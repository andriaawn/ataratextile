#!/usr/bin/env bash
# Runner test plan 0015 — DB THROWAWAY (direset fresh tiap run). Tidak menyentuh produksi.
# Pakai: bash tests/run-0015.sh
set -eu
SRC="$(cd "$(dirname "$0")/.." && pwd)"
T="/tmp/atara_test15"
PORT=8895
BASE="http://127.0.0.1:$PORT"
ADMIN_EMAIL="admin@test.local"
ADMIN_PASS="Test-Passw0rd-2026-Str0ng"

cleanup() { [ -f "$T/pid" ] && kill "$(cat "$T/pid")" 2>/dev/null || true; }
trap cleanup EXIT

# --- siapkan throwaway ---
mkdir -p "$T/tests" "$T/data"
[ -d "$T/server" ] || cp -r "$SRC/server" "$T/server"
ln -sfn "$SRC/node_modules" "$T/node_modules"
ln -sfn "$SRC/public" "$T/public"
cat > "$T/.env" <<EOF
PORT=$PORT
NODE_ENV=development
ADMIN_EMAIL=$ADMIN_EMAIL
ADMIN_PASSWORD=$ADMIN_PASS
ADMIN_INVITE_KEY=throwaway-invite-key-1234567890
DEV_PAYMENT_KEY=local-only
ALLOWED_ORIGINS=http://127.0.0.1:$PORT,http://localhost:$PORT
EOF
cp "$SRC/tests/"*.test.sh "$T/tests/"
rm -rf "$T/dist"; cp -r "$SRC/dist" "$T/dist"
cp "$SRC/server/index.js" "$T/server/index.js"
cp "$SRC/store.js" "$T/store.js" 2>/dev/null || true
cp "$SRC/admin-samples.js" "$T/admin-samples.js" 2>/dev/null || true

# --- reset DB fresh (salinan produksi, read-only) + stok besar ---
kill "$(cat "$T/pid" 2>/dev/null)" 2>/dev/null || true
sleep 1
cp "$SRC/data/atandra.sqlite" "$T/data/atandra.sqlite"
( cd "$T" && node -e '
const initSqlJs=require("sql.js"),fs=require("fs");
(async()=>{const S=await initSqlJs();const db=new S.Database(fs.readFileSync("data/atandra.sqlite"));
db.run("UPDATE inventory SET stock=500, reserved_stock=0");
db.run("DELETE FROM sample_requests");
fs.writeFileSync("data/atandra.sqlite",Buffer.from(db.export()));})();' )

# --- start server (dibersihkan oleh trap) ---
( cd "$T" && node server/index.js > "$T/server.log" 2>&1 & echo $! > "$T/pid" )
for i in $(seq 1 15); do curl -s -m1 -o /dev/null "$BASE/api/health" 2>/dev/null && break; sleep 0.5; done
curl -s -m3 "$BASE/api/health" >/dev/null || { echo "server throwaway gagal start — lihat $T/server.log"; exit 1; }

# --- jalankan test ---
RC=0
echo "=== PLAN 0015 — test (DB throwaway @ $BASE) ==="
bash "$T/tests/samples.test.sh" "$BASE" "$ADMIN_EMAIL" "$ADMIN_PASS" || RC=1
exit $RC
