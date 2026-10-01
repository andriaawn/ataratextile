#!/usr/bin/env bash
# Test plan 0009 — pastikan SEMUA elemen ber-atribut `hidden` benar-benar tersembunyi.
#
# Kenapa perlu: atribut `hidden` bawaan browser (display:none) KALAH spesifisitas dari
# aturan kelas (mis. `.admin-stack{display:grid}`). Akibatnya dashboard admin tampil
# sebelum login. Test ini menjaga agar aturan penutup global tidak pernah hilang.
#
# Cara pakai: bash tests/hidden-guard.test.sh [DIR]   (default: direktori repo ini)
set -u
DIR="${1:-.}"
cd "$DIR" || { echo "❌ direktori tidak ada: $DIR"; exit 1; }
PASS=0; FAIL=0
ok()  { echo "  ✅ PASS  $1"; PASS=$((PASS+1)); }
bad() { echo "  ❌ FAIL  $1"; FAIL=$((FAIL+1)); }

# CSS: pakai bundle hasil build kalau ada (itu yang dilayani produksi), kalau tidak
# pakai sumber store.css.
CSS_SRC="store.css"
if [ -f dist/admin.html ]; then
  CSSFILE=$(ls dist/assets/store-*.css 2>/dev/null | head -1)
  [ -n "${CSSFILE:-}" ] && CSS_SRC="$CSSFILE"
fi

echo "=== Penjaga panel hidden (plan 0009) ==="
echo "  CSS yang diperiksa: $CSS_SRC"

if [ ! -f "$CSS_SRC" ]; then
  bad "0. CSS tidak ditemukan ($CSS_SRC)"
  echo; echo "  PASS: $PASS  FAIL: $FAIL"; exit 1
fi

CSS=$(cat "$CSS_SRC")

# ---- 1. aturan penutup GLOBAL ada ----
# ⚠️ Tidak boleh cuma grep substring: `.admin-panel[hidden]{display:none}` juga cocok
#    dengan pola itu, padahal ia TIDAK menutup `.admin-stack[hidden]`. Yang dicari:
#    selector yang BERDIRI SENDIRI sebagai `[hidden]` (didahului `{`, `}`, atau `,`).
if python3 -c "
import re, sys
s = open('$CSS_SRC', encoding='utf-8', newline='').read()
sys.exit(0 if re.search(r'(^|[},])\s*\[hidden\]\s*\{[^}]*display\s*:\s*none', s) else 1)"; then
  ok "1a. aturan GLOBAL [hidden]{display:none} ada (selector berdiri sendiri)"
else
  bad "1a. aturan GLOBAL [hidden]{display:none} HILANG — panel bisa tampil sebelum login"
fi

