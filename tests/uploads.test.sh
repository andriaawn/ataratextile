#!/usr/bin/env bash
# Test Fase 2A — upload gambar produk (plan 0006).
# Cara pakai: bash tests/uploads.test.sh <BASE_URL> [ADMIN_EMAIL] [ADMIN_PASSWORD]
# WAJIB dijalankan terhadap DB throwaway + public/ throwaway (bukan produksi).
set -u
BASE="${1:-http://127.0.0.1:8881}"
ADMIN_EMAIL="${2:-admin@test.local}"
ADMIN_PASSWORD="${3:-Test-Passw0rd-2026-Str0ng}"
PASS=0; FAIL=0
ok()  { echo "  ✅ PASS  $1"; PASS=$((PASS+1)); }
bad() { echo "  ❌ FAIL  $1"; FAIL=$((FAIL+1)); }
JAR=$(mktemp)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK" "$JAR"' EXIT

echo "=== Fase 2A: upload gambar produk ($BASE) ==="

fetch() { local out; out=$(curl -s -m 8 "$BASE$1"); case "$out" in *"Terlalu banyak request"*) THROTTLED=$((THROTTLED+1));; esac; printf '%s' "$out"; }
THROTTLED=0

# ---- Fixture: gambar asli (PNG besar, JPEG kecil) + file jahat ----
ffmpeg -y -hide_banner -loglevel error -f lavfi -i testsrc=size=2200x1400:duration=1 -frames:v 1 "$WORK/besar.png" 2>/dev/null
ffmpeg -y -hide_banner -loglevel error -f lavfi -i testsrc=size=120x90:duration=1  -frames:v 1 "$WORK/kecil.jpg" 2>/dev/null
printf '<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>' > "$WORK/jahat.svg"
printf 'bukan gambar sama sekali' > "$WORK/teks.png"
python3 -c "import sys; sys.stdout.buffer.write(b'\x89PNG\r\n\x1a\n' + b'\x00'*(9*1024*1024))" > "$WORK/besar-banget.png"

# ---- 1. Guest DITOLAK di semua endpoint upload ----
for ep in "POST /api/admin/uploads" "GET /api/admin/uploads" "DELETE /api/admin/uploads/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.png"; do
  M="${ep%% *}"; P="${ep#* }"
  C=$(curl -s -m 8 -o /dev/null -w '%{http_code}' -X "$M" "$BASE$P" --data-binary @"$WORK/kecil.jpg" -H 'Content-Type: image/jpeg')
  [ "$C" = "401" ] && ok "Guest $M $P ditolak (401)" || bad "Guest $M $P = $C (harus 401)"
done

# ---- 2. Login admin ----
L=$(curl -s -m 8 -c "$JAR" -o /dev/null -w '%{http_code}' -X POST "$BASE/api/auth/login" \
  -H 'Content-Type: application/json' -d "{\"email\":\"$ADMIN_EMAIL\",\"password\":\"$ADMIN_PASSWORD\"}")
[ "$L" = "200" ] && ok "Login admin berhasil (200)" || bad "Login admin = $L"

# ---- 3. Upload PNG besar → 201 + di-resize ----
UP=$(curl -s -m 30 -b "$JAR" -X POST "$BASE/api/admin/uploads" --data-binary @"$WORK/besar.png" -H 'Content-Type: image/png')
URL=$(echo "$UP" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("url",""))' 2>/dev/null)
NAME=$(basename "$URL" 2>/dev/null)
if [ -n "$URL" ]; then ok "Upload PNG berhasil → $URL"; else bad "Upload PNG gagal: $UP"; fi
if echo "$NAME" | grep -qE '^[a-f0-9]{32}\.png$'; then ok "Nama file = hash isi (32 hex) + .png"; else bad "Nama file tidak sesuai pola: '$NAME'"; fi

BYTES=$(echo "$UP" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("bytes",0))' 2>/dev/null)
ORIG=$(echo "$UP" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("originalBytes",0))' 2>/dev/null)
if [ "${BYTES:-0}" -lt "${ORIG:-0}" ] && [ "${BYTES:-0}" -gt 0 ]; then
  ok "Gambar di-resize ($ORIG → $BYTES byte)"
