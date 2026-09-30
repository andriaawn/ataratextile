#!/usr/bin/env bash
# Test Fase 1 — halaman admin order + perbaikan kontras.
# Cara pakai: bash tests/admin-orders.test.sh <BASE_URL> <ADMIN_EMAIL> <ADMIN_PASSWORD>
# WAJIB dijalankan terhadap DB throwaway (bukan data/atandra.sqlite produksi).
set -u
BASE="${1:-http://127.0.0.1:8877}"
ADMIN_EMAIL="${2:-admin@test.local}"
ADMIN_PASSWORD="${3:-Test-Passw0rd-2026-Str0ng}"
PASS=0; FAIL=0
ok()  { echo "  ✅ PASS  $1"; PASS=$((PASS+1)); }
bad() { echo "  ❌ FAIL  $1"; FAIL=$((FAIL+1)); }
JAR=$(mktemp)

echo "=== Fase 1 admin-order test ($BASE) ==="

# ---- 1. Guest tidak boleh akses admin orders ----
CODE=$(curl -s -m 8 -o /dev/null -w '%{http_code}' "$BASE/api/admin/orders")
[ "$CODE" = "401" ] && ok "Guest GET /api/admin/orders ditolak (401)" || bad "Guest GET /api/admin/orders = $CODE (harus 401)"

CODE=$(curl -s -m 8 -o /dev/null -w '%{http_code}' -X PATCH "$BASE/api/admin/orders/1" -H 'Content-Type: application/json' -d '{"status":"paid"}')
[ "$CODE" = "401" ] && ok "Guest PATCH /api/admin/orders/1 ditolak (401)" || bad "Guest PATCH = $CODE (harus 401)"

# ---- 2. Login admin ----
LOGIN=$(curl -s -m 8 -c "$JAR" -o /dev/null -w '%{http_code}' -X POST "$BASE/api/auth/login" \
  -H 'Content-Type: application/json' -d "{\"email\":\"$ADMIN_EMAIL\",\"password\":\"$ADMIN_PASSWORD\"}")
[ "$LOGIN" = "200" ] && ok "Login admin berhasil (200)" || bad "Login admin = $LOGIN (harus 200)"

# ---- 3. Halaman admin order dilayani ----
CODE=$(curl -s -m 8 -o /dev/null -w '%{http_code}' "$BASE/admin-orders.html")
[ "$CODE" = "200" ] && ok "GET /admin-orders.html dilayani (200)" || bad "GET /admin-orders.html = $CODE (harus 200)"

# ---- 4. Bikin order test lewat API publik ----
VARIANT=$(curl -s -m 8 "$BASE/api/products" | python3 -c 'import json,sys; d=json.load(sys.stdin); p=(d.get("products") or []); print(p[0]["id"] if p else "")' 2>/dev/null)
ORDER=$(curl -s -m 8 -X POST "$BASE/api/orders" -H 'Content-Type: application/json' \
  -d "{\"customer\":{\"name\":\"Budi Test\",\"email\":\"budi@test.local\",\"phone\":\"08120000001\"},\"address\":{\"address\":\"Jl Test 1\",\"province\":\"Jabar\",\"city\":\"Bandung\",\"district\":\"Coblong\",\"postal_code\":\"40132\"},\"items\":[{\"variant_id\":$VARIANT,\"quantity\":2}]}" \
  | python3 -c 'import json,sys; print(json.load(sys.stdin).get("orderNumber",""))' 2>/dev/null)
[ -n "$ORDER" ] && ok "Order test dibuat ($ORDER)" || bad "Gagal buat order test (variant_id=$VARIANT)"

# ---- 5. Admin lihat daftar order ----
BODY=$(curl -s -m 8 -b "$JAR" "$BASE/api/admin/orders")
if echo "$BODY" | grep -q "$ORDER"; then ok "Admin melihat order di daftar"; else bad "Order tidak muncul di daftar admin"; fi

# ---- 6. Status invalid harus DITOLAK ----
CODE=$(curl -s -m 8 -b "$JAR" -o /dev/null -w '%{http_code}' -X PATCH "$BASE/api/admin/orders/1" \
  -H 'Content-Type: application/json' -d '{"status":"status-ngawur"}')
[ "$CODE" = "400" ] && ok "Status invalid ditolak (400)" || bad "Status invalid = $CODE (harus 400)"

# ---- 7. Ubah status valid + resi ----
CODE=$(curl -s -m 8 -b "$JAR" -o /dev/null -w '%{http_code}' -X PATCH "$BASE/api/admin/orders/1" \
  -H 'Content-Type: application/json' -d '{"status":"paid","tracking_number":"JNE-TEST-123"}')
[ "$CODE" = "200" ] && ok "Ubah status ke paid (200)" || bad "Ubah status = $CODE (harus 200)"

# ---- 8. Perubahan benar-benar tersimpan ----
BODY=$(curl -s -m 8 -b "$JAR" "$BASE/api/admin/orders")
if echo "$BODY" | grep -q '"status":"paid"' && echo "$BODY" | grep -q 'JNE-TEST-123'; then
  ok "Status & resi tersimpan di database"
else
  bad "Status/resi tidak tersimpan"
fi

# ---- 9. Guest tetap tidak lihat data pribadi order ----
BODY=$(curl -s -m 8 "$BASE/api/orders/1")
if echo "$BODY" | grep -q "budi@test.local"; then bad "Guest masih lihat email pelanggan"; else ok "Guest tidak lihat data pribadi"; fi

# ---- 10. Kontras --rust & --muted sudah diperbaiki di CSS ----
CSS=$(curl -s -m 8 "$BASE/assets/$(curl -s -m 8 "$BASE/admin-orders.html" | grep -oE 'store-[A-Za-z0-9_-]+\.css' | head -1)")
if echo "$CSS" | grep -q '#a8562f'; then ok "CSS memakai --rust baru (#a8562f)"; else bad "CSS masih --rust lama"; fi
if echo "$CSS" | grep -q '#5c6a6a'; then ok "CSS memakai --muted baru (#5c6a6a)"; else bad "CSS masih --muted lama"; fi

echo
echo "=== HASIL: $PASS PASS / $FAIL FAIL ==="
rm -f "$JAR"
[ "$FAIL" -eq 0 ]