# ---- 2. urutannya setelah .admin-stack{display:grid} (yang menang = deklarasi terakhir) ----
POS_STACK=$(python3 -c "
import sys
s=open('$CSS_SRC',encoding='utf-8',newline='').read()
i=s.find('.admin-stack{display:grid')
print(i if i>=0 else -1)")
POS_HIDDEN=$(python3 -c "
import re
s=open('$CSS_SRC',encoding='utf-8',newline='').read()
m=re.search(r'(^|[},])\s*\[hidden\]\s*\{[^}]*display\s*:\s*none', s)
print(m.start() if m else -1)")
if [ "$POS_HIDDEN" -ge 0 ] && [ "$POS_STACK" -ge 0 ] && [ "$POS_HIDDEN" -gt "$POS_STACK" ]; then
  ok "2a. aturan [hidden] muncul SETELAH .admin-stack{display:grid} (urutan menang)"
else
  bad "2a. urutan salah (stack=$POS_STACK, hidden=$POS_HIDDEN) — aturan kelas bisa menang"
fi

# ---- 3. SEMUA elemen hidden di semua halaman punya penutup ----
# Cek statis: kumpulkan kelas tiap elemen ber-atribut hidden, lalu pastikan ada
# aturan `[hidden]` global yang menutupinya (dan bukan cuma .admin-panel).
LEAKS=$(python3 - <<'PY'
import re, glob, os
# Aturan penutup yang berlaku: selector mengandung [hidden] dengan display:none
def covered(css):
    # Aturan penutup harus GLOBAL: selector `[hidden]` berdiri sendiri (didahului
    # awal baris, `}`, atau `,`). `.admin-panel[hidden]{...}` TIDAK dihitung — ia
    # tidak menutup `.admin-stack[hidden]`, dan itulah bug yang dijaga test ini.
    return re.search(r'(^|[},])[ \t\r\n]*\[hidden\][ \t\r\n]*\{[^}]*display[ \t\r\n]*:[ \t\r\n]*none', css, re.M) is not None

css_sources = []
if os.path.isfile('store.css'):
    css_sources.append(open('store.css', encoding='utf-8', newline='').read())
for f in glob.glob('index.html'):
    s = open(f, encoding='utf-8', newline='').read()
    for m in re.findall(r'<style[^>]*>(.*?)</style>', s, re.S):
        css_sources.append(m)
allcss = '\n'.join(css_sources)

global_guard = covered(allcss)

def class_has_display(css, cls):
    for m in re.finditer(r'\.' + re.escape(cls) + r'(?![\w-])[^{}]*\{([^}]*)\}', css):
        if re.search(r'display\s*:\s*(?!none)', m.group(1)):
            return True
    return False

leaks = []
for h in sorted(glob.glob('*.html')):
    s = open(h, encoding='utf-8', newline='').read()
    for m in re.finditer(r'<(\w+)([^>]*?)\shidden(\s[^>]*)?>', s):
        attrs = m.group(2) + (m.group(3) or '')
        cm = re.search(r'class="([^"]*)"', attrs)
        if not cm:
            continue
        idm = re.search(r'id="([^"]*)"', attrs)
        eid = idm.group(1) if idm else '-'
        for c in cm.group(1).split():
            if class_has_display(allcss, c) and not global_guard:
                leaks.append(f'{h} #{eid} .{c}')
print('\n'.join(leaks))
PY
)
if [ -z "$LEAKS" ]; then
  ok "3a. tidak ada elemen hidden yang kelasnya ber-display tanpa penutup"
else
  bad "3a. elemen hidden BOCOR (kelas ber-display tanpa penutup global):"
  echo "$LEAKS" | sed 's/^/        /'
fi

# ---- 4. aturan lama .admin-panel[hidden] masih ada (nol regresi 2E) ----
if echo "$CSS" | grep -q '\.admin-panel\[hidden\]'; then
  ok "4a. aturan .admin-panel[hidden]{display:none} masih ada (nol regresi 2E)"
else
  bad "4a. aturan .admin-panel[hidden] HILANG — regresi 2E"
fi

# ---- 5. store.css tetap CRLF (kalau yang diperiksa sumbernya) ----
if [ "$CSS_SRC" = "store.css" ]; then
  if python3 -c "
s=open('store.css','rb').read()
import sys; sys.exit(0 if s.count(b'\r\n')>0 and s.count(b'\n')==s.count(b'\r\n') else 1)"; then
    ok "5a. store.css tetap CRLF"
  else
    bad "5a. store.css line ending berubah (harus CRLF)"
  fi
fi

# ---- 6. penjaga ini berlaku untuk SEMUA halaman admin ----
MISSING=""
for f in admin.html admin-products.html admin-orders.html; do
  [ -f "$f" ] || continue
  grep -q 'hidden' "$f" || MISSING="$MISSING $f"
done
if [ -z "$MISSING" ]; then
  ok "6a. halaman admin memakai atribut hidden (dilindungi penjaga)"
else
  bad "6a. halaman tanpa atribut hidden (tak terduga):$MISSING"
fi

echo
echo "────────────────────────────────────────"
echo "  PASS: $PASS   FAIL: $FAIL"
echo "────────────────────────────────────────"
[ "$FAIL" -eq 0 ]
