#!/usr/bin/env bash
# Test Fase 1 — buktikan 5 kerentanan sudah tertutup.
# Cara pakai: bash /tmp/atara_test.sh <BASE_URL> <ADMIN_EMAIL> <ADMIN_PASSWORD>
set -u
BASE="${1:-http://localhost:8877}"
ADMIN_EMAIL="${2:-admin@example.com}"
ADMIN_PASSWORD="${3:-Str0ng-Passw0rd-2026!}"
PASS=0; FAIL=0
ok()   { echo "  ✅ PASS  $1"; PASS=$((PASS+1)); }
bad()  { echo "  ❌ FAIL  $1"; FAIL=$((FAIL+1)); }
JAR=$(mktemp)

echo "=== Fase 1 security test ($BASE) ==="

# ---- 1. IDOR: guest tidak boleh lihat data pribadi order ----
# buat order dulu sebagai guest
ORDER=$(curl -s -m 8 -X POST "$BASE/api/orders" -H 'Content-Type: application/json' \
  -d '{"customer":{"name":"Rahasia Corp","email":"secret@example.com","phone":"08120000000"},"address":{"address":"Jl Rahasia 1","province":"Jabar","city":"Bandung","district":"Coblong","postal_code":"40132"},"items":[{"variant_id":1,"quantity":1}]}' \
  | python3 -c 'import json,sys; print(json.load(sys.stdin).get("orderNumber",""))' 2>/dev/null)
if [ -z "$ORDER" ]; then
  echo "  (skip IDOR: gagal buat order — cek variant_id)"
else
  BODY=$(curl -s -m 8 "$BASE/api/orders/$ORDER")
  if echo "$BODY" | grep -q "secret@example.com\|08120000000"; then
    bad "IDOR #1 — guest masih bisa lihat email/telepon order"
  else
    ok "IDOR #1 — guest tidak lihat data pribadi"
  fi
  # guest masih boleh lihat status
  if echo "$BODY" | grep -q "$ORDER"; then ok "IDOR #1b — guest tetap bisa cek status order"; else bad "IDOR #1b — guest tidak bisa cek status"; fi
fi

# ---- 2. admin-register dengan key default harus DITOLAK ----
CODE=$(curl -s -m 8 -o /dev/null -w '%{http_code}' -X POST "$BASE/api/auth/admin-register" \
  -H 'Content-Type: application/json' \
  -d '{"name":"Attacker","email":"attacker@evil.com","password":"hacked12345","invite_key":"change-this-invite-key"}')
if [ "$CODE" = "403" ] || [ "$CODE" = "503" ]; then ok "Admin takeover #2 — key default ditolak (HTTP $CODE)"; else bad "Admin takeover #2 — key default DITERIMA (HTTP $CODE)"; fi

# ---- 3. mock-payment tanpa/dengan key default harus GAGAL ----
if [ -n "${ORDER:-}" ]; then
  CODE=$(curl -s -m 8 -o /dev/null -w '%{http_code}' -X POST "$BASE/api/orders/$ORDER/mock-payment" -H 'x-dev-payment-key: local-only')
  if [ "$CODE" = "404" ]; then ok "Mock-payment #3 — key default 'local-only' ditolak (HTTP 404)"; else bad "Mock-payment #3 — DITERIMA (HTTP $CODE)"; fi
  CODE=$(curl -s -m 8 -o /dev/null -w '%{http_code}' -X POST "$BASE/api/orders/$ORDER/mock-payment")
  if [ "$CODE" = "404" ]; then ok "Mock-payment #3b — tanpa key ditolak (HTTP 404)"; else bad "Mock-payment #3b — DITERIMA (HTTP $CODE)"; fi
fi

# ---- 4. login admin dengan password dari DB lama harus GAGAL ----
CODE=$(curl -s -m 8 -o /dev/null -w '%{http_code}' -X POST "$BASE/api/auth/login" \
  -H 'Content-Type: application/json' -d '{"email":"admin@atandra.local","password":"password"}')
if [ "$CODE" = "401" ]; then ok "Login lama #4 — admin@atandra.local/password ditolak (HTTP 401)"; else bad "Login lama #4 — MASIH BISA login (HTTP $CODE)"; fi

# ---- 5. XSS: payload harus ter-escape (disimpan mentah, dirender aman oleh frontend) ----
if [ -n "${ORDER:-}" ]; then
  curl -s -m 8 -X POST "$BASE/api/orders" -H 'Content-Type: application/json' \
    -d '{"customer":{"name":"<img src=x onerror=alert(1)>","email":"xss@example.com","phone":"0812"},"address":{"address":"x","province":"x","city":"x"},"items":[{"variant_id":1,"quantity":1}]}' > /dev/null
fi
# cek frontend punya esc() dan dipakai
if grep -q "const esc =" store.js && grep -q 'esc(order.customer_name' store.js; then
  ok "XSS #5 — frontend punya esc() dan dipakai di render order"
else
  bad "XSS #5 — esc() tidak ada / tidak dipakai"
fi

# ---- 6. security headers ----
HDRS=$(curl -s -m 8 -D - -o /dev/null "$BASE/api/health")
for h in "X-Content-Type-Options" "Content-Security-Policy" "X-Frame-Options"; do
  if echo "$HDRS" | grep -qi "^$h:"; then ok "Header #6 — $h ada"; else bad "Header #6 — $h HILANG"; fi
done

echo
echo "=== HASIL: $PASS PASS / $FAIL FAIL ==="
rm -f "$JAR"
[ "$FAIL" -eq 0 ]
