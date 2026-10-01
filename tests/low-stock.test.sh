#!/usr/bin/env bash
# Fase 2D — badge stok menipis (plan 0006).
# Cara pakai: bash tests/low-stock.test.sh <BASE_URL> [ADMIN_EMAIL] [ADMIN_PASSWORD]
# WAJIB dijalankan terhadap DB throwaway (bukan produksi).
#
# Yang diuji: ambang batas benar-benar dipakai, `low_stock` dihitung SERVER
# (bukan browser), dan berubah begitu stok diubah.
set -uo pipefail

BASE="${1:-http://127.0.0.1:8881}"
EMAIL="${2:-admin@test.local}"
PASS="${3:-Test-Passw0rd-2026-Str0ng}"
JAR="$(mktemp)"

pass=0; fail=0
ok()   { pass=$((pass+1)); printf '  \033[32mPASS\033[0m %s\n' "$1"; }
bad()  { fail=$((fail+1)); printf '  \033[31mFAIL\033[0m %s\n' "$1"; }
check(){ [ "$2" = "$3" ] && ok "$1 ($2)" || bad "$1 — dapat '$2', harus '$3'"; }

req() {
  local method="$1" path="$2" body="${3:-}"
  if [ -n "$body" ]; then
    curl -s -o /tmp/ls_body.json -w '%{http_code}' -X "$method" -b "$JAR" -c "$JAR" \
      -H 'Content-Type: application/json' -d "$body" "$BASE/api$path"
  else
    curl -s -o /tmp/ls_body.json -w '%{http_code}' -X "$method" -b "$JAR" -c "$JAR" "$BASE/api$path"
  fi
}
jq_get() { python3 -c "import json,sys; d=json.load(open('/tmp/ls_body.json')); print($1)" 2>/dev/null; }

echo "═══ Fase 2D — badge stok menipis ═══"

code=$(curl -s -o /tmp/ls_login.json -w '%{http_code}' -c "$JAR" -H 'Content-Type: application/json' \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASS\"}" "$BASE/api/auth/login")
[ "$code" = "200" ] || { echo "  login gagal ($code)"; exit 1; }
echo "  login OK"

# ---- siapkan produk + varian dengan stok bisa diatur ----
PRODUCT=$(curl -s -b "$JAR" -c "$JAR" -H 'Content-Type: application/json' \
  -d "{\"category_id\":1,\"name\":\"Uji Stok $RANDOM\",\"slug\":\"uji-stok-$RANDOM\",\"sku\":\"US-$RANDOM\",\"description\":\"uji\",\"material\":\"uji\",\"construction\":\"uji\",\"gsm\":150,\"width\":\"150 cm\",\"weight_per_yard\":\"200 g/yard\",\"recommended_usage\":\"uji\",\"status\":\"active\"}" \
  "$BASE/api/admin/products")
PID=$(printf '%s' "$PRODUCT" | python3 -c 'import sys,json; print(json.load(sys.stdin)["product"]["id"])' 2>/dev/null)
[ -n "$PID" ] || { echo "  gagal bikin produk"; exit 1; }
SLUG=$(curl -s -b "$JAR" "$BASE/api/admin/products" | python3 -c "import sys,json; print([p['slug'] for p in json.load(sys.stdin)['products'] if p['id']==$PID][0])")
COLOR=$(curl -s -b "$JAR" "$BASE/api/admin/colors" | python3 -c 'import sys,json; print(json.load(sys.stdin)["colors"][0]["id"])')

# stok awal 50, ambang 5 → TIDAK menipis
V=$(curl -s -b "$JAR" -c "$JAR" -H 'Content-Type: application/json' \
  -d "{\"color_id\":$COLOR,\"sku\":\"US-$PID-$RANDOM\",\"price\":100000,\"wholesale_price\":90000,\"stock\":50,\"low_stock_threshold\":5}" \
  "$BASE/api/admin/products/$PID/variants")
VID=$(printf '%s' "$V" | python3 -c 'import sys,json; print(json.load(sys.stdin)["variant"]["id"])' 2>/dev/null)
[ -n "$VID" ] || { echo "  gagal bikin varian"; exit 1; }
echo "  produk #$PID varian #$VID"

prod_field() { curl -s -m 8 -b "$JAR" "$BASE/api/admin/products" | python3 -c "import sys,json; d=[p for p in json.load(sys.stdin)['products'] if p['id']==$PID][0]; print(d.get('$1'))"; }
var_field()  { curl -s -m 8 -b "$JAR" "$BASE/api/admin/products/$PID/variants" | python3 -c "import sys,json; d=[v for v in json.load(sys.stdin)['variants'] if v['id']==$VID][0]; print(d.get('$1'))"; }

# ---- 1. field baru ada di API ----
check "1a. produk punya low_stock_threshold" "$(prod_field low_stock_threshold)" "5"
check "1b. produk punya low_stock" "$(prod_field low_stock)" "False"
check "1c. varian punya low_stock_threshold" "$(var_field low_stock_threshold)" "5"

# ---- 2. stok 50 vs ambang 5 → TIDAK menipis ----
check "2. stok 50 > ambang 5 → low_stock False" "$(prod_field low_stock)" "False"

# ---- 3. stok diturunkan ke 5 (= ambang) → menipis (<=, bukan <) ----
req PATCH "/admin/inventory/$VID" '{"stock":5}' > /dev/null
check "3a. stok 5 = ambang → low_stock True" "$(prod_field low_stock)" "True"
check "3b. available_stock ikut benar" "$(prod_field available_stock)" "5"

# ---- 4. stok 6 (> ambang) → tidak menipis lagi ----
req PATCH "/admin/inventory/$VID" '{"stock":6}' > /dev/null
check "4. stok 6 > ambang 5 → low_stock False" "$(prod_field low_stock)" "False"

