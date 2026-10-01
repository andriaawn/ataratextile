#!/usr/bin/env bash
# Plan 0007 — halaman admin tidak boleh melebar di layar sempit.
# Cara pakai: bash tests/responsive.test.sh <BASE_URL>
#
# Kenapa test ini ada: `.admin-main{display:grid}` tanpa grid-template-columns
# membuat kolom implisit `auto`, yang TIDAK mau menyusut di bawah min-content
# (tabel 7 kolom ≈ 782px) → seluruh halaman melebar dan `.table-wrap{overflow:auto}`
# tidak menolong. Test ini menjaga aturan `minmax(0,1fr)` + `min-width:0` supaya
# tidak hilang lagi. Urutan juga dijaga: blok perbaikan harus SETELAH aturan lama,
# kalau tidak aturan lama yang menang.
set -uo pipefail

BASE="${1:-http://127.0.0.1:8881}"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  \033[32mPASS\033[0m %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  \033[31mFAIL\033[0m %s\n' "$1"; }

echo "═══ Plan 0007 — admin tidak melebar di layar sempit ═══"

# ---------- 1. Ketiga halaman admin ada & memuat store.css ----------
declare -A PAGES=(
  ["/admin"]="Dashboard"
  ["/admin/pesanan"]="Pesanan"
  ["/admin/produk"]="Produk"
)
CSS_PATH=""
for path in "${!PAGES[@]}"; do
  H=$(curl -s -m 8 "$BASE$path")
  if [ -z "$H" ]; then
    bad "1. $path tidak terjangkau"
    continue
  fi
  case "$H" in *'<title>'*) ok "1. $path terisi HTML";; *) bad "1. $path kosong";; esac
  case "$H" in
    *'admin-layout'*) ok "1. $path punya .admin-layout";;
    *) bad "1. $path tidak punya .admin-layout";;
  esac
  case "$H" in
    *'admin-main'*) ok "1. $path punya .admin-main";;
    *) bad "1. $path tidak punya .admin-main";;
  esac
  case "$H" in
    *'admin-side'*) ok "1. $path punya .admin-side";;
    *) bad "1. $path tidak punya .admin-side";;
  esac
  p=$(printf '%s' "$H" | grep -oE '/assets/store-[A-Za-z0-9_-]+\.css' | head -1)
  [ -n "$p" ] && CSS_PATH="$p"
done

if [ -z "$CSS_PATH" ]; then
  bad "1. bundle CSS tidak ditemukan"
  echo
  echo "═══ 0007: $pass PASS / $fail FAIL ═══"
  exit 1
fi
CSSB=$(curl -s -m 8 "$BASE$CSS_PATH")
[ -n "$CSSB" ] || { bad "1. CSS tidak terjangkau"; exit 1; }

# ---------- 2. Aturan perbaikan ada ----------
# Minifier membuang spasi, jadi cocokkan tanpa spasi.
case "$CSSB" in
  *'.admin-main{grid-template-columns:minmax(0,1fr)'*|*'.admin-main{grid-template-columns:minmax(0,1fr);'*)
    ok "2a. .admin-main pakai kolom minmax(0,1fr)";;
  *) bad "2a. .admin-main TIDAK pakai minmax(0,1fr) — halaman bisa melebar di HP";;
esac
case "$CSSB" in
  *'.admin-main{grid-template-columns:minmax(0,1fr);min-width:0}'*)
    ok "2b. .admin-main punya min-width:0";;
  *) bad "2b. .admin-main tidak punya min-width:0";;
esac
case "$CSSB" in
  *'.admin-side{min-width:0}'*) ok "2c. .admin-side punya min-width:0";;
  *) bad "2c. .admin-side tidak punya min-width:0";;
esac
case "$CSSB" in
  *'.admin-layout{grid-template-columns:minmax(0,220px) minmax(0,1fr)}'*)
    ok "2d. .admin-layout pakai minmax untuk kedua kolom";;
  *) bad "2d. .admin-layout masih pakai kolom 1fr telanjang";;
esac

# ---------- 3. KPI strip (penyebab overflow 11px di Dashboard) ----------
case "$CSSB" in
  *'.kpi-strip{grid-template-columns:repeat(4,minmax(0,1fr))}'*)
    ok "3a. .kpi-strip pakai repeat(4,minmax(0,1fr))";;
  *) bad "3a. .kpi-strip masih repeat(4,1fr) — label panjang memaksa melebar";;
