#!/usr/bin/env bash
# Test plan 0013 — Fix A: payments.status sinkron dengan orders.status.
# Cara pakai: bash tests/order-sync.test.sh <BASE_URL> <ADMIN_EMAIL> <ADMIN_PASSWORD>
# WAJIB di DB throwaway (bukan data/atandra.sqlite produksi).
set -u
BASE="${1:-http://127.0.0.1:8877}"
ADMIN_EMAIL="${2:-admin@test.local}"
ADMIN_PASSWORD="${3:-Test-Passw0rd-2026-Str0ng}"
PASS=0; FAIL=0
ok()  { echo "  ✅ PASS  $1"; PASS=$((PASS+1)); }
bad() { echo "  ❌ FAIL  $1"; FAIL=$((FAIL+1)); }
JAR=$(mktemp)
PY() { python3 -c "$1" 2>/dev/null; }

echo "=== 0013 Fix A: sinkron payments.status ($BASE) ==="

# ---- login admin ----
LOGIN=$(curl -s -m 8 -c "$JAR" -o /dev/null -w '%{http_code}' -X POST "$BASE/api/auth/login" \
  -H 'Content-Type: application/json' -d "{\"email\":\"$ADMIN_EMAIL\",\"password\":\"$ADMIN_PASSWORD\"}")
[ "$LOGIN" = "200" ] && ok "Login admin (200)" || { bad "Login admin = $LOGIN"; echo "STOP"; exit 1; }

# ---- ambil variant_id asli dari produk pertama ----
SLUG=$(curl -s -m 8 "$BASE/api/products" | PY 'import json,sys; d=json.load(sys.stdin); p=(d.get("products") or []); print(p[0]["slug"] if p else "")')
VARIANT=$(curl -s -m 8 "$BASE/api/products/$SLUG" | PY 'import json,sys; d=json.load(sys.stdin); v=(d.get("product") or {}).get("variants") or []; print(v[0]["id"] if v else "")')
[ -n "$VARIANT" ] && ok "Variant asli ditemukan (id=$VARIANT, slug=$SLUG)" || { bad "Variant tidak ditemukan"; exit 1; }

# ---- bikin order test ----
ORDER_ID=$(curl -s -m 8 -X POST "$BASE/api/orders" -H 'Content-Type: application/json' \
  -d "{\"customer\":{\"name\":\"Sync Test\",\"email\":\"sync@test.local\",\"phone\":\"0812\"},\"address\":{\"address\":\"Jl Test\",\"province\":\"DKI\",\"city\":\"Jakarta\",\"district\":\"\",\"postal_code\":\"\"},\"items\":[{\"variant_id\":$VARIANT,\"quantity\":1}]}" \
  | PY 'import json,sys; print(json.load(sys.stdin).get("orderId",""))')
[ -n "$ORDER_ID" ] && ok "Order test dibuat (id=$ORDER_ID)" || { bad "Gagal buat order"; exit 1; }

pay_status() { curl -s -m 8 -b "$JAR" "$BASE/api/admin/orders" | PY "import json,sys; d=json.load(sys.stdin); o=[x for x in d['orders'] if x['id']==$ORDER_ID]; print(o[0].get('payment_status','') if o else '')"; }

# ---- A0. order baru → pending ----
P=$(pay_status)
[ "$P" = "pending" ] && ok "A0. order baru → payments='pending'" || bad "A0. payments='$P' (harus pending)"

# ---- A1. PATCH → paid ⇒ payments='paid' ----
curl -s -m 8 -b "$JAR" -o /dev/null -X PATCH "$BASE/api/admin/orders/$ORDER_ID" -H 'Content-Type: application/json' -d '{"status":"paid"}'
P=$(pay_status)
[ "$P" = "paid" ] && ok "A1. PATCH→paid ⇒ payments='paid'" || bad "A1. payments='$P' (harus paid) — BUG tidak sinkron"

# ---- A2. PATCH → refunded ⇒ payments='refunded' ----
curl -s -m 8 -b "$JAR" -o /dev/null -X PATCH "$BASE/api/admin/orders/$ORDER_ID" -H 'Content-Type: application/json' -d '{"status":"refunded"}'
P=$(pay_status)
[ "$P" = "refunded" ] && ok "A2. PATCH→refunded ⇒ payments='refunded'" || bad "A2. payments='$P' (harus refunded)"

# ---- A3. PATCH → cancelled ⇒ payments='refunded' ----
curl -s -m 8 -b "$JAR" -o /dev/null -X PATCH "$BASE/api/admin/orders/$ORDER_ID" -H 'Content-Type: application/json' -d '{"status":"cancelled"}'
P=$(pay_status)
[ "$P" = "refunded" ] && ok "A3. PATCH→cancelled ⇒ payments='refunded'" || bad "A3. payments='$P' (harus refunded)"

# ---- A4. order refunded TIDAK terhitung pending (KPI jujur) ----
STILL=$(curl -s -m 8 -b "$JAR" "$BASE/api/admin/orders" | PY "import json,sys; d=json.load(sys.stdin); print(len([x for x in d['orders'] if x['id']==$ORDER_ID and x.get('payment_status')=='pending']))")
[ "$STILL" = "0" ] && ok "A4. order refunded tidak lagi 'pending' (KPI jujur)" || bad "A4. order refunded masih pending"

# ---- A5. status invalid tetap 400 ----
CODE=$(curl -s -m 8 -b "$JAR" -o /dev/null -w '%{http_code}' -X PATCH "$BASE/api/admin/orders/$ORDER_ID" -H 'Content-Type: application/json' -d '{"status":"ngawur"}')
[ "$CODE" = "400" ] && ok "A5. status invalid tetap 400" || bad "A5. status invalid = $CODE (harus 400)"

# ---- A6. guest tetap 401 ----
CODE=$(curl -s -m 8 -o /dev/null -w '%{http_code}' -X PATCH "$BASE/api/admin/orders/$ORDER_ID" -H 'Content-Type: application/json' -d '{"status":"paid"}')
[ "$CODE" = "401" ] && ok "A6. guest PATCH tetap 401" || bad "A6. guest PATCH = $CODE (harus 401)"

echo
echo "=== HASIL: $PASS PASS / $FAIL FAIL ==="
rm -f "$JAR"
[ "$FAIL" -eq 0 ]
