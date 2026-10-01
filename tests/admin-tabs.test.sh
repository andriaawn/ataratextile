#!/usr/bin/env bash
# Fase 2E — halaman Produk dirapikan jadi tab (plan 0006).
# Cara pakai: bash tests/admin-tabs.test.sh <BASE_URL>
# WAJIB dijalankan terhadap DB throwaway (bukan data/andra.sqlite produksi).
#
# Yang diuji: 3 tab ada, hanya satu panel tampil, CSS benar-benar menyembunyikan
# panel (menang atas [hidden] bawaan), dan SEMUA kontrol lama masih ada di dalam
# panel yang benar — tab tidak boleh menghilangkan fungsi apa pun.
set -uo pipefail

BASE="${1:-http://127.0.0.1:8881}"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  \033[32mPASS\033[0m %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  \033[31mFAIL\033[0m %s\n' "$1"; }

echo "═══ Fase 2E — halaman Produk jadi tab ═══"

HTML=$(curl -s -m 8 "$BASE/admin/produk")
[ -n "$HTML" ] || { echo "  halaman tidak terjangkau"; exit 1; }

OUT=$(python3 - "$HTML" <<'PY'
import re, sys
html = sys.argv[1]
pass_n = 0; fail_n = 0
def ok(m):
    global pass_n; pass_n += 1; print(f"  \033[32mPASS\033[0m {m}")
def bad(m):
    global fail_n; fail_n += 1; print(f"  \033[31mFAIL\033[0m {m}")
def check(cond, m):
    ok(m) if cond else bad(m)

# ---- 1. Tiga tab, tiga panel ----
tabs = re.findall(r'<button class="admin-tab[^"]*"[^>]*data-tab="([^"]+)"', html)
check(tabs == ['produk', 'varian', 'katalog'], f"1a. 3 tab dengan urutan benar: {tabs}")
panels = re.findall(r'<section id="panel-([a-z]+)"[^>]*data-panel="([a-z]+)"', html)
check([p[0] for p in panels] == ['produk', 'varian', 'katalog'], f"1b. 3 panel sesuai tab: {[p[0] for p in panels]}")
check(all(a == b for a, b in panels), "1c. id panel cocok dengan data-panel")

# ---- 2. Hanya tab pertama aktif; panel 2 & 3 `hidden` DI HTML statis ----
check('id="tab-produk"' in html and 'aria-selected="true"' in html, "2a. tab pertama aria-selected=true")
check(len(re.findall(r'aria-selected="false"', html)) == 2, "2b. dua tab lain aria-selected=false")
check('class="admin-tab is-active"' in html, "2c. tab pertama punya class is-active")
tag1 = re.search(r'id="panel-produk"[^>]*>', html)
check(tag1 is not None and 'hidden' not in tag1.group(0), "2d. panel Produk TIDAK hidden")
for name in ('varian', 'katalog'):
    tag = re.search(rf'id="panel-{name}"[^>]*>', html)
    check(tag is not None and 'hidden' in tag.group(0), f"2e. panel {name} punya 'hidden' di HTML statis (tidak berkedip)")

# ---- 3. Aksesibilitas tab ----
check('role="tablist"' in html, "3a. ada role=tablist")
check(len(re.findall(r'role="tab"', html)) == 3, "3b. tiga role=tab")
check(len(re.findall(r'role="tabpanel"', html)) == 3, "3c. tiga role=tabpanel")
check(len(re.findall(r'aria-controls="panel-', html)) == 3, "3d. tiap tab punya aria-controls")
check(len(re.findall(r'aria-labelledby="tab-', html)) == 3, "3e. tiap panel punya aria-labelledby")

# ---- 4. Pesan tetap terlihat dari tab mana pun (di luar panel) ----
msg_pos = html.find('id="products-message"')
tab_pos = html.find('class="admin-tabs"')
first_panel = html.find('id="panel-produk"')
check(0 < msg_pos < tab_pos < first_panel, "4. #products-message di luar panel (selalu terlihat)")

# ---- 5. SEMUA kontrol lama masih ada (tab tidak menghilangkan fungsi) ----
controls = ['id="product-form"', 'id="product-rows"', 'id="category-select"',
            'id="image-input"', 'id="image-url"', 'id="image-preview"', 'id="image-status"',
            'id="variant-panel"', 'id="variant-form"', 'id="variant-rows"', 'id="variant-title"',
            'id="variant-empty"', 'id="color-select"', 'id="pricing-form"',
            'id="bulk-all"', 'id="bulk-field"', 'id="bulk-mode"',
            'id="bulk-value"', 'id="bulk-preview"', 'id="bulk-preview-box"', 'id="bulk-apply"', 'id="bulk-cancel"',
            'id="gallery-grid"', 'id="gallery-drop"', 'id="gallery-pick"', 'id="gallery-input"',
            'id="category-form"', 'id="color-form"', 'id="category-list"', 'id="color-list"',
            'id="products-refresh"', 'id="products-auth"', 'id="products-loading"', 'id="products-workspace"']
missing = [c for c in controls if c not in html]
check(not missing, f"5a. semua {len(controls)} kontrol lama masih ada" if not missing else f"5a. HILANG: {missing}")
check('class="bulk-panel"' in html, "5b. panel bulk harga masih ada (class)")

# ---- 6. Kontrol ada di PANEL YANG BENAR ----
def inside(container_id, needle):
    i = html.find(f'id="{container_id}"')
    # Kita SUDAH berada di dalam <section> yang membuka container ini, jadi
    # hitungan kedalaman mulai dari 1 — kalau dari 0, penutup pertama bikin -1.
    depth = 1; k = i
    while k < len(html):
        nxt_open = html.find('<section', k)
        nxt_close = html.find('</section>', k)
        if nxt_close == -1: return False
        if nxt_open != -1 and nxt_open < nxt_close:
            depth += 1; k = nxt_open + 8
        else:
            depth -= 1
            if depth == 0: return needle in html[i:nxt_close]
            k = nxt_close + 10
    return False

for panel, needle, label in [
    ('panel-produk', 'id="product-form"', 'form produk'),
    ('panel-produk', 'id="product-rows"', 'daftar produk'),
    ('panel-varian', 'id="variant-panel"', 'panel varian'),
    ('panel-varian', 'class="bulk-panel"', 'panel bulk harga'),
    ('panel-varian', 'id="gallery-grid"', 'galeri gambar'),
    ('panel-katalog', 'id="category-list"', 'daftar kategori'),
    ('panel-katalog', 'id="color-list"', 'daftar warna'),
]:
    check(inside(panel, needle), f"6. {label} ada di dalam {panel}")

# ---- 7. Bahasa Indonesia, nol label Inggris ----
english = ['Product operations', 'Catalog structure', 'Create product', '>Archive<', '>Variant<']
found = [w for w in english if w in html]
check(not found, "7a. nol label Inggris" if not found else f"7a. label Inggris: {found}")
check('<th>Produk</th>' in html and '<th>Aksi</th>' in html, "7b. header tabel Indonesia")

# ---- 8. Tidak ada halaman baru (URL tetap) ----
check(html.count('<title>') == 1, "8. satu <title> (bukan halaman terpisah)")

print(f"__COUNT__ {pass_n} {fail_n}")
PY
)
printf '%s\n' "$OUT" | grep -v '^__COUNT__'
read -r _ P F <<<"$(printf '%s\n' "$OUT" | grep '^__COUNT__')"

# ---- 9. Sisi JS: bundle benar-benar punya logika tab ----
# Minifier mengganti nama fungsi, jadi periksa MARKUP/atribut, bukan nama fungsi.
BUNDLE_PATH=$(printf '%s' "$HTML" | grep -oE '/assets/adminProducts-[A-Za-z0-9_-]+\.js' | head -1)
if [ -z "$BUNDLE_PATH" ]; then
  bad "9. bundle adminProducts tidak ditemukan"
else
  BUNDLE=$(curl -s -m 8 "$BASE$BUNDLE_PATH")
  for marker in 'dataset.tab' 'admin-panel' 'is-active' 'aria-selected'; do
    case "$BUNDLE" in *"$marker"*) ok "9. bundle punya '$marker'";; *) bad "9. bundle tidak punya '$marker'";; esac
  done
  # Klik "Varian" harus memindah ke tab varian, bukan cuma membuka panel.
  case "$BUNDLE" in *'varian'*) ok "9. bundle memindah ke tab 'varian' saat klik Varian";; *) bad "9. bundle tidak memindah tab saat klik Varian";; esac
