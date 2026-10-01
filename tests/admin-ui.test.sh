#!/usr/bin/env bash
# Test plan 0005 — kerapihan UI/UX CMS admin.
# Cara pakai: bash tests/admin-ui.test.sh <BASE_URL>
# WAJIB dijalankan terhadap DB throwaway (bukan data/atandra.sqlite produksi).
set -u
BASE="${1:-http://127.0.0.1:8880}"
PASS=0; FAIL=0
ok()  { echo "  ✅ PASS  $1"; PASS=$((PASS+1)); }
bad() { echo "  ❌ FAIL  $1"; FAIL=$((FAIL+1)); }

echo "=== Test UI/UX CMS admin ($BASE) ==="

fetch() { curl -s -m 8 "$BASE$1"; }

# ---- 1. Dashboard: bahasa Indonesia (bukan Inggris) ----
DASH=$(fetch /admin)
if echo "$DASH" | grep -q 'Akses admin'; then ok "Dashboard: panel login pakai bahasa Indonesia"; else bad "Dashboard: masih 'Admin access'"; fi
if echo "$DASH" | grep -q '<th>Pelanggan</th>'; then ok "Dashboard: header tabel Indonesia (Pelanggan)"; else bad "Dashboard: header tabel masih Inggris"; fi
if echo "$DASH" | grep -qE '<th>Customer</th>|<th>Payment</th>'; then bad "Dashboard: masih ada header Inggris"; else ok "Dashboard: nol header tabel Inggris"; fi

# ---- 2. Anti-kedip: panel login punya atribut hidden DI HTML ----
AUTH_TAG=$(echo "$DASH" | grep -oE 'id="admin-auth"[^>]*' | head -1)
if echo "$AUTH_TAG" | grep -q 'hidden'; then ok "Dashboard: #admin-auth punya 'hidden' di HTML (tidak berkedip)"; else bad "Dashboard: #admin-auth tanpa 'hidden' → form berkedip"; fi

PROD=$(fetch /admin/produk)
P_TAG=$(echo "$PROD" | grep -oE 'id="products-auth"[^>]*' | head -1)
if echo "$P_TAG" | grep -q 'hidden'; then ok "Produk: #products-auth punya 'hidden' di HTML"; else bad "Produk: #products-auth tanpa 'hidden' → form berkedip"; fi

# ---- 3. Judul tab konsisten ----
T1=$(echo "$DASH" | grep -oE '<title>[^<]*' | head -1)
T2=$(echo "$PROD" | grep -oE '<title>[^<]*' | head -1)
T3=$(fetch /admin/pesanan | grep -oE '<title>[^<]*' | head -1)
for t in "$T1" "$T2" "$T3"; do
  if echo "$t" | grep -q -- '— Admin Atandra'; then :; else bad "Judul tab tidak konsisten: $t"; fi
done
[ "$FAIL" -eq 0 ] && ok "Judul tab 3 halaman konsisten ('— Admin Atandra')"

# ---- 4. Halaman Produk: bahasa Indonesia ----
if echo "$PROD" | grep -q '<th>Produk</th>' && echo "$PROD" | grep -q '<th>Aksi</th>'; then ok "Produk: header tabel Indonesia"; else bad "Produk: header tabel masih Inggris"; fi
if echo "$PROD" | grep -qE 'Product operations|Catalog structure|Create product|>Archive<|>Variant<'; then bad "Produk: masih ada label Inggris"; else ok "Produk: nol label Inggris"; fi

# ---- 5. Bug nama dobel: kategori dirender dengan class .sub (dipasang JS) ----
# .sub ada di bundle JS, bukan HTML statis — jadi cari di berkas JS halaman Produk.
JS_NAME=$(echo "$PROD" | grep -oE 'adminProducts-[A-Za-z0-9_-]+\.js' | head -1)
if [ -z "$JS_NAME" ]; then
  bad "Tidak menemukan bundle adminProducts dari halaman Produk"
else
  JS=$(curl -s -m 8 "$BASE/assets/$JS_NAME")
  if echo "$JS" | grep -q 'class="sub"'; then ok "Produk: kategori memakai .sub (bug nama dobel diperbaiki)"; else bad "Produk: kategori masih tanpa .sub"; fi
  # Minifier mengganti nama fungsi, jadi periksa MARKUP badge-nya, bukan nama fungsi.
  if echo "$JS" | grep -q 'badge badge--'; then ok "Produk: status dirender sebagai badge"; else bad "Produk: status tidak pakai badge"; fi
  if echo "$JS" | grep -qE '>Archive<|>Variant<|Archive produk'; then bad "Produk: masih ada teks Inggris di JS"; else ok "Produk: nol teks Inggris di JS"; fi
fi

# ---- 6. CSS: cincin fokus ada ----
CSS_NAME=$(echo "$DASH" | grep -oE 'store-[A-Za-z0-9_-]+\.css' | head -1)
if [ -z "$CSS_NAME" ]; then
  bad "Tidak menemukan file CSS dari halaman admin"
else
  CSS=$(curl -s -m 8 "$BASE/assets/$CSS_NAME")
  if echo "$CSS" | grep -q ':focus-visible'; then ok "CSS: aturan :focus-visible ada (cincin fokus)"; else bad "CSS: :focus-visible HILANG"; fi
  if echo "$CSS" | grep -q '#ffd166'; then ok "CSS: cincin fokus kuning (#ffd166)"; else bad "CSS: warna cincin fokus tidak ada"; fi

  # ---- 7. Token --text-muted sudah diperbaiki (bukan #8a9694 yang gagal AA) ----
  if echo "$CSS" | grep -q -- '--text-muted:#63716f'; then ok "CSS: --text-muted diperbaiki (#63716f, lolos AA)"; else bad "CSS: --text-muted masih nilai lama"; fi
  if echo "$CSS" | grep -q -- '--text-muted:#8a9694'; then bad "CSS: masih ada --text-muted:#8a9694 (gagal AA)"; else ok "CSS: nol --text-muted:#8a9694"; fi

  # ---- 8. Badge status produk ----
  if echo "$CSS" | grep -q '.badge--active' && echo "$CSS" | grep -q '.badge--draft'; then ok "CSS: badge status produk ada"; else bad "CSS: badge status produk HILANG"; fi

  # ---- 9. spec-grid small tidak lagi pakai #9aa5a2 (gagal kontras di paper) ----
  if echo "$CSS" | grep -oE '\.spec-grid small\{[^}]*\}' | grep -q '#9aa5a2'; then bad "CSS: .spec-grid small masih #9aa5a2 (2.50, gagal AA)"; else ok "CSS: .spec-grid small tidak lagi #9aa5a2"; fi
fi

echo
echo "=== HASIL: $PASS PASS / $FAIL FAIL ==="
[ "$FAIL" -eq 0 ]