else
  bad "Resize tidak jalan (orig=$ORIG hasil=$BYTES)"
fi

# ---- 4. File benar-benar dilayani + content-type gambar ----
CT=$(curl -s -m 8 -o /dev/null -w '%{http_code} %{content_type}' "$BASE$URL")
case "$CT" in
  200\ image/*) ok "Gambar dilayani (200, $CT)" ;;
  *) bad "Gambar tidak dilayani: $CT" ;;
esac

# ---- 5. Idempoten: upload isi sama → nama sama, tidak menumpuk ----
UP2=$(curl -s -m 30 -b "$JAR" -X POST "$BASE/api/admin/uploads" --data-binary @"$WORK/besar.png" -H 'Content-Type: image/png')
URL2=$(echo "$UP2" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("url",""))' 2>/dev/null)
[ "$URL" = "$URL2" ] && ok "Upload ulang isi sama → nama sama (tidak menumpuk)" || bad "Nama berubah: $URL vs $URL2"

# ---- 6. File jahat DITOLAK walau Content-Type dipalsukan ----
for f in "jahat.svg:image/svg+xml" "teks.png:image/png"; do
  FN="${f%%:*}"; MT="${f##*:}"
  C=$(curl -s -m 15 -b "$JAR" -o /dev/null -w '%{http_code}' -X POST "$BASE/api/admin/uploads" --data-binary @"$WORK/$FN" -H "Content-Type: $MT")
  [ "$C" = "400" ] && ok "File '$FN' (Content-Type dipalsukan '$MT') ditolak (400)" || bad "File '$FN' = $C (harus 400)"
done

# ---- 7. Melebihi 8 MB ditolak ----
C=$(curl -s -m 30 -b "$JAR" -o /dev/null -w '%{http_code}' -X POST "$BASE/api/admin/uploads" --data-binary @"$WORK/besar-banget.png" -H 'Content-Type: image/png')
[ "$C" = "413" ] && ok "File >8 MB ditolak (413)" || bad "File >8 MB = $C (harus 413)"

# ---- 8. Daftar upload menampilkan file ----
LIST=$(curl -s -m 8 -b "$JAR" "$BASE/api/admin/uploads")
if echo "$LIST" | grep -q "$NAME"; then ok "Daftar upload menampilkan file"; else bad "File tidak muncul di daftar: $LIST"; fi

# ---- 9. Galeri: tambah gambar ke produk ----
PID=$(curl -s -m 8 "$BASE/api/products" | python3 -c 'import json,sys; p=json.load(sys.stdin).get("products") or []; print(p[0]["id"] if p else "")' 2>/dev/null)
SLUG=$(curl -s -m 8 "$BASE/api/products" | python3 -c 'import json,sys; p=json.load(sys.stdin).get("products") or []; print(p[0]["slug"] if p else "")' 2>/dev/null)
IMGID=$(curl -s -m 8 -b "$JAR" -X POST "$BASE/api/admin/products/$PID/images" -H 'Content-Type: application/json' \
  -d "{\"url\":\"$URL\",\"alt\":\"Uji galeri\"}" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("id",""))' 2>/dev/null)
[ -n "$IMGID" ] && ok "Tambah gambar ke galeri produk (id=$IMGID)" || bad "Gagal tambah gambar ke galeri"

# ---- 10. Gambar muncul di endpoint publik ----
PUB=$(curl -s -m 8 "$BASE/api/products/$SLUG")
if echo "$PUB" | grep -q "$URL"; then ok "Gambar muncul di /api/products/:slug (halaman toko)"; else bad "Gambar tidak muncul di endpoint publik"; fi

# ---- 11. Gambar utama (sort_order 0) ----
# Produk seed SUDAH punya gambar utama, jadi gambar baru masuk urutan berikutnya.
if echo "$PUB" | grep -q "\"image\":\"$URL\""; then bad "Gambar baru menimpa gambar utama tanpa diminta"; else ok "Gambar baru tidak menimpa gambar utama (perilaku benar)"; fi

# ---- 11b. Produk tanpa gambar: gambar pertama otomatis jadi utama ----
# POST /api/admin/products selalu menyisipkan 1 gambar default, jadi skenario
# "tanpa gambar" dibuat dengan menghapus gambar itu dulu.
NEWPID=$(curl -s -m 8 -b "$JAR" -X POST "$BASE/api/admin/products" -H 'Content-Type: application/json' \
  -d "{\"category_id\":1,\"name\":\"Produk Uji Galeri\",\"slug\":\"produk-uji-galeri-$RANDOM\",\"sku\":\"UJI-$RANDOM\",\"description\":\"uji\",\"material\":\"uji\",\"construction\":\"uji\",\"gsm\":150,\"width\":\"150 cm\",\"weight_per_yard\":\"200 g/yard\",\"recommended_usage\":\"uji\",\"status\":\"active\"}" \
  | python3 -c 'import json,sys; print((json.load(sys.stdin).get("product") or {}).get("id",""))' 2>/dev/null)
if [ -n "$NEWPID" ]; then
  DEFID=$(curl -s -m 8 -b "$JAR" "$BASE/api/admin/products/$NEWPID/images" | python3 -c 'import json,sys; i=json.load(sys.stdin).get("images") or []; print(i[0]["id"] if i else "")' 2>/dev/null)
  curl -s -m 8 -b "$JAR" -o /dev/null -X DELETE "$BASE/api/admin/products/$NEWPID/images/$DEFID"
  curl -s -m 8 -b "$JAR" -o /dev/null -X POST "$BASE/api/admin/products/$NEWPID/images" -H 'Content-Type: application/json' -d "{\"url\":\"$URL\"}"
  NIMG=$(curl -s -m 8 -b "$JAR" "$BASE/api/admin/products/$NEWPID/images" | python3 -c 'import json,sys; i=json.load(sys.stdin).get("images") or []; print(i[0]["sort_order"] if i else "x")' 2>/dev/null)
  [ "$NIMG" = "0" ] && ok "Produk tanpa gambar → gambar pertama otomatis utama (sort_order 0)" || bad "sort_order gambar pertama = $NIMG (harus 0)"
else
  bad "Gagal buat produk uji"
fi

# ---- 11c. Endpoint /primary memindahkan gambar utama ----
NEWID=$(curl -s -m 8 -b "$JAR" "$BASE/api/admin/products/$PID/images" | python3 -c 'import json,sys; i=json.load(sys.stdin).get("images") or []; print(i[-1]["id"] if i else "")' 2>/dev/null)
curl -s -m 8 -b "$JAR" -o /dev/null -X PATCH "$BASE/api/admin/products/$PID/images/$NEWID/primary"
AFTER=$(curl -s -m 8 "$BASE/api/products/$SLUG" | python3 -c 'import json,sys; print(json.load(sys.stdin)["product"]["image"])' 2>/dev/null)
if [ "$AFTER" != "/img/double-pique-165-blend.jpg" ] && [ -n "$AFTER" ]; then
  ok "Endpoint /primary memindahkan gambar utama → $AFTER"
else
  bad "Gambar utama tidak berpindah: $AFTER"
fi

# ---- 12. URL gambar ngawur DITOLAK ----
for u in "http://evil.example.com/x.png" "/uploads/../../etc/passwd" "/uploads/bukanhex.png" "javascript:alert(1)"; do
  C=$(curl -s -m 8 -b "$JAR" -o /dev/null -w '%{http_code}' -X POST "$BASE/api/admin/products/$PID/images" \
    -H 'Content-Type: application/json' -d "{\"url\":\"$u\"}")
  [ "$C" = "400" ] && ok "URL ngawur ditolak (400): $u" || bad "URL '$u' = $C (harus 400)"
done

# ---- 13. Hapus gambar dari galeri → file fisik ikut hilang ----
# Pakai gambar UNIK di sini: gambar yang dipakai produk lain memang sengaja
# tidak dihapus (diuji di #14), jadi kalau pakai $URL yang sama hasilnya bias.
ffmpeg -y -hide_banner -loglevel error -f lavfi -i testsrc=size=300x200:duration=1 -frames:v 1 -vf "hue=h=90" "$WORK/unik.png" 2>/dev/null
UPU=$(curl -s -m 30 -b "$JAR" -X POST "$BASE/api/admin/uploads" --data-binary @"$WORK/unik.png" -H 'Content-Type: image/png')
URLU=$(echo "$UPU" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("url",""))' 2>/dev/null)
IMGU=$(curl -s -m 8 -b "$JAR" -X POST "$BASE/api/admin/products/$PID/images" -H 'Content-Type: application/json' -d "{\"url\":\"$URLU\"}" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("id",""))' 2>/dev/null)
curl -s -m 8 -b "$JAR" -o /dev/null -X DELETE "$BASE/api/admin/products/$PID/images/$IMGU"
C=$(curl -s -m 8 -o /dev/null -w '%{http_code}' "$BASE$URLU")
[ "$C" = "404" ] && ok "Hapus gambar galeri → file fisik ikut terhapus (404)" || bad "File masih ada: $C (harus 404)"

# ---- 14. File DIPAKAI produk lain → JANGAN dihapus ----
UP3=$(curl -s -m 30 -b "$JAR" -X POST "$BASE/api/admin/uploads" --data-binary @"$WORK/kecil.jpg" -H 'Content-Type: image/jpeg')
URL3=$(echo "$UP3" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("url",""))' 2>/dev/null)
PID2=$(curl -s -m 8 "$BASE/api/products" | python3 -c 'import json,sys; p=json.load(sys.stdin).get("products") or []; print(p[1]["id"] if len(p)>1 else "")' 2>/dev/null)
A=$(curl -s -m 8 -b "$JAR" -X POST "$BASE/api/admin/products/$PID/images"  -H 'Content-Type: application/json' -d "{\"url\":\"$URL3\"}" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("id",""))' 2>/dev/null)
B=$(curl -s -m 8 -b "$JAR" -X POST "$BASE/api/admin/products/$PID2/images" -H 'Content-Type: application/json' -d "{\"url\":\"$URL3\"}" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("id",""))' 2>/dev/null)
curl -s -m 8 -b "$JAR" -o /dev/null -X DELETE "$BASE/api/admin/products/$PID/images/$A"
C=$(curl -s -m 8 -o /dev/null -w '%{http_code}' "$BASE$URL3")
[ "$C" = "200" ] && ok "File dipakai produk lain → tidak ikut terhapus (200)" || bad "File terhapus padahal masih dipakai: $C"

# ---- 15. Hapus nama file path traversal DITOLAK ----
C=$(curl -s -m 8 -b "$JAR" -o /dev/null -w '%{http_code}' -X DELETE "$BASE/api/admin/uploads/..%2F..%2Fserver%2Findex.js")
[ "$C" = "400" ] && ok "Hapus nama path traversal ditolak (400)" || bad "Path traversal = $C (harus 400)"

# ---- 16. CSP mengizinkan blob: (pratinjau gambar sebelum unggah) ----
CSP=$(curl -s -m 8 -D - -o /dev/null "$BASE/admin/produk" | grep -i '^content-security-policy' | tr -d '\r')
if echo "$CSP" | grep -q "img-src 'self' data: blob:"; then ok "CSP mengizinkan blob: untuk pratinjau"; else bad "CSP belum izinkan blob:"; fi

# ---- 16b. Halaman Produk punya kontrol upload gambar (bukan cuma input URL) ----
PAGE=$(fetch /admin/produk)
if echo "$PAGE" | grep -q 'id="image-input"' && echo "$PAGE" | grep -q 'type="file"'; then ok "Halaman Produk punya input file gambar"; else bad "Input file gambar tidak ada di HTML"; fi
if echo "$PAGE" | grep -qE 'name="image"[^>]*type="text"'; then bad "Masih ada input URL gambar manual (diganti jadi hidden)"; else ok "Input URL gambar manual sudah diganti hidden"; fi
if echo "$PAGE" | grep -q 'id="gallery-grid"'; then ok "Panel galeri gambar ada di halaman Produk"; else bad "Panel galeri tidak ada"; fi

# ---- 16c. Bundle JS memuat logika upload & galeri ----
ASSET=$(echo "$PAGE" | grep -oE '/assets/adminProducts-[A-Za-z0-9_-]+\.js' | head -1)
BUNDLE=$(curl -s -m 8 "$BASE$ASSET")
if echo "$BUNDLE" | grep -q '/admin/uploads'; then ok "Bundle JS mengirim ke /api/admin/uploads"; else bad "Bundle JS tidak memanggil endpoint upload ($ASSET)"; fi
if echo "$BUNDLE" | grep -q 'gallery-grid'; then ok "Bundle JS menggambar galeri"; else bad "Bundle JS tidak menyentuh galeri"; fi
if echo "$BUNDLE" | grep -q 'dragover'; then ok "Bundle JS mendukung tarik-lepas (drag & drop)"; else bad "Tidak ada dukungan drag & drop"; fi

# ---- 16d. Penjaga listener: klik "Varian" berulang tidak menggandakan handler ----
if echo "$BUNDLE" | grep -q 'dataset.bound'; then ok "Bundle JS punya penjaga agar listener galeri tidak menumpuk"; else bad "Tidak ada penjaga listener (upload bisa berlipat)"; fi
# Cek berdasarkan JUMLAH kemunculan, bukan nama fungsi — minifier mengganti nama
# (pelajaran dari plan 0005: 'statusBadge' ikut di-rename).
INPUT_REFS=$(echo "$BUNDLE" | grep -o 'image-input' | wc -l | tr -d ' ')
if [ "$INPUT_REFS" -ge 2 ]; then ok "Bundle JS mereset pratinjau setelah form disimpan ($INPUT_REFS rujukan)"; else bad "Pratinjau tidak direset (hanya $INPUT_REFS rujukan)"; fi

# ---- 16e. Halaman toko menampilkan galeri (bukan cuma 1 gambar) ----
# Halaman memuat >1 bundle store-*.js (satu kecil untuk modulepreload), jadi
# gabungkan semuanya — jangan asal ambil yang pertama.
STORE_PAGE=$(fetch /produk)
STORE_JS=""
for a in $(echo "$STORE_PAGE" | grep -oE '/assets/store-[A-Za-z0-9_-]+\.js'); do STORE_JS="$STORE_JS$(curl -s -m 8 "$BASE$a")"; done
if echo "$STORE_JS" | grep -q 'thumb-row'; then ok "Halaman produk toko punya baris thumbnail"; else bad "Halaman toko masih 1 gambar (tidak ada thumb-row)"; fi
if echo "$STORE_JS" | grep -q 'product-main'; then ok "Halaman toko bisa ganti gambar utama"; else bad "Tidak bisa ganti gambar utama"; fi

# ---- 17. Header keamanan lain masih utuh (tidak ada regresi) ----
if echo "$CSP" | grep -q "object-src 'none'" && echo "$CSP" | grep -q "frame-ancestors 'none'"; then
  ok "CSP lain masih utuh (object-src, frame-ancestors)"
else
  bad "CSP lain rusak"
fi

echo
# Server membatasi 120 request/menit per IP. Suite ini mengirim ~45 request, jadi
# JANGAN dijalankan berulang di server yang sama dalam satu menit — hasilnya
# akan menyesatkan (elemen "hilang" padahal cuma kena 429).
if [ "${THROTTLED:-0}" -gt 0 ]; then
  echo "⚠️  $THROTTLED respons kena rate limit (429) — jalankan ulang terhadap server BARU."
fi
echo "=== HASIL: $PASS PASS / $FAIL FAIL ==="
[ "$FAIL" -eq 0 ]
