#!/usr/bin/env bash
# Test plan 0015 — Sample request: sambungkan jalur yang setengah hidup.
# Inti: form storefront → baris DB → terlihat & bisa diubah admin.
# WAJIB di DB throwaway.
set -u
BASE="${1:-http://127.0.0.1:8895}"
ADMIN_EMAIL="${2:-${ADMIN_EMAIL:-admin@test.local}}"
ADMIN_PASSWORD="${3:-${ADMIN_PASSWORD:-}}"
PASS=0; FAIL=0
ok()  { echo "  ✅ PASS  $1"; PASS=$((PASS+1)); }
bad() { echo "  ❌ FAIL  $1"; FAIL=$((FAIL+1)); }
PY() { python3 -c "$1" 2>/dev/null; }
COOKIE=$(mktemp)

echo "=== 0015: sample request ($BASE) ==="

# ---- produk asli (untuk product_id) ----
PROD=$(curl -s -m 8 "$BASE/api/products" | PY 'import json,sys; d=json.load(sys.stdin); p=(d.get("products") or []); print(p[0]["id"] if p else "")')
[ -n "$PROD" ] && ok "Produk asli (id=$PROD)" || { bad "Produk tidak ditemukan"; exit 1; }

post_sample() { curl -s -m 8 -X POST "$BASE/api/samples" -H 'Content-Type: application/json' -d "$1"; }

# ---- 1. POST valid → 201 ----
CODE=$(curl -s -m 8 -o /dev/null -w '%{http_code}' -X POST "$BASE/api/samples" -H 'Content-Type: application/json' \
  -d "{\"customer_name\":\"Sari Test\",\"email\":\"sari@test.local\",\"phone\":\"08120000009\",\"product_id\":$PROD,\"color\":\"Navy\",\"quantity\":2,\"address\":\"Jl Sample 1, Bandung\"}")
[ "$CODE" = "201" ] && ok "1. POST sample valid → 201" || bad "1. POST valid = $CODE (harus 201)"

# ---- 2. POST body kosong → 400 ----
CODE=$(curl -s -m 8 -o /dev/null -w '%{http_code}' -X POST "$BASE/api/samples" -H 'Content-Type: application/json' -d '{}')
[ "$CODE" = "400" ] && ok "2. POST kosong ditolak → 400" || bad "2. POST kosong = $CODE (harus 400)"

# ---- 3. GET admin samples tanpa login → 401 ----
CODE=$(curl -s -m 8 -o /dev/null -w '%{http_code}' "$BASE/api/admin/samples")
[ "$CODE" = "401" ] && ok "3. GET admin/samples tanpa login → 401" || bad "3. tanpa login = $CODE (harus 401)"

# ---- login admin ----
curl -s -m 8 -c "$COOKIE" -X POST "$BASE/api/auth/login" -H 'Content-Type: application/json' \
  -d "{\"email\":\"$ADMIN_EMAIL\",\"password\":\"$ADMIN_PASSWORD\"}" >/dev/null 2>&1

# ---- 4. GET admin samples (login) → 200 + berisi sample baru ----
BODY=$(curl -s -m 8 -b "$COOKIE" "$BASE/api/admin/samples")
CODE=$(curl -s -m 8 -o /dev/null -w '%{http_code}' -b "$COOKIE" "$BASE/api/admin/samples")
N=$(echo "$BODY" | PY 'import json,sys; print(len(json.load(sys.stdin).get("samples") or []))')
HAS=$(echo "$BODY" | PY 'import json,sys; d=json.load(sys.stdin); print(1 if any(s.get("customer_name")=="Sari Test" for s in (d.get("samples") or [])) else 0)')
[ "$CODE" = "200" ] && [ "${N:-0}" -ge 1 ] && [ "$HAS" = "1" ] && ok "4. admin lihat sample ($N baris, ada 'Sari Test')" || bad "4. admin/samples n=$N has=$HAS"

# ---- 5. PATCH status → 200 + tersimpan ----
SID=$(echo "$BODY" | PY 'import json,sys; d=json.load(sys.stdin); s=[x for x in (d.get("samples") or []) if x.get("customer_name")=="Sari Test"]; print(s[0]["id"] if s else "")')
if [ -n "$SID" ]; then
  CODE=$(curl -s -m 8 -o /dev/null -w '%{http_code}' -b "$COOKIE" -X PATCH "$BASE/api/admin/samples/$SID" -H 'Content-Type: application/json' -d '{"status":"contacted"}')
  NEWST=$(curl -s -m 8 -b "$COOKIE" "$BASE/api/admin/samples" | PY "import json,sys; d=json.load(sys.stdin); s=[x for x in (d.get('samples') or []) if x.get('id')==$SID]; print(s[0]['status'] if s else '')")
  [ "$CODE" = "200" ] && [ "$NEWST" = "contacted" ] && ok "5. PATCH status → contacted tersimpan" || bad "5. PATCH=$CODE status=$NEWST"
else
  bad "5. sample id tidak ditemukan"
fi

# ---- 6. PATCH status invalid → 400 ----
CODE=$(curl -s -m 8 -o /dev/null -w '%{http_code}' -b "$COOKIE" -X PATCH "$BASE/api/admin/samples/$SID" -H 'Content-Type: application/json' -d '{"status":"ngawur"}')
[ "$CODE" = "400" ] && ok "6. status invalid → 400" || bad "6. status invalid = $CODE (harus 400)"

# ---- 7. halaman /admin/sample dilayani → 200 ----
CODE=$(curl -s -m 8 -o /dev/null -w '%{http_code}' "$BASE/admin/sample")
[ "$CODE" = "200" ] && ok "7. halaman /admin/sample → 200" || bad "7. /admin/sample = $CODE (harus 200)"

# ---- 8. bundle store memuat form sample (POST /samples) ----
# Ambil SEMUA bundle JS yang direferensikan halaman, cek apakah ada pemanggil /samples.
ASSETS=$(curl -s -m 8 "$BASE/admin/sample" | PY 'import sys,re; print(" ".join(re.findall(r"/assets/[^\"]+\.js", sys.stdin.read())))')
ASSETS="$ASSETS $(curl -s -m 8 "$BASE/katalog" | PY 'import sys,re; print(" ".join(re.findall(r"/assets/[^\"]+\.js", sys.stdin.read())))')"
FOUND=0
for b in $ASSETS; do
  if curl -s -m 8 "$BASE$b" | grep -q "/samples"; then FOUND=1; fi
done
[ "$FOUND" = "1" ] && ok "8. bundle store memuat form sample (POST /samples)" || bad "8. bundle tidak memuat form sample"

# ---- 9. dashboard merender KPI 'Sample baru' (bukan field server) ----
FOUND=0
for b in $ASSETS; do
  if curl -s -m 8 "$BASE$b" | grep -q "Sample baru"; then FOUND=1; fi
done
[ "$FOUND" = "1" ] && ok "9. dashboard merender KPI 'Sample baru'" || bad "9. KPI 'Sample baru' tidak dirender"

rm -f "$COOKIE"
echo
echo "=== HASIL: $PASS PASS / $FAIL FAIL ==="
[ "$FAIL" -eq 0 ]
