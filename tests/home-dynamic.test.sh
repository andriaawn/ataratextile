#!/usr/bin/env bash
# Test plan 0014 Fix B — beranda dinamis (kartu dari /api/products, bukan hardcode).
# WAJIB di DB throwaway.
set -u
BASE="${1:-http://127.0.0.1:8877}"
PASS=0; FAIL=0
ok()  { echo "  ✅ PASS  $1"; PASS=$((PASS+1)); }
bad() { echo "  ❌ FAIL  $1"; FAIL=$((FAIL+1)); }
PY() { python3 -c "$1" 2>/dev/null; }

echo "=== 0014 Fix B: beranda dinamis ($BASE) ==="

HTML=$(curl -s -m8 "$BASE/")

# ---- B1. nol kartu produk hardcode (grid diisi JS) ----
# Penanda: nama/SKU produk asli TIDAK boleh muncul di HTML statis.
NAMEDB=$(curl -s -m8 "$BASE/api/products" | PY 'import json,sys; print(json.load(sys.stdin)["products"][0]["name"])')
SKUDB=$(curl -s -m8 "$BASE/api/products" | PY 'import json,sys; print(json.load(sys.stdin)["products"][0]["sku"])')
if echo "$HTML" | grep -qF "$SKUDB"; then bad "B1. SKU produk ($SKUDB) masih hardcode di HTML"; else ok "B1. nol SKU produk hardcode di HTML"; fi

# ---- B2. ada container grid dinamis ----
echo "$HTML" | grep -q 'id="koleksi-grid"' && ok "B2. ada #koleksi-grid" || bad "B2. tidak ada #koleksi-grid"

# ---- B3. beranda memanggil /api/products ----
if echo "$HTML" | grep -qE "fetch\('/api/products'\)|/api/products"; then ok "B3. beranda memanggil /api/products"; else bad "B3. beranda tidak memanggil API"; fi

# ---- B4. filter masih ada (delegasi) ----
for f in all light medium structured; do
  echo "$HTML" | grep -q "data-filter=\"$f\"" && ok "B4. filter '$f' ada" || bad "B4. filter '$f' hilang"
done
echo "$HTML" | grep -q "closest('.filter')" && ok "B4b. filter pakai delegasi (closest)" || bad "B4b. filter tidak pakai delegasi"

# ---- B5. harga beranda dari DB (min_price), bukan hardcode ----
echo "$HTML" | grep -q "min_price" && ok "B5. kartu beranda memakai min_price" || bad "B5. kartu beranda tidak pakai min_price"
if echo "$HTML" | grep -qE '825000|825e3'; then bad "B5b. beranda masih ada 825000"; else ok "B5b. beranda nol 825000"; fi

# ---- B6. jumlah kartu yang dirender = jumlah produk API ----
# Cek statis: kode harus render list.map(...) (bukan jumlah tetap).
echo "$HTML" | grep -qE 'list\.map|\.map\(homeCard\)' && ok "B6. kartu dirender dari list API (map)" || bad "B6. kartu tidak dirender dari list"

# ---- B7. gagal API → pesan jujur (bukan kartu palsu) ----
echo "$HTML" | grep -q "gagal dimuat" && ok "B7. ada pesan gagal-muat (jujur)" || bad "B7. tidak ada penanganan gagal API"

# ---- B8. hero & section marketing tetap ada (tidak rusak) ----
for s in id=\"spesifikasi\" id=\"keunggulan\" id=\"faq\"; do
  echo "$HTML" | grep -q "$s" && ok "B8. section ${s#id=} tetap ada" || bad "B8. section ${s#id=} hilang"
done

echo
echo "=== HASIL: $PASS PASS / $FAIL FAIL ==="
[ "$FAIL" -eq 0 ]
