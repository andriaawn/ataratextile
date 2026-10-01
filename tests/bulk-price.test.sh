#!/usr/bin/env bash
# Fase 2B — bulk ubah harga varian (plan 0006).
#
# Server uji dijalankan oleh /tmp/atara_setup6.sh di port 8881 dengan DB throwaway.
# PENTING: server rate limit 120 request/menit per IP. Jalankan lewat
# /tmp/atara_run_all.sh yang me-restart server antar suite, atau tunggu 1 menit
# kalau suite ini dijalankan berulang.
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
    curl -s -o /tmp/bulk_body.json -w '%{http_code}' -X "$method" -b "$JAR" -c "$JAR" \
      -H 'Content-Type: application/json' -d "$body" "$BASE/api$path"
  else
    curl -s -o /tmp/bulk_body.json -w '%{http_code}' -X "$method" -b "$JAR" -c "$JAR" "$BASE/api$path"
  fi
}

echo "═══ Fase 2B — bulk ubah harga ═══"

# ---- autentikasi ----
code=$(curl -s -o /tmp/bulk_login.json -w '%{http_code}' -c "$JAR" \
  -H 'Content-Type: application/json' \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASS\"}" "$BASE/api/auth/login")
if [ "$code" != "200" ]; then echo "  login gagal ($code) — server uji jalan?"; cat /tmp/bulk_login.json; exit 1; fi
echo "  login OK"

# ---- siapkan produk uji dengan 3 varian harga berbeda ----
# POST /api/admin/products wajib field lengkap (bukan cuma name/slug/price).
PRODUCT=$(curl -s -b "$JAR" -c "$JAR" -H 'Content-Type: application/json' \
  -d "{\"category_id\":1,\"name\":\"Uji Bulk $RANDOM\",\"slug\":\"uji-bulk-$RANDOM\",\"sku\":\"UB-$RANDOM\",\"description\":\"uji\",\"material\":\"uji\",\"construction\":\"uji\",\"gsm\":150,\"width\":\"150 cm\",\"weight_per_yard\":\"200 g/yard\",\"recommended_usage\":\"uji\",\"status\":\"draft\"}" \
  "$BASE/api/admin/products")
PID=$(printf '%s' "$PRODUCT" | python3 -c 'import sys,json; print(json.load(sys.stdin)["product"]["id"])' 2>/dev/null)
if [ -z "$PID" ]; then echo "  gagal bikin produk uji"; printf '%s\n' "$PRODUCT"; exit 1; fi
echo "  produk uji #$PID"

# color_id diambil dari DB (jangan asumsi 1..3 selalu ada).
COLOR_IDS=$(curl -s -b "$JAR" -c "$JAR" "$BASE/api/admin/colors" | python3 -c 'import sys,json; print(" ".join(str(c["id"]) for c in json.load(sys.stdin)["colors"][:3]))')
COLORS=($COLOR_IDS)
if [ "${#COLORS[@]}" -lt 3 ]; then echo "  butuh 3 warna di DB uji, ada ${#COLORS[@]}"; exit 1; fi

VAR_IDS=()
for i in 0 1 2; do
  V=$(curl -s -b "$JAR" -c "$JAR" -H 'Content-Type: application/json' \
    -d "{\"color_id\":${COLORS[$i]},\"sku\":\"UB-$PID-$i-$RANDOM\",\"price\":$((100000*(i+1))),\"wholesale_price\":$((90000*(i+1))),\"stock\":5}" \
    "$BASE/api/admin/products/$PID/variants")
  VID=$(printf '%s' "$V" | python3 -c 'import sys,json; print(json.load(sys.stdin)["variant"]["id"])' 2>/dev/null)
  [ -n "$VID" ] && VAR_IDS+=("$VID")
done
echo "  varian: ${VAR_IDS[*]}"
[ "${#VAR_IDS[@]}" -eq 3 ] || { echo "  gagal bikin 3 varian"; exit 1; }

IDS_JSON="[${VAR_IDS[0]},${VAR_IDS[1]},${VAR_IDS[2]}]"
price_of() { curl -s -b "$JAR" -c "$JAR" "$BASE/api/admin/products/$PID/variants" | python3 -c "import sys,json;d=json.load(sys.stdin)['variants'];print([v['price'] for v in d if v['id']==$1][0])"; }

# ---- 1. percent +10% ----
base1=$(price_of "${VAR_IDS[0]}")
code=$(req POST /admin/variants/bulk-price "{\"variant_ids\":$IDS_JSON,\"mode\":\"percent\",\"value\":10,\"field\":\"price\"}")
check "1. percent +10% → 200" "$code" "200"
check "1. updated = 3" "$(python3 -c 'import json;print(json.load(open("/tmp/bulk_body.json"))["updated"])')" "3"
after1=$(price_of "${VAR_IDS[0]}")
check "1. harga 100000 +10% = 110000" "$after1" "110000"

# ---- 2. amount +5000 ----
code=$(req POST /admin/variants/bulk-price "{\"variant_ids\":$IDS_JSON,\"mode\":\"amount\",\"value\":5000,\"field\":\"price\"}")
check "2. amount +5000 → 200" "$code" "200"
check "2. 110000 +5000 = 115000" "$(price_of "${VAR_IDS[0]}")" "115000"

# ---- 3. set harga sama ----
code=$(req POST /admin/variants/bulk-price "{\"variant_ids\":$IDS_JSON,\"mode\":\"set\",\"value\":777000,\"field\":\"price\"}")
check "3. set 777000 → 200" "$code" "200"
check "3. semua jadi 777000" "$(price_of "${VAR_IDS[1]}")" "777000"