fi

# ---- 10. CSS benar-benar menyembunyikan panel (menang atas [hidden]) ----
CSS_PATH=$(printf '%s' "$HTML" | grep -oE '/assets/store-[A-Za-z0-9_-]+\.css' | head -1)
if [ -z "$CSS_PATH" ]; then
  bad "10. CSS tidak ditemukan"
else
  CSSB=$(curl -s -m 8 "$BASE$CSS_PATH")
  case "$CSSB" in
    *'.admin-panel[hidden]{display:none}'*) ok "10a. .admin-panel[hidden]{display:none} ada (tidak bentrok dengan display:grid)";;
    *) bad "10a. aturan .admin-panel[hidden] tidak ada — panel bisa tetap tampil";;
    esac
    # Penjaga plan 0009: workspace (class admin-stack) juga display:grid, jadi atribut
    # `hidden`-nya kalah spesifisitas. Harus ada penutup global.
    case "$CSSB" in *'[hidden]{display:none!important}'*) ok "10a2. penutup global [hidden]{display:none!important} ada (workspace ikut tersembunyi)";; *) bad "10a2. penutup global [hidden] tidak ada — workspace bisa tampil sebelum login";; esac
  case "$CSSB" in *'.admin-tabs{'*) ok "10b. CSS .admin-tabs ada";; *) bad "10b. CSS .admin-tabs tidak ada";; esac
  case "$CSSB" in *'.admin-tab.is-active'*) ok "10c. CSS tab aktif ada";; *) bad "10c. CSS tab aktif tidak ada";; esac
  # Penjaga regresi: input punya lebar intrinsik, jadi grid `1fr 1fr` membuat
  # halaman melebar di 360px. `minmax(0,1fr)` yang mencegahnya.
  case "$CSSB" in *'minmax(0,1fr)'*) ok "10d. CSS pakai minmax(0,1fr) (anti scroll horizontal 360px)";; *) bad "10d. CSS tidak pakai minmax(0,1fr) — halaman bisa melebar di 360px";; esac
  case "$CSSB" in *'.variant-row{grid-template-columns:minmax'*) ok "10e. baris varian pakai minmax (tidak melebar)";; *) bad "10e. .variant-row tidak pakai minmax";; esac
  case "$CSSB" in *'max-width:900px'*) ok "10f. ada breakpoint 900px";; *) bad "10f. tidak ada breakpoint untuk layar sempit";; esac
fi

echo
echo "═══ 2E: $((P + pass)) PASS / $((F + fail)) FAIL ═══"
[ "$((F + fail))" -eq 0 ]