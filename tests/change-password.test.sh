#!/usr/bin/env bash
# Test plan 0008 — ganti password sendiri dari CMS.
# Cara pakai: bash tests/change-password.test.sh <BASE_URL> <ADMIN_EMAIL> <ADMIN_PASSWORD>
#
# ⚠️ URUTAN PENTING: endpoint punya rate limit 5 gagal / 15 menit per IP.
#    Tes rate limit diletakkan PALING AKHIR, karena setelah kena 429 endpoint
#    terkunci 15 menit dan tes sesudahnya akan gagal palsu.
set -u
BASE="${1:-http://127.0.0.1:8881}"
ADMIN_EMAIL="${2:-admin@test.local}"
ADMIN_PASSWORD="${3:-Test-Passw0rd-2026-Str0ng}"
PASS=0; FAIL=0
ok()  { echo "  ✅ PASS  $1"; PASS=$((PASS+1)); }
bad() { echo "  ❌ FAIL  $1"; FAIL=$((FAIL+1)); }

JAR=$(mktemp)      # sesi utama
JAR2=$(mktemp)     # sesi kedua (perangkat lain)
NEW_PASSWORD='Ganti-Baru-2026-Kuat!x'
NEW_PASSWORD2='Ganti-Lagi-2026-Kuat!y'

echo "=== Ganti password admin (plan 0008) — $BASE ==="

# ---- 0. markup UI ada di hasil build (minifier-safe: cek string selector) ----
if [ -f dist/admin.html ]; then
  ok_markup=0
  for m in password-panel password-current password-new password-repeat password-submit; do
    grep -q "$m" dist/admin.html || { bad "0. markup UI: '$m' hilang dari dist/admin.html"; ok_markup=1; }
  done
  CSSFILE=$(ls dist/assets/store-*.css 2>/dev/null | head -1)
  # ⚠️ Jangan ambil satu file: ada beberapa bundle `store-*.js` (loader kecil + isi).
  # Cari di SEMUA bundle, kalau tidak tesnya gagal palsu tergantung urutan `ls`.
  JSFILES=$(ls dist/assets/store-*.js 2>/dev/null)
  [ -n "$CSSFILE" ] && grep -q 'password-panel' "$CSSFILE" || { bad "0. CSS .password-panel hilang dari bundle"; ok_markup=1; }
  if [ -n "$JSFILES" ]; then
    grep -q 'change-password' $JSFILES || { bad "0. JS tidak memanggil /auth/change-password"; ok_markup=1; }
    grep -q 'password-repeat' $JSFILES || { bad "0. JS tidak memakai field ulangi password"; ok_markup=1; }
  fi
  [ "$ok_markup" -eq 0 ] && ok "0. markup UI lengkap di dist (form + CSS + pemanggilan endpoint)"
else
  echo "  (skip markup: dist/ tidak ada — mode uji live)"
fi

login() { # $1=jar $2=password -> http code
  curl -s -m 8 -c "$1" -o /dev/null -w '%{http_code}' -X POST "$BASE/api/auth/login" \
    -H 'Content-Type: application/json' \
    -d "{\"email\":\"$ADMIN_EMAIL\",\"password\":\"$2\"}"
}
change() { # $1=jar $2=current $3=new -> "CODE|BODY"
  curl -s -m 8 -b "$1" -w '\n%{http_code}' -X POST "$BASE/api/auth/change-password" \
    -H 'Content-Type: application/json' \
    -d "{\"current_password\":\"$2\",\"new_password\":\"$3\"}"
}
me() { curl -s -m 8 -o /dev/null -w '%{http_code}' -b "$1" "$BASE/api/auth/me"; }

# ---- 1. tanpa login -> 401 ----
CODE=$(curl -s -m 8 -o /dev/null -w '%{http_code}' -X POST "$BASE/api/auth/change-password" \
  -H 'Content-Type: application/json' -d '{"current_password":"x","new_password":"y"}')
[ "$CODE" = "401" ] && ok "1. tanpa login ditolak (401)" || bad "1. tanpa login = HTTP $CODE (harus 401)"

# ---- login 2 sesi (simulasi 2 perangkat) ----
C=$(login "$JAR" "$ADMIN_PASSWORD")
[ "$C" = "200" ] && ok "2a. login sesi #1 berhasil" || bad "2a. login sesi #1 = HTTP $C"
C=$(login "$JAR2" "$ADMIN_PASSWORD")
[ "$C" = "200" ] && ok "2b. login sesi #2 berhasil (perangkat lain)" || bad "2b. login sesi #2 = HTTP $C"

# ---- 3. field kosong -> 400 ----
CODE=$(curl -s -m 8 -o /dev/null -w '%{http_code}' -b "$JAR" -X POST "$BASE/api/auth/change-password" \
  -H 'Content-Type: application/json' -d '{"current_password":"","new_password":""}')
[ "$CODE" = "400" ] && ok "3. field kosong ditolak (400)" || bad "3. field kosong = HTTP $CODE (harus 400)"

