#!/usr/bin/env bash
# Test plan 0013 — Fix B/C sisi UI: nol angka uang hardcode di klien.
# Cek statis HTML/JS yang dilayani server.
set -u
BASE="${1:-http://127.0.0.1:8877}"
PASS=0; FAIL=0
ok()  { echo "  ✅ PASS  $1"; PASS=$((PASS+1)); }
bad() { echo "  ❌ FAIL  $1"; FAIL=$((FAIL+1)); }

echo "=== 0013 Fix B/C: checkout UI ($BASE) ==="

# ---- C1. checkout.html tidak lagi hardcode Rp 35.000 ----
HTML=$(curl -s -m 8 "$BASE/keranjang")
if echo "$HTML" | grep -q "Rp 35.000"; then bad "C1. checkout.html masih hardcode 'Rp 35.000'"; else ok "C1. checkout.html nol 'Rp 35.000' mati"; fi

# ---- C2. checkout.html punya elemen #shipping & #total ----
echo "$HTML" | grep -q 'id="shipping"' && ok "C2a. ada #shipping" || bad "C2a. tidak ada #shipping"
echo "$HTML" | grep -q 'id="total"' && ok "C2b. ada #total" || bad "C2b. tidak ada #total"

# ---- C3/C4. semua bundle store-*.js tidak hardcode 35000 & memanggil /checkout/quote ----
BUNDLES=$(echo "$HTML" | grep -oE 'store-[A-Za-z0-9_-]+\.js' | sort -u)
if [ -z "$BUNDLES" ]; then
  bad "C3. bundle store-*.js tidak ditemukan"
else
  ALLJS=""
  for b in $BUNDLES; do ALLJS="$ALLJS$(curl -s -m 8 "$BASE/assets/$b")"; done
  # minifier bisa menulis 35000 sebagai 35e3 / 3.5e4 / 35_000 — cek semua bentuk.
  if echo "$ALLJS" | grep -qE '35000|35e3|3\.5e4|35_000'; then bad "C3. bundle JS masih ada ongkir hardcode (35000/35e3)"; else ok "C3. bundle JS nol ongkir hardcode"; fi
  echo "$ALLJS" | grep -q "checkout/quote" && ok "C4. JS memanggil /checkout/quote" || bad "C4. JS tidak memanggil /checkout/quote"
fi

echo
echo "=== HASIL: $PASS PASS / $FAIL FAIL ==="
[ "$FAIL" -eq 0 ]
