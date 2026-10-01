#!/usr/bin/env bash
# Fase 2C — kelola kategori & warna (plan 0006).
# Cara pakai: bash tests/catalog.test.sh <BASE_URL> [ADMIN_EMAIL] [ADMIN_PASSWORD]
# WAJIB dijalankan terhadap DB throwaway (bukan produksi).
#
# Yang diuji paling penting: hapus yang MASIH DIPAKAI harus 409 dan datanya
# benar-benar tidak berubah. Kalau ini bocor, produk jadi yatim.
set -uo pipefail

BASE="${1:-http://127.0.0.1:8881}"
EMAIL="${2:-admin@test.local}"
PASS="${3:-Test-Passw0rd-2026-Str0ng}"
JAR="$(mktemp)"

pass=0; fail=0
ok()   { pass=$((pass+1)); printf '  \033[32mPASS\033[0m %s\n' "$1"; }
bad()  { fail=$((fail+1)); printf '  \033[31mFAIL\033[0m %s\n' "$1"; }
check(){ [ "$2" = "$3" ] && ok "$1 ($2)" || bad "$1 — dapat '$2', harus '$3'"; }

req() { # method path [body]
  local method="$1" path="$2" body="${3:-}"
  if [ -n "$body" ]; then
    curl -s -o /tmp/cat_body.json -w '%{http_code}' -X "$method" -b "$JAR" -c "$JAR" \
      -H 'Content-Type: application/json' -d "$body" "$BASE/api$path"
  else
    curl -s -o /tmp/cat_body.json -w '%{http_code}' -X "$method" -b "$JAR" -c "$JAR" "$BASE/api$path"
  fi
}
jq_get() { python3 -c "import json,sys; d=json.load(open('/tmp/cat_body.json')); print($1)" 2>/dev/null; }

echo "═══ Fase 2C — kelola kategori & warna ═══"

code=$(curl -s -o /tmp/cat_login.json -w '%{http_code}' -c "$JAR" -H 'Content-Type: application/json' \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASS\"}" "$BASE/api/auth/login")
[ "$code" = "200" ] || { echo "  login gagal ($code)"; exit 1; }
echo "  login OK"

# ---- 1. GET /admin/catalog ada jumlah pemakai ----
code=$(req GET /admin/catalog)
check "1a. GET /admin/catalog → 200" "$code" "200"
CATS=$(jq_get "len(d['categories'])")
COLS=$(jq_get "len(d['colors'])")
[ "$CATS" -ge 1 ] && ok "1b. kategori terdaftar ($CATS)" || bad "1b. nol kategori"
[ "$COLS" -ge 1 ] && ok "1c. warna terdaftar ($COLS)" || bad "1c. nol warna"
HAS_USAGE=$(jq_get "'usage_count' in d['categories'][0] and 'usage_count' in d['colors'][0]")
check "1d. ada usage_count di kategori & warna" "$HAS_USAGE" "True"
USED=$(jq_get "d['categories'][0]['usage_count']")
[ "$USED" -ge 1 ] && ok "1e. kategori seed terhitung dipakai ($USED)" || bad "1e. usage_count kategori seed = $USED"

# ---- 2. HAPUS yang masih dipakai → 409 + data tidak berubah ----
CID=$(jq_get "d['categories'][0]['id']")
PROD_BEFORE=$(curl -s -m 8 -b "$JAR" "$BASE/api/admin/products" | python3 -c 'import sys,json; print(len(json.load(sys.stdin)["products"]))')
code=$(req DELETE "/admin/categories/$CID")
check "2a. hapus kategori terpakai → 409" "$code" "409"
check "2b. pesan menyebut jumlah pemakai" "$(jq_get "'dipakai' in d['error'] and 'produk' in d['error']")" "True"
check "2c. usage_count ikut dikirim" "$(jq_get "d.get('usage_count',0)>=1")" "True"
PROD_AFTER=$(curl -s -m 8 -b "$JAR" "$BASE/api/admin/products" | python3 -c 'import sys,json; print(len(json.load(sys.stdin)["products"]))')
check "2d. jumlah produk TIDAK berubah" "$PROD_AFTER" "$PROD_BEFORE"

WID=$(curl -s -m 8 -b "$JAR" "$BASE/api/admin/catalog" | python3 -c 'import sys,json; print(json.load(sys.stdin)["colors"][0]["id"])')
code=$(req DELETE "/admin/colors/$WID")
check "3a. hapus warna terpakai → 409" "$code" "409"
check "3b. pesan menyebut varian" "$(jq_get "'varian' in d['error']")" "True"

# ---- 4. Kategori BARU (tidak dipakai) → boleh dihapus ----
code=$(req POST /admin/categories "{\"name\":\"Uji Hapus $RANDOM\",\"slug\":\"uji-hapus-$RANDOM\"}")
check "4a. tambah kategori → 201" "$code" "201"
NCID=$(jq_get "d['category']['id']")
code=$(req DELETE "/admin/categories/$NCID")
check "4b. hapus kategori tak terpakai → 200" "$code" "200"
code=$(req DELETE "/admin/categories/$NCID")
check "4c. hapus lagi → 404" "$code" "404"