# ---- 4. password sekarang SALAH -> 401, dan password TIDAK berubah ----
OUT=$(change "$JAR" "Password-Salah-Sekali-99" "$NEW_PASSWORD")
CODE=$(echo "$OUT" | tail -1)
[ "$CODE" = "401" ] && ok "4a. password sekarang salah ditolak (401)" || bad "4a. password salah = HTTP $CODE (harus 401)"
C=$(login "$JAR" "$ADMIN_PASSWORD")
[ "$C" = "200" ] && ok "4b. password lama MASIH berlaku setelah percobaan gagal" || bad "4b. password lama sudah tidak berlaku (HTTP $C) — percobaan gagal merusak akun!"
# sesi tidak boleh ikut terhapus saat gagal
[ "$(me "$JAR2")" = "200" ] && ok "4c. sesi lain tidak terhapus saat percobaan gagal" || bad "4c. sesi lain ikut terhapus saat gagal"

# ---- 5. password lemah -> 400 ----
for weak in 'pendek' 'admin123' 'password123'; do
  OUT=$(change "$JAR" "$ADMIN_PASSWORD" "$weak")
  CODE=$(echo "$OUT" | tail -1)
  [ "$CODE" = "400" ] && ok "5. password lemah '$weak' ditolak (400)" || bad "5. password lemah '$weak' = HTTP $CODE (harus 400)"
done

# ---- 6. password baru SAMA dengan sekarang -> 400 ----
OUT=$(change "$JAR" "$ADMIN_PASSWORD" "$ADMIN_PASSWORD")
CODE=$(echo "$OUT" | tail -1)
[ "$CODE" = "400" ] && ok "6. password baru sama dengan sekarang ditolak (400)" || bad "6. password sama = HTTP $CODE (harus 400)"

# ---- 7. SUKSES: ganti password ----
OUT=$(change "$JAR" "$ADMIN_PASSWORD" "$NEW_PASSWORD")
CODE=$(echo "$OUT" | tail -1)
BODY=$(echo "$OUT" | head -n -1)
[ "$CODE" = "204" ] && ok "7a. ganti password berhasil (204)" || bad "7a. ganti password = HTTP $CODE (harus 204)"
if echo "$BODY" | grep -qi "$NEW_PASSWORD\|$ADMIN_PASSWORD"; then
  bad "7b. password BOCOR di body respons!"
else
  ok "7b. respons tidak memuat password"
fi

# ---- 8. SEMUA sesi digugurkan (termasuk sesi #2 dari perangkat lain) ----
# Dicek TEPAT setelah ganti password, sebelum login ulang — kalau tidak, jar
# yang dipakai login ulang akan tampak "hidup" dan tesnya salah sendiri.
[ "$(me "$JAR2")" = "401" ] && ok "8a. sesi perangkat lain ikut gugur (401)" || bad "8a. sesi perangkat lain MASIH HIDUP — password baru tidak mengunci semua perangkat!"
[ "$(me "$JAR")" = "401" ] && ok "8b. sesi sendiri ikut gugur (401)" || bad "8b. sesi sendiri masih hidup"

# ---- 9. password lama MATI, password baru HIDUP ----
C=$(login "$JAR" "$ADMIN_PASSWORD")
[ "$C" = "401" ] && ok "9a. password lama sudah TIDAK berlaku (401)" || bad "9a. password lama MASIH bisa login (HTTP $C)!"
C=$(login "$JAR" "$NEW_PASSWORD")
[ "$C" = "200" ] && ok "9b. password baru bisa login (200)" || bad "9b. password baru GAGAL login (HTTP $C)"

# ---- 10. setelah ganti, password kedua kalinya pakai password BARU ----
C=$(login "$JAR" "$NEW_PASSWORD")
[ "$C" = "200" ] && ok "10a. login ulang pakai password baru berhasil" || bad "10a. login ulang = HTTP $C"
OUT=$(change "$JAR" "$NEW_PASSWORD" "$NEW_PASSWORD2")
CODE=$(echo "$OUT" | tail -1)
[ "$CODE" = "204" ] && ok "10b. ganti password kedua kali berhasil" || bad "10b. ganti kedua kali = HTTP $CODE"

# ---- 11. endpoint lain tidak terpengaruh (produk masih publik) ----
CODE=$(curl -s -m 8 -o /dev/null -w '%{http_code}' "$BASE/api/products")
[ "$CODE" = "200" ] && ok "11. endpoint publik tetap normal (200)" || bad "11. endpoint publik = HTTP $CODE"

# ---- 12. RATE LIMIT (paling akhir — mengunci endpoint 15 menit) ----
# 5 percobaan GAGAL berturut-turut -> yang ke-6 harus 429.
C=$(login "$JAR" "$NEW_PASSWORD2")
if [ "$C" != "200" ]; then
  echo "  (skip rate limit: tidak bisa login ulang, HTTP $C)"
else
  LAST=""
  for i in 1 2 3 4 5 6; do
    LAST=$(curl -s -m 8 -o /dev/null -w '%{http_code}' -b "$JAR" -X POST "$BASE/api/auth/change-password" \
      -H 'Content-Type: application/json' -d '{"current_password":"SalahTerus-99","new_password":"Tidak-Penting-2026-x"}')
  done
  [ "$LAST" = "429" ] && ok "12. rate limit aktif setelah 5 gagal (429)" || bad "12. rate limit TIDAK aktif, percobaan ke-6 = HTTP $LAST (harus 429)"
fi

echo
echo "────────────────────────────────────────"
echo "  PASS: $PASS   FAIL: $FAIL"
echo "────────────────────────────────────────"
rm -f "$JAR" "$JAR2"
[ "$FAIL" -eq 0 ]
