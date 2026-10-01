#!/usr/bin/env bash
# Plan 0012 — CMS siap terima produk.
#
# Akar bug: POST /api/admin/products mewajibkan 11 field, tapi form CMS hanya punya
# 10 (recommended_usage tidak ada). Semua test lama memanggil API LANGSUNG dan selalu
# mengirim recommended_usage, jadi tak ada yang memeriksa FORM-nya — API hijau, form rusak.
#
# Test ini yang menutup celah itu:
#   A. STATIS  — setiap field wajib API harus ada di form HTML (penjaga utama)
#   B. FUNGSIONAL — kirim payload PERSIS yang bisa dihasilkan form → harus 201
#
# ⚠️ Bagian A sengaja baca SUMBER (admin-products.html + server/index.js), bukan bundle,
# supaya pesan gagalnya menunjuk file yang harus diperbaiki.
set -uo pipefail

BASE="${1:-http://127.0.0.1:8881}"
ROOT="${2:-/home/dev/projects/ataratextile}"
EMAIL="${3:-admin@test.local}"
PASS="${4:-Test-Passw0rd-2026-Str0ng}"
JAR="$(mktemp)"

pass=0; fail=0
ok()   { pass=$((pass+1)); printf '  \033[32mPASS\033[0m %s\n' "$1"; }
bad()  { fail=$((fail+1)); printf '  \033[31mFAIL\033[0m %s\n' "$1"; }
check(){ [ "$2" = "$3" ] && ok "$1 ($2)" || bad "$1 — dapat '$2', harus '$3'"; }

echo "═══ Plan 0012 — CMS siap terima produk ═══"

HTML="$ROOT/admin-products.html"
SRV="$ROOT/server/index.js"
[ -f "$HTML" ] || { bad "1. $HTML tidak ada"; exit 1; }
[ -f "$SRV" ]  || { bad "2. $SRV tidak ada"; exit 1; }

# ─────────────────────────────────────────────────────────────────────────
# A. STATIS — field wajib API vs field di form
# ─────────────────────────────────────────────────────────────────────────
REQ_JSON=$(python3 - "$SRV" <<'PY'
import re, sys, json
s = open(sys.argv[1], encoding='utf-8').read()
i = s.find("app.post('/api/admin/products'")
seg = s[i:i+1400]
m = re.search(r'const requiredFields = \{(.*?)\};', seg, re.S)
if not m:
    # kode lama: pakai rantai `if (!a || !b || ...)` — ekstrak nama variabelnya
    m2 = re.search(r'if \((!.*?)\) return res\.status\(400\)', seg, re.S)
    names = re.findall(r'!\s*([a-z_]+)', m2.group(1)) if m2 else []
    print(json.dumps(names)); raise SystemExit
print(json.dumps(re.findall(r'([a-z_]+):', m.group(1))))
PY
)

FORM_JSON=$(python3 - "$HTML" <<'PY'
import re, sys, json
s = open(sys.argv[1], encoding='utf-8').read()
i = s.find('id="product-form"')
j = s.find('</form>', i)
seg = s[i:j]
print(json.dumps(sorted(set(re.findall(r'name="([a-z_]+)"', seg)))))
PY
)

echo "  field wajib API : $REQ_JSON"
echo "  field di form   : $FORM_JSON"

MISSING=$(python3 - "$REQ_JSON" "$FORM_JSON" <<'PY'
import json, sys
req = json.loads(sys.argv[1]); form = json.loads(sys.argv[2])
print(' '.join(f for f in req if f not in form))
PY
)
if [ -z "$MISSING" ]; then
  ok "3. semua field wajib API ada di form"
else
  bad "3. field wajib API TIDAK ada di form: $MISSING"
fi

# Field baru yang harus bisa diisi admin (temuan 0011 #4)
for f in recommended_usage moq sample_available featured bestseller; do
  case "$FORM_JSON" in
    *"\"$f\""*) ok "4. form punya field '$f'";;
    *)          bad "4. form TIDAK punya field '$f'";;
  esac
done

