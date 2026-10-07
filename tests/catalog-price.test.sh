#!/usr/bin/env bash
# Test plan 0014 Fix A — harga katalog dari DB (bukan rumus 825000+gsm*1000).
# WAJIB di DB throwaway.
set -u
BASE="${1:-http://127.0.0.1:8877}"
PASS=0; FAIL=0
ok()  { echo "  ✅ PASS  $1"; PASS=$((PASS+1)); }
bad() { echo "  ❌ FAIL  $1"; FAIL=$((FAIL+1)); }
PY() { python3 -c "$1" 2>/dev/null; }

echo "=== 0014 Fix A: harga katalog dari DB ($BASE) ==="

# ---- A1. /api/products mengirim min_price ----
BODY=$(curl -s -m8 "$BASE/api/products")
HAS=$(echo "$BODY" | PY 'import json,sys; d=json.load(sys.stdin); p=d["products"][0]; print("yes" if "min_price" in p else "no")')
[ "$HAS" = "yes" ] && ok "A1. /api/products punya field min_price" || bad "A1. field min_price TIDAK ADA"

# ---- A2. min_price == harga varian termurah di DB ----
API_MIN=$(echo "$BODY" | PY 'import json,sys; d=json.load(sys.stdin); p=d["products"][0]; print(p.get("min_price"))')
echo "$BODY" | PY "
import json,sys
d=json.load(sys.stdin)
p=d['products'][0]
print('    produk:',p['name'],'| slug:',p['slug'],'| min_price:',p.get('min_price'))
"
# bandingkan dengan harga varian produk itu via /api/products/:slug
SLUG=$(echo "$BODY" | PY 'import json,sys; print(json.load(sys.stdin)["products"][0]["slug"])')
DBMIN=$(curl -s -m8 "$BASE/api/products/$SLUG" | PY 'import json,sys; v=json.load(sys.stdin)["product"]["variants"]; print(min(x["price"] for x in v) if v else "")')
[ -n "$API_MIN" ] && [ "$API_MIN" = "$DBMIN" ] && ok "A2. min_price == harga varian termurah DB ($API_MIN)" || bad "A2. min_price=$API_MIN vs DB=$DBMIN"

# ---- A3. bundle klien NOL rumus 825000 ----
HTML=$(curl -s -m8 "$BASE/katalog")
BUNDLES=$(echo "$HTML" | grep -oE 'store-[A-Za-z0-9_-]+\.js' | sort -u)
ALLJS=""
for b in $BUNDLES; do ALLJS="$ALLJS$(curl -s -m8 "$BASE/assets/$b")"; done
# 825000 bisa ditulis 825e3 / 825_000 oleh minifier
if echo "$ALLJS" | grep -qE '825000|825e3|825_000|8\.25e5'; then bad "A3. bundle masih ada rumus 825000"; else ok "A3. bundle klien nol rumus 825000"; fi

# ---- A4. bundle pakai min_price ----
echo "$ALLJS" | grep -q "min_price" && ok "A4. bundle memakai field min_price dari API" || bad "A4. bundle tidak memakai min_price"

echo
echo "=== HASIL: $PASS PASS / $FAIL FAIL ==="
[ "$FAIL" -eq 0 ]