# ---- 4. field both ----
code=$(req POST /admin/variants/bulk-price "{\"variant_ids\":[${VAR_IDS[0]}],\"mode\":\"percent\",\"value\":-50,\"field\":\"both\"}")
check "4. field both → 200" "$code" "200"
WH=$(curl -s -b "$JAR" -c "$JAR" "$BASE/api/admin/products/$PID/variants" | python3 -c "import sys,json;d=json.load(sys.stdin)['variants'];print([v['wholesale_price'] for v in d if v['id']==${VAR_IDS[0]}][0])")
check "4. grosir 90000 -50% = 45000" "$WH" "45000"

# ---- 5. dry_run tidak mengubah apa pun ----
before5=$(price_of "${VAR_IDS[0]}")
code=$(req POST /admin/variants/bulk-price "{\"variant_ids\":$IDS_JSON,\"mode\":\"set\",\"value\":1,\"field\":\"price\",\"dry_run\":true}")
check "5. dry_run → 200" "$code" "200"
check "5. dry_run updated = 3" "$(python3 -c 'import json;print(json.load(open("/tmp/bulk_body.json"))["updated"])')" "3"
check "5. harga TIDAK berubah" "$(price_of "${VAR_IDS[0]}")" "$before5"

# ---- 6. VALIDASI ----
code=$(req POST /admin/variants/bulk-price "{\"variant_ids\":[],\"mode\":\"set\",\"value\":100}")
check "6a. daftar kosong → 400" "$code" "400"
code=$(req POST /admin/variants/bulk-price "{\"variant_ids\":$IDS_JSON,\"mode\":\"salah\",\"value\":10}")
check "6b. mode ngawur → 400" "$code" "400"
code=$(req POST /admin/variants/bulk-price "{\"variant_ids\":$IDS_JSON,\"mode\":\"set\",\"value\":0}")
check "6c. set 0 → 400" "$code" "400"
code=$(req POST /admin/variants/bulk-price "{\"variant_ids\":$IDS_JSON,\"mode\":\"set\",\"value\":-5000}")
check "6d. set negatif → 400" "$code" "400"
code=$(req POST /admin/variants/bulk-price "{\"variant_ids\":$IDS_JSON,\"mode\":\"percent\",\"value\":-150}")
check "6e. percent -150% → 400" "$code" "400"
code=$(req POST /admin/variants/bulk-price "{\"variant_ids\":$IDS_JSON,\"mode\":\"set\",\"value\":\"abc\"}")
check "6f. nilai bukan angka → 400" "$code" "400"
code=$(req POST /admin/variants/bulk-price "{\"variant_ids\":[99999999],\"mode\":\"set\",\"value\":100}")
check "6g. varian tidak ada → 404" "$code" "404"

# ---- 7. ATOMIK: satu harga jadi <= 0 → tidak ada yang berubah ----
# Varian ke-3 dibuat sangat murah, lalu kita potong nominal besar → harus ditolak SEMUA.
curl -s -o /dev/null -b "$JAR" -c "$JAR" -H 'Content-Type: application/json' -X PATCH \
  -d '{"price":100,"wholesale_price":90}' "$BASE/api/admin/variants/${VAR_IDS[2]}"
snap1=$(price_of "${VAR_IDS[0]}"); snap3=$(price_of "${VAR_IDS[2]}")
code=$(req POST /admin/variants/bulk-price "{\"variant_ids\":$IDS_JSON,\"mode\":\"amount\",\"value\":-5000,\"field\":\"price\"}")
check "7a. satu varian jadi minus → 400" "$code" "400"
check "7b. varian lain TIDAK berubah" "$(price_of "${VAR_IDS[0]}")" "$snap1"
check "7c. varian minus juga tidak berubah" "$(price_of "${VAR_IDS[2]}")" "$snap3"

# ---- 8. varian id duplikat & sampah ----
code=$(req POST /admin/variants/bulk-price "{\"variant_ids\":[${VAR_IDS[0]},${VAR_IDS[0]},\"abc\",null],\"mode\":\"amount\",\"value\":1000,\"field\":\"price\"}")
check "8a. id duplikat/sampah → 200" "$code" "200"
check "8b. hanya 1 varian unik diproses" "$(python3 -c 'import json;print(json.load(open("/tmp/bulk_body.json"))["updated"])')" "1"

# ---- 9. endpoint wajib login ----
code=$(curl -s -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' \
  -d "{\"variant_ids\":$IDS_JSON,\"mode\":\"set\",\"value\":1}" "$BASE/api/admin/variants/bulk-price")
check "9. tanpa login → 401" "$code" "401"

# ---- 10. UI: panel bulk + tombol pratinjau ada di HTML & bundle ----
HTML=$(curl -s -m 8 "$BASE/admin/produk")
for marker in 'bulk-panel' 'bulk-preview' 'bulk-apply' 'bulk-field' 'bulk-mode' 'Pilih semua varian' 'Lihat pratinjau'; do
  case "$HTML" in *"$marker"*) ok "10. HTML punya '$marker'";; *) bad "10. HTML tidak punya '$marker'";; esac
done
BUNDLE=$(curl -s -m 8 "$BASE/admin/produk" | grep -oE '/assets/adminProducts-[A-Za-z0-9_-]+\.js' | head -1)
JS=$(curl -s -m 8 "$BASE$BUNDLE")
for marker in 'bulk-price' 'data-pick' 'dry_run' 'dataset.pending'; do
  case "$JS" in *"$marker"*) ok "10. bundle punya '$marker'";; *) bad "10. bundle tidak punya '$marker'";; esac
done

rm -f "$JAR" /tmp/bulk_body.json /tmp/bulk_login.json
echo
echo "═══ 2B: $pass PASS / $fail FAIL ═══"
[ "$fail" -eq 0 ] || exit 1