# ---- 5. stok 0 → menipis ----
req PATCH "/admin/inventory/$VID" '{"stock":0}' > /dev/null
check "5. stok 0 → low_stock True" "$(prod_field low_stock)" "True"

# ---- 6. ambang dinaikkan → ikut berubah (ambang benar-benar dibaca) ----
req PATCH "/admin/inventory/$VID" '{"stock":20,"low_stock_threshold":50}' > /dev/null
check "6a. ambang jadi 50" "$(prod_field low_stock_threshold)" "50"
check "6b. stok 20 <= ambang 50 → menipis" "$(prod_field low_stock)" "True"
req PATCH "/admin/inventory/$VID" '{"stock":80,"low_stock_threshold":50}' > /dev/null
check "6c. stok 80 > ambang 50 → tidak menipis" "$(prod_field low_stock)" "False"

# ---- 7. produk TANPA varian → low_stock null/false, tidak error ----
P2=$(curl -s -b "$JAR" -c "$JAR" -H 'Content-Type: application/json' \
  -d "{\"category_id\":1,\"name\":\"Uji Kosong $RANDOM\",\"slug\":\"uji-kosong-$RANDOM\",\"sku\":\"UK-$RANDOM\",\"description\":\"uji\",\"material\":\"uji\",\"construction\":\"uji\",\"gsm\":150,\"width\":\"150 cm\",\"weight_per_yard\":\"200 g/yard\",\"recommended_usage\":\"uji\",\"status\":\"active\"}" \
  "$BASE/api/admin/products" | python3 -c 'import sys,json; print(json.load(sys.stdin)["product"]["id"])')
check "7. produk tanpa varian → low_stock False" "$(curl -s -m 8 -b "$JAR" "$BASE/api/admin/products" | python3 -c "import sys,json; d=[p for p in json.load(sys.stdin)['products'] if p['id']==$P2][0]; print(d.get('low_stock'))")" "False"

# ---- 8. dashboard menghitung yang menipis ----
req PATCH "/admin/inventory/$VID" '{"stock":1,"low_stock_threshold":5}' > /dev/null
code=$(req GET /admin/dashboard)
check "8a. dashboard → 200" "$code" "200"
N=$(jq_get "d['lowStock']")
case "$N" in ''|*[!0-9]*) bad "8b. dashboard lowStock bukan angka ('$N')";; *) [ "$N" -ge 1 ] && ok "8b. dashboard hitung stok menipis ($N)" || bad "8b. dashboard lowStock = $N, harus >= 1";; esac

# ---- 9. endpoint publik juga bawa low_stock (konsisten) ----
PUB=$(curl -s -m 8 "$BASE/api/products/$SLUG")
check "9a. endpoint publik punya low_stock" "$(printf '%s' "$PUB" | python3 -c 'import sys,json; print(json.load(sys.stdin)["product"].get("low_stock"))')" "True"
check "9b. endpoint publik punya low_stock_threshold" "$(printf '%s' "$PUB" | python3 -c 'import sys,json; print(json.load(sys.stdin)["product"].get("low_stock_threshold"))')" "5"

# ---- 10. UI: badge & token ada ----
HTML=$(curl -s -m 8 "$BASE/admin/produk")
BUNDLE=$(printf '%s' "$HTML" | grep -oE '/assets/adminProducts-[A-Za-z0-9_-]+\.js' | head -1)
JS=$(curl -s -m 8 "$BASE$BUNDLE")
for marker in 'badge--low-stock' 'low_stock' 'Menipis'; do
  case "$JS" in *"$marker"*) ok "10. bundle punya '$marker'";; *) bad "10. bundle tidak punya '$marker'";; esac
done
CSS=$(curl -s -m 8 "$BASE/admin/produk" | grep -oE '/assets/store-[A-Za-z0-9_-]+\.css' | head -1)
CSSJS=$(curl -s -m 8 "$BASE$CSS")
case "$CSSJS" in *'--status-low-stock'*) ok "10. CSS punya token --status-low-stock";; *) bad "10. CSS tidak punya token";; esac
case "$CSSJS" in *'.badge--low-stock'*) ok "10. CSS punya .badge--low-stock";; *) bad "10. CSS tidak punya .badge--low-stock";; esac

# ---- 11. varian: low_stock dihitung server, & simpan stok saja tetap jalan ----
# (dulu PATCH stok tanpa low_stock_threshold → 500 karena sql.js menolak undefined)
req PATCH "/admin/inventory/$VID" '{"stock":2,"low_stock_threshold":5}' > /dev/null
check "11a. varian low_stock True (server)" "$(var_field low_stock)" "True"
code=$(req PATCH "/admin/inventory/$VID" '{"stock":9}')
check "11b. PATCH stok SAJA → 200 (bukan 500)" "$code" "200"
check "11c. ambang tidak ikut berubah" "$(var_field low_stock_threshold)" "5"
check "11d. stok jadi 9" "$(var_field stock)" "9"
check "11e. stok 9 > ambang 5 → low_stock False" "$(var_field low_stock)" "False"

# ---- 12. ambang tidak boleh negatif / bukan angka ----
code=$(req PATCH "/admin/inventory/$VID" '{"stock":9,"low_stock_threshold":-1}')
check "12a. ambang negatif → 400" "$code" "400"
code=$(req PATCH "/admin/inventory/$VID" '{"stock":9,"low_stock_threshold":"abc"}')
check "12b. ambang bukan angka → 400" "$code" "400"

rm -f "$JAR" /tmp/ls_body.json /tmp/ls_login.json
echo
echo "═══ 2D: $pass PASS / $fail FAIL ═══"
[ "$fail" -eq 0 ] || exit 1