esac
case "$CSSB" in
  *'.kpi-strip{grid-template-columns:repeat(2,minmax(0,1fr))}'*)
    ok "3b. .kpi-strip 2 kolom di layar sempit (minmax juga)";;
  *) bad "3b. .kpi-strip 2 kolom belum pakai minmax";;
esac

# ---------- 4. Breakpoint 760px masih ada untuk admin ----------
case "$CSSB" in
  *'max-width:760px'*) ok "4a. breakpoint 760px ada";;
  *) bad "4a. breakpoint 760px hilang";;
esac
case "$CSSB" in
  *'@media(max-width:760px){.admin-layout{grid-template-columns:minmax(0,1fr)}'*|*'.admin-layout{grid-template-columns:minmax(0,1fr)}.kpi-strip'*)
    ok "4b. di ≤760px .admin-layout jadi 1 kolom minmax";;
  *) bad "4b. .admin-layout tidak menumpuk 1 kolom di layar sempit";;
esac

# ---------- 5. URUTAN: blok perbaikan harus menang atas aturan lama ----------
# Kalau aturan lama (kolom 1fr) muncul SETELAH perbaikan, dia yang menang dan
# halaman melebar lagi — jadi urutan ikut dijaga, bukan cuma keberadaan.
# Catatan: pola aturan lama HARUS menyertakan sisa deklarasinya (gap/padding),
# kalau tidak pencarian gagal dan test memberi alarm palsu.
OLD=$(printf '%s' "$CSSB" | grep -bo 'admin-layout{display:grid;grid-template-columns:220px 1fr' | head -1 | cut -d: -f1)
NEW=$(printf '%s' "$CSSB" | grep -bo 'admin-layout{grid-template-columns:minmax(0,220px) minmax(0,1fr)}' | head -1 | cut -d: -f1)
if [ -n "$OLD" ] && [ -n "$NEW" ]; then
  if [ "$NEW" -gt "$OLD" ]; then
    ok "5a. blok perbaikan datang SETELAH aturan lama (menang urutan)"
  else
    bad "5a. blok perbaikan datang SEBELUM aturan lama — aturan lama yang menang"
  fi
elif [ -z "$OLD" ]; then
  ok "5a. aturan lama sudah tidak ada (perbaikan menggantikannya)"
else
  bad "5a. blok perbaikan tidak ditemukan di CSS"
fi
# .admin-main: aturan lama `display:grid` boleh tetap ada (itu yang membuat grid),
# asal pengunci `min-width:0` datang belakangan.
OLD2=$(printf '%s' "$CSSB" | grep -bo 'admin-main{display:grid;gap:20px;align-content:start}' | head -1 | cut -d: -f1)
NEW2=$(printf '%s' "$CSSB" | grep -bo 'admin-main{grid-template-columns:minmax(0,1fr);min-width:0}' | head -1 | cut -d: -f1)
if [ -n "$NEW2" ]; then
  if [ -z "$OLD2" ] || [ "$NEW2" -gt "$OLD2" ]; then
    ok "5b. pengunci .admin-main datang setelah display:grid"
  else
    bad "5b. pengunci .admin-main datang sebelum display:grid"
  fi
else
  bad "5b. pengunci .admin-main tidak ditemukan"
fi

# ---------- 6. Deklarasi EFEKTIF (yang terakhir) harus pakai minmax ----------
# Aturan lama boleh tetap ada di CSS (ditimpa). Yang menentukan adalah deklarasi
# TERAKHIR untuk selector itu — itulah yang dipakai browser.
check_last() {
  local sel="$1" prop="$2"
  local last
  last=$(printf '%s' "$CSSB" | grep -o "${sel}{${prop}:[^}]*}" | tail -1)
  case "$last" in
    *minmax*) ok "6. deklarasi efektif $sel pakai minmax → ${last}";;
    *) bad "6. deklarasi efektif $sel TIDAK pakai minmax → ${last:-tidak ada}";;
  esac
}
check_last '.admin-layout' 'grid-template-columns'
check_last '.admin-main' 'grid-template-columns'
check_last '.kpi-strip' 'grid-template-columns'

# ---------- 7. Drawer & modal tetap pakai min() (bukan lebar tetap) ----------
case "$CSSB" in
  *'width:min(460px,100%)'*) ok "7a. drawer pakai min(460px,100%)";;
  *) bad "7a. drawer bukan lebar adaptif";;
esac
case "$CSSB" in
  *'width:min(400px,100%)'*) ok "7b. modal pakai min(400px,100%)";;
  *) bad "7b. modal bukan lebar adaptif";;
esac

echo
echo "═══ 0007: $pass PASS / $fail FAIL ═══"
[ "$fail" -eq 0 ]
