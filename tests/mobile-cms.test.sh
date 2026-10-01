#!/usr/bin/env bash
# Plan 0010 — CMS nyaman dipakai di HP.
#
# Yang dijaga: baris varian tidak lagi tumpang tindih / diperas, form jadi satu
# kolom di HP, target sentuh >=44px, font input 16px (cegah auto-zoom iOS).
#
# ⚠️ Cek CSS dibaca dari BUNDLE (dist/assets/store-*.css), bukan store.css —
# karena minifier mengubah bentuk, dan bundle itulah yang benar-benar dikirim.
# Cek markup dari BUNDLE JS (dist/assets/adminProducts-*.js) karena baris varian
# dibuat runtime (HTML statis tidak memuatnya).
set -u
ROOT="${1:-/home/dev/projects/ataratextile}"
D="$ROOT/dist"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "PASS: $1"; }
bad(){ FAIL=$((FAIL+1)); echo "FAIL: $1"; }

echo "═══ Suite: CMS mobile (plan 0010) ═══"

# Cari di SEMUA bundle store-*.css (hash berubah tiap build).
CSS=""
for f in "$D"/assets/store-*.css; do [ -f "$f" ] && CSS="$CSS$(cat "$f")"; done
JS=""
for f in "$D"/assets/adminProducts-*.js; do [ -f "$f" ] && JS="$JS$(cat "$f")"; done

if [ -z "$CSS" ]; then bad "1. bundle CSS store-*.css tidak ditemukan di $D"; exit 1; fi
if [ -z "$JS" ]; then bad "2. bundle JS adminProducts-*.js tidak ditemukan di $D"; exit 1; fi

# ── 1. Akar bug dibuang: grid berkolom TETAP untuk .variant-row ──
case "$CSS" in
  *'.variant-row{grid-template-columns:minmax(0,1fr) repeat(3,'*)
    bad "3. masih ada .variant-row grid berkolom tetap (sumber bug 24px)";;
  *) ok "3. tidak ada lagi .variant-row grid berkolom tetap";;
esac

# ── 2. Baris varian memakai flexbox yang membungkus ──
case "$CSS" in
  *'.variant-row{display:flex;flex-wrap:wrap'*)
    ok "4. .variant-row pakai flex + flex-wrap";;
  *) bad "4. .variant-row bukan flex-wrap (input bisa diperas)";;
esac

# ── 3. Input varian punya lantai lebar ──
case "$CSS" in
  *'.variant-row>span:not(.badge){flex:1 1 150px;min-width:110px'*)
    ok "5. input/nama varian punya flex-basis + min-width";;
  *) bad "5. tidak ada lantai lebar di baris varian";;
esac

# ── 4. Label per input (Harga/Grosir/Stok) — markup dari bundle JS ──
for label in Harga Grosir Stok; do
  case "$JS" in
    *"vf\"><span>$label</span>"*) ok "6. label '$label' ada di baris varian";;
    *) bad "6. label '$label' tidak ada di baris varian";;
  esac
done
case "$JS" in
  *'class="vf"'*) ok "7. input varian dibungkus label .vf";;
  *) bad "7. input varian tidak dibungkus .vf";;
esac

# ── 5. Form satu kolom di HP ──
case "$CSS" in
  *'.inline-form{display:grid;grid-template-columns:minmax(0,1fr)'*)
    ok "8. .inline-form jadi satu kolom di HP";;
  *) bad "8. .inline-form tidak satu kolom di HP";;
esac
case "$CSS" in
  *'.inline-form input,.inline-form select{min-width:120px;flex:1 1 120px'*)
    ok "9. kontrol form punya lantai 120px (tidak diperas)";;
  *) bad "9. kontrol form bisa diperas <120px";;
esac

# ── 6. Target sentuh >=44px ──
case "$CSS" in
  *'.btn,.chip,.inline-form button,.variant-row button,.bulk-controls button{min-height:44px}'*)
    ok "10. tombol >=44px di HP";;
  *) bad "10. tombol tidak dijamin >=44px";;
esac
case "$CSS" in
  *'.admin-tab{min-height:44px'*)
    ok "11. tab >=44px (target sentuh)";;
  *) bad "11. tab < 44px";;
esac

# ── 7. Font input 16px (cegah auto-zoom iOS) ──
case "$CSS" in
  *'input,select,textarea{font-size:16px}'*)
    ok "12. input font 16px (cegah zoom iOS)";;
  *) bad "12. input font < 16px → iOS auto-zoom";;
esac

# ── 8. Media query yang benar ──
# ⚠️ Minifier membuang spasi setelah `@media` → cari `@media(max-width:640px)`.
case "$CSS" in
  *'@media(max-width:640px)'*) ok "13. ada breakpoint 640px (HP)";;
  *) bad "13. tidak ada breakpoint 640px";;
esac
case "$CSS" in
  *'@media(pointer:coarse)'*) ok "14. ada @media(pointer:coarse) untuk perangkat sentuh";;
  *) bad "14. tidak ada pointer:coarse";;
esac

# ── 9. Tipografi mikro dinaikkan ──
case "$CSS" in
  *'.table-wrap th,.line-items th,.field label'*'font-size:11px'*)
    ok "15. teks mikro dinaikkan ke 11px di HP";;
  *) bad "15. teks mikro masih 9-10px";;
esac

# ── 10. Regresi yang harus TETAP ada ──
case "$CSS" in
  *'[hidden]{display:none!important}'*) ok "16. penjaga [hidden] (plan 0009) masih ada";;
  *) bad "16. penjaga [hidden] hilang — regresi 0009";;
esac
case "$CSS" in
  *'.kpi-strip{grid-template-columns:repeat(2,minmax(0,1fr))}'*)
    ok "17. KPI strip 2 kolom di HP (plan 0007) masih ada";;
  *) bad "17. regresi plan 0007 (kpi-strip)";;
esac
case "$CSS" in
  *'.badge--low-stock'*) ok "18. badge stok menipis (plan 2D) masih ada";;
  *) bad "18. regresi plan 2D (badge--low-stock)";;
esac

echo
echo "HASIL: $PASS PASS, $FAIL FAIL"
[ "$FAIL" -eq 0 ] || exit 1