# ---- 5. Warna BARU → boleh dihapus ----
code=$(req POST /admin/colors "{\"name\":\"Uji Warna $RANDOM\",\"code\":\"UW-$RANDOM\"}")
check "5a. tambah warna → 201" "$code" "201"
NWID=$(jq_get "d['color']['id']")
code=$(req DELETE "/admin/colors/$NWID")
check "5b. hapus warna tak terpakai → 200" "$code" "200"
code=$(req DELETE "/admin/colors/$NWID")
check "5c. hapus lagi → 404" "$code" "404"

# ---- 6. PATCH warna (baru di 2C) ----
code=$(req POST /admin/colors "{\"name\":\"Warna Ubah $RANDOM\",\"code\":\"WU-$RANDOM\"}")
PWID=$(jq_get "d['color']['id']")
code=$(req PATCH "/admin/colors/$PWID" "{\"name\":\"Warna Sudah Diubah\",\"code\":\"WSD-$RANDOM\"}")
check "6a. PATCH warna → 200" "$code" "200"
NEWNAME=$(curl -s -m 8 -b "$JAR" "$BASE/api/admin/catalog" | python3 -c "import sys,json; print([c['name'] for c in json.load(sys.stdin)['colors'] if c['id']==$PWID][0])")
check "6b. nama warna tersimpan" "$NEWNAME" "Warna Sudah Diubah"
code=$(req PATCH "/admin/colors/99999999" "{\"name\":\"X\",\"code\":\"Y\"}")
check "6c. PATCH warna tidak ada → 404" "$code" "404"
code=$(req PATCH "/admin/colors/$PWID" "{\"name\":\"\",\"code\":\"\"}")
check "6d. PATCH warna kosong → 400" "$code" "400"
curl -s -m 8 -o /dev/null -b "$JAR" -X DELETE "$BASE/api/admin/colors/$PWID"

# ---- 7. PATCH kategori: slug bentrok → 409 (bukan 500) ----
code=$(req POST /admin/categories "{\"name\":\"Kat A $RANDOM\",\"slug\":\"kat-a-$RANDOM\"}")
K1=$(jq_get "d['category']['id']"); S1=$(jq_get "d['category']['slug']")
code=$(req POST /admin/categories "{\"name\":\"Kat B $RANDOM\",\"slug\":\"kat-b-$RANDOM\"}")
K2=$(jq_get "d['category']['id']")
code=$(req PATCH "/admin/categories/$K2" "{\"name\":\"Kat B\",\"slug\":\"$S1\"}")
check "7a. slug bentrok → 409 (bukan 500)" "$code" "409"
check "7b. slug K1 tidak berubah" "$(curl -s -m 8 -b "$JAR" "$BASE/api/admin/catalog" | python3 -c "import sys,json; print([c['slug'] for c in json.load(sys.stdin)['categories'] if c['id']==$K1][0])")" "$S1"
curl -s -m 8 -o /dev/null -b "$JAR" -X DELETE "$BASE/api/admin/categories/$K1"
curl -s -m 8 -o /dev/null -b "$JAR" -X DELETE "$BASE/api/admin/categories/$K2"

# ---- 8. Duplikat saat tambah ----
DUPCODE=$(curl -s -m 8 -b "$JAR" "$BASE/api/admin/catalog" | python3 -c 'import sys,json; print(json.load(sys.stdin)["colors"][0]["code"])')
code=$(req POST /admin/colors "{\"name\":\"Duplikat\",\"code\":\"$DUPCODE\"}")
check "8a. kode warna duplikat → 409" "$code" "409"
DUPSLUG=$(curl -s -m 8 -b "$JAR" "$BASE/api/admin/catalog" | python3 -c 'import sys,json; print(json.load(sys.stdin)["categories"][0]["slug"])')
code=$(req POST /admin/categories "{\"name\":\"Duplikat\",\"slug\":\"$DUPSLUG\"}")
check "8b. slug kategori duplikat → 409" "$code" "409"

# ---- 9. Wajib login ----
for ep in "GET /admin/catalog" "DELETE /admin/categories/1" "DELETE /admin/colors/1" "PATCH /admin/colors/1"; do
  M="${ep%% *}"; P="${ep#* }"
  C=$(curl -s -o /dev/null -w '%{http_code}' -X "$M" -H 'Content-Type: application/json' -d '{"name":"x","code":"y"}' "$BASE/api$P")
  check "9. tamu $M $P → 401" "$C" "401"
done

# ---- 10. UI: daftar + tombol ubah/hapus di HTML & bundle ----
HTML=$(curl -s -m 8 "$BASE/admin/produk")
for marker in 'category-list' 'color-list' 'catalog-lists'; do
  case "$HTML" in *"$marker"*) ok "10. HTML punya '$marker'";; *) bad "10. HTML tidak punya '$marker'";; esac
done
BUNDLE=$(curl -s -m 8 "$BASE/admin/produk" | grep -oE '/assets/adminProducts-[A-Za-z0-9_-]+\.js' | head -1)
JS=$(curl -s -m 8 "$BASE$BUNDLE")
for marker in '/admin/catalog' 'data-row' 'data-edit-name' 'data-edit-extra' 'dipakai'; do
  case "$JS" in *"$marker"*) ok "10. bundle punya '$marker'";; *) bad "10. bundle tidak punya '$marker'";; esac
done

rm -f "$JAR" /tmp/cat_body.json /tmp/cat_login.json
echo
echo "═══ 2C: $pass PASS / $fail FAIL ═══"
[ "$fail" -eq 0 ] || exit 1