# Label lama "Deskripsi / penggunaan" menyesatkan — admin mengira itu recommended_usage.
if grep -q 'Deskripsi / penggunaan' "$HTML"; then
  bad "5. label 'Deskripsi / penggunaan' masih ada (menyesatkan, tertukar dengan rekomendasi)"
else
  ok "5. label deskripsi tidak lagi menyesatkan"
fi

# ─────────────────────────────────────────────────────────────────────────
# B. FUNGSIONAL — kirim payload PERSIS dari form
# ─────────────────────────────────────────────────────────────────────────
code=$(curl -s -o /tmp/pf_login.json -w '%{http_code}' -c "$JAR" \
  -H 'Content-Type: application/json' \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASS\"}" "$BASE/api/auth/login")
if [ "$code" != "200" ]; then echo "  login gagal ($code) — server uji jalan?"; cat /tmp/pf_login.json; exit 1; fi
echo "  login OK"

RND=$RANDOM
PAYLOAD=$(python3 - "$FORM_JSON" "$RND" <<'PY'
import json, sys
names = json.loads(sys.argv[1]); rnd = sys.argv[2]
vals = {
  'name': f'Uji Form {rnd}', 'slug': f'uji-form-{rnd}', 'sku': f'UF-{rnd}',
  'category_id': '1', 'gsm': '150', 'width': '150 cm', 'weight_per_yard': '200 g/yard',
  'status': 'active', 'material': 'Cotton', 'construction': 'Pique',
  'description': 'uji', 'recommended_usage': 'Kaos polos',
  'moq': '1', 'sample_available': '1', 'featured': '0', 'bestseller': '0',
  'image': '/img/fabric-hero.png',
}
# hanya kirim field yang benar-benar ada di form — ini inti testnya
print(json.dumps({k: vals.get(k, 'uji') for k in names}))
PY
)
echo "  payload (dari form) : $PAYLOAD"

HTTP=$(curl -s -o /tmp/pf_create.json -w '%{http_code}' -b "$JAR" -c "$JAR" \
  -H 'Content-Type: application/json' -d "$PAYLOAD" "$BASE/api/admin/products")
check "6. POST persis payload form → 201" "$HTTP" "201"
if [ "$HTTP" != "201" ]; then echo "     respons: $(cat /tmp/pf_create.json)"; fi

PID=$(python3 -c 'import json;print(json.load(open("/tmp/pf_create.json")).get("product",{}).get("id",""))' 2>/dev/null)

# ── field baru benar-benar tersimpan ──
if [ -n "$PID" ]; then
  curl -s -b "$JAR" -c "$JAR" "$BASE/api/admin/products" -o /tmp/pf_list.json
  GOT=$(python3 - "$PID" <<'PY'
import json, sys
pid = int(sys.argv[1])
data = json.load(open('/tmp/pf_list.json'))
for p in data['products']:
    if p['id'] == pid:
        print(f"{p.get('recommended_usage')}|{p.get('moq')}|{p.get('sample_available')}|{p.get('featured')}|{p.get('bestseller')}")
        break
PY
)
  check "7. recommended_usage tersimpan" "$(printf '%s' "$GOT" | cut -d'|' -f1)" "Kaos polos"
  check "8. moq tersimpan"              "$(printf '%s' "$GOT" | cut -d'|' -f2)" "1"
  check "9. sample_available tersimpan" "$(printf '%s' "$GOT" | cut -d'|' -f3)" "True"
  check "10. featured tersimpan"        "$(printf '%s' "$GOT" | cut -d'|' -f4)" "False"
  check "11. bestseller tersimpan"      "$(printf '%s' "$GOT" | cut -d'|' -f5)" "False"
else
  bad "7-11. produk tidak terbuat, tidak bisa cek field"
fi

