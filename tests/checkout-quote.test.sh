#!/usr/bin/env bash
# Test plan 0013 — Fix B/C: /api/checkout/quote = SATU rumus uang.
# Inti: quote.total HARUS == order.total (angka dilihat == angka ditagih).
# WAJIB di DB throwaway.
set -u
BASE="${1:-http://127.0.0.1:8877}"
PASS=0; FAIL=0
ok()  { echo "  ✅ PASS  $1"; PASS=$((PASS+1)); }
bad() { echo "  ❌ FAIL  $1"; FAIL=$((FAIL+1)); }
PY() { python3 -c "$1" 2>/dev/null; }

echo "=== 0013 Fix B/C: /api/checkout/quote ($BASE) ==="

# ---- variant asli ----
SLUG=$(curl -s -m 8 "$BASE/api/products" | PY 'import json,sys; d=json.load(sys.stdin); p=(d.get("products") or []); print(p[0]["slug"] if p else "")')
VARIANT=$(curl -s -m 8 "$BASE/api/products/$SLUG" | PY 'import json,sys; d=json.load(sys.stdin); v=(d.get("product") or {}).get("variants") or []; print(v[0]["id"] if v else "")')
[ -n "$VARIANT" ] && ok "Variant asli (id=$VARIANT)" || { bad "Variant tidak ditemukan"; exit 1; }

quote() { curl -s -m 8 -X POST "$BASE/api/checkout/quote" -H 'Content-Type: application/json' -d "$1"; }

# ---- B1. 3 roll Jakarta: ongkir 18000 + 2*5000 = 28000 ----
R=$(quote "{\"items\":[{\"variant_id\":$VARIANT,\"quantity\":3}],\"city\":\"Jakarta\"}")
SHIP=$(echo "$R" | PY 'import json,sys; print(json.load(sys.stdin)["shipping"]["cost"])')
[ "$SHIP" = "28000" ] && ok "B1. 3 roll Jakarta → ongkir 28.000" || bad "B1. ongkir=$SHIP (harus 28000)"

# ---- B2. 1 roll Bandung: 35000 ----
R=$(quote "{\"items\":[{\"variant_id\":$VARIANT,\"quantity\":1}],\"city\":\"Bandung\"}")
SHIP=$(echo "$R" | PY 'import json,sys; print(json.load(sys.stdin)["shipping"]["cost"])')
[ "$SHIP" = "35000" ] && ok "B2. 1 roll Bandung → ongkir 35.000" || bad "B2. ongkir=$SHIP (harus 35000)"

# ---- B3. INTI: quote.total == order.total (3 roll Jakarta) ----
QTOTAL=$(quote "{\"items\":[{\"variant_id\":$VARIANT,\"quantity\":3}],\"city\":\"Jakarta\"}" | PY 'import json,sys; print(json.load(sys.stdin)["total"])')
OTOTAL=$(curl -s -m 8 -X POST "$BASE/api/orders" -H 'Content-Type: application/json' \
  -d "{\"customer\":{\"name\":\"Quote Test\",\"email\":\"quote@test.local\",\"phone\":\"0812\"},\"address\":{\"address\":\"Jl Q\",\"province\":\"DKI\",\"city\":\"Jakarta\",\"district\":\"\",\"postal_code\":\"\"},\"items\":[{\"variant_id\":$VARIANT,\"quantity\":3}]}" \
  | PY 'import json,sys; print(json.load(sys.stdin)["total"])')
[ -n "$QTOTAL" ] && [ "$QTOTAL" = "$OTOTAL" ] && ok "B3. INTI: quote.total == order.total ($QTOTAL) — selisih 0" || bad "B3. quote=$QTOTAL order=$OTOTAL (HARUS sama!)"

# ---- B4. subtotal pakai harga TIER (5 roll < harga satuan) ----
# harga tier 5-19 roll (mis. 940.000) vs retail 990.000
QT5=$(quote "{\"items\":[{\"variant_id\":$VARIANT,\"quantity\":5}],\"city\":\"Bandung\"}")
UNIT5=$(echo "$QT5" | PY 'import json,sys; print(json.load(sys.stdin)["items"][0]["unit_price"])')
RETAIL=$(curl -s -m 8 "$BASE/api/products/$SLUG" | PY 'import json,sys; d=json.load(sys.stdin); print((d["product"]["variants"] or [{}])[0].get("price",""))')
if [ -n "$UNIT5" ] && [ "$UNIT5" != "$RETAIL" ] && [ "$UNIT5" -lt "$RETAIL" ]; then
  ok "B4. 5 roll pakai harga tier ($UNIT5 < retail $RETAIL)"
else
  # kalau produk ini tak punya tier berbeda, cek minimal konsisten
  bad "B4. unit5=$UNIT5 retail=$RETAIL (tier tidak diterapkan?)"
fi

# ---- B5. quote TIDAK membuat order ----
BEFORE=$(curl -s -m 8 "$BASE/api/products" >/dev/null; curl -s -m 8 -X POST "$BASE/api/checkout/quote" -H 'Content-Type: application/json' -d "{\"items\":[{\"variant_id\":$VARIANT,\"quantity\":1}],\"city\":\"Bogor\"}" >/dev/null; echo done)
# cek jumlah order sebelum/sesudah via dashboard (butuh admin) — pakai produk endpoint tidak bisa.
# Di sini cukup pastikan quote 200 & tidak error.
CODE=$(curl -s -m 8 -o /dev/null -w '%{http_code}' -X POST "$BASE/api/checkout/quote" -H 'Content-Type: application/json' -d "{\"items\":[{\"variant_id\":$VARIANT,\"quantity\":1}],\"city\":\"Bogor\"}")
[ "$CODE" = "200" ] && ok "B5. quote tidak butuh login (200)" || bad "B5. quote = $CODE (harus 200)"

# ---- B6. qty > stok → 400 ----
CODE=$(curl -s -m 8 -o /dev/null -w '%{http_code}' -X POST "$BASE/api/checkout/quote" -H 'Content-Type: application/json' -d "{\"items\":[{\"variant_id\":$VARIANT,\"quantity\":999999}],\"city\":\"Bogor\"}")
[ "$CODE" = "400" ] && ok "B6. qty > stok ditolak (400)" || bad "B6. qty>stok = $CODE (harus 400)"

# ---- B7. variant tidak ada → 400 ----
CODE=$(curl -s -m 8 -o /dev/null -w '%{http_code}' -X POST "$BASE/api/checkout/quote" -H 'Content-Type: application/json' -d '{"items":[{"variant_id":99999999,"quantity":1}],"city":"Bogor"}')
[ "$CODE" = "400" ] && ok "B7. variant tak ada ditolak (400)" || bad "B7. variant tak ada = $CODE (harus 400)"

# ---- B8. items kosong → 400 ----
CODE=$(curl -s -m 8 -o /dev/null -w '%{http_code}' -X POST "$BASE/api/checkout/quote" -H 'Content-Type: application/json' -d '{"items":[],"city":"Bogor"}')
[ "$CODE" = "400" ] && ok "B8. items kosong ditolak (400)" || bad "B8. items kosong = $CODE (harus 400)"

echo
echo "=== HASIL: $PASS PASS / $FAIL FAIL ==="
[ "$FAIL" -eq 0 ]