# ── string "0" itu TRUTHY di JS: `featured ? 1 : 0` dengan "0" akan salah jadi 1 ──
RND2=$((RND+1))
P2=$(python3 - "$FORM_JSON" "$RND2" <<'PY'
import json, sys
names = json.loads(sys.argv[1]); rnd = sys.argv[2]
vals = {'name': f'Uji Flag {rnd}', 'slug': f'uji-flag-{rnd}', 'sku': f'UFL-{rnd}',
  'category_id': '1', 'gsm': '150', 'width': '150 cm', 'weight_per_yard': '200 g/yard',
  'status': 'active', 'material': 'uji', 'construction': 'uji', 'description': 'uji',
  'recommended_usage': 'uji', 'moq': '0', 'sample_available': '0', 'featured': '1', 'bestseller': '1'}
print(json.dumps({k: vals.get(k, 'uji') for k in names}))
PY
)
curl -s -o /tmp/pf_flag.json -b "$JAR" -c "$JAR" -H 'Content-Type: application/json' \
  -d "$P2" "$BASE/api/admin/products" > /dev/null
P2ID=$(python3 -c 'import json;print(json.load(open("/tmp/pf_flag.json")).get("product",{}).get("id",""))' 2>/dev/null)
if [ -n "$P2ID" ]; then
  curl -s -b "$JAR" -c "$JAR" "$BASE/api/admin/products" -o /tmp/pf_list2.json
  GOT2=$(python3 - "$P2ID" <<'PY'
import json, sys
pid = int(sys.argv[1])
data = json.load(open('/tmp/pf_list2.json'))
for p in data['products']:
    if p['id'] == pid:
        print(f"{p.get('featured')}|{p.get('bestseller')}|{p.get('sample_available')}|{p.get('moq')}")
        break
PY
)
  check "12. featured='1' → True"        "$(printf '%s' "$GOT2" | cut -d'|' -f1)" "True"
  check "13. sample_available='0' → False" "$(printf '%s' "$GOT2" | cut -d'|' -f3)" "False"
  check "14. moq='0' dinormalkan ke 1"   "$(printf '%s' "$GOT2" | cut -d'|' -f4)" "1"
else
  bad "12-14. produk flag tidak terbuat"
fi

# ── pesan 400 menyebut field yang kurang ──
BODY=$(curl -s -b "$JAR" -c "$JAR" -H 'Content-Type: application/json' \
  -d '{"name":"Kurang Lengkap"}' "$BASE/api/admin/products")
case "$BODY" in
  *recommended_usage*|*Rekomendasi*) ok "15. pesan 400 menyebut field yang kurang";;
  *) bad "15. pesan 400 tidak menyebut field mana: $BODY";;
esac

# ─────────────────────────────────────────────────────────────────────────
# C. STATIS — `event.currentTarget` dipakai SETELAH `await` = null
# ─────────────────────────────────────────────────────────────────────────
# Akar: React/DOM melepas currentTarget begitu handler selesai. Dipakai setelah
# await → null → `Cannot read properties of null`. Dulu tersembunyi karena form
# produk SELALU gagal 400, jadi baris reset() tak pernah tercapai.
JS_FILES="admin-products.js admin-orders.js store.js account.js"
LEAK=0
for f in $JS_FILES; do
  [ -f "$ROOT/$f" ] || continue
  n=$(grep -c 'event\.currentTarget\.reset' "$ROOT/$f" 2>/dev/null)
  n=${n:-0}
  [ "$n" -gt 0 ] && { bad "16. $f pakai event.currentTarget.reset() ($n×) — jadi null setelah await"; LEAK=$((LEAK+1)); }
done
[ "$LEAK" -eq 0 ] && ok "16. tidak ada event.currentTarget.reset() setelah await"

# Handler yang reset form wajib menangkap form SEBELUM await.
CAP=0; RES=0
for f in $JS_FILES; do
  [ -f "$ROOT/$f" ] || continue
  c=$(grep -o 'const form = event\.currentTarget' "$ROOT/$f" 2>/dev/null | wc -l); c=${c:-0}
  r=$(grep -o 'form\.reset()' "$ROOT/$f" 2>/dev/null | wc -l); r=${r:-0}
  CAP=$((CAP+c)); RES=$((RES+r))
done
check "17. jumlah form tertangkap = jumlah reset" "$CAP" "$RES"

echo
echo "  ── hasil: PASS: $pass / FAIL: $fail ──"
[ "$fail" -eq 0 ] && exit 0 || exit 1
