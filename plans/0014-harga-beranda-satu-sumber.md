# 0014 — Harga & beranda dari satu sumber (DB), bukan angka hardcode

**Status:** MENUNGGU APPROVE
**Tanggal:** 2026-10-07
**Latar:** lanjutan `plans/0011-audit-cms.md`. Setelah 0013 menutup "uang dihitung dua tempat",
dua tempat lain masih menyalin data secara manual dari DB ke HTML/JS:

1. **Harga katalog diarang di klien.** `store.js` menulis `money(825000 + product.gsm * 1000)`
   untuk kartu di `/katalog`. `productSelect` (`/api/products`) bahkan **tidak** mengirim harga
   sama sekali. Rumus itu **kebetulan cocok** dengan harga DB sekarang (7/7 baris), tapi begitu
   harga diubah dari CMS admin, katalog tetap menampilkan angka lama → pelanggan lihat harga
   yang tidak ada di DB.
2. **Beranda hardcode.** `index.html` punya 15 `<article>` yang disalin manual dari 11 produk,
   **nol panggilan API**. Produk baru/berubah **tidak** muncul di beranda sampai ada yang
   mengedit HTML. Judul "11 Koleksi Double Pique" juga hardcode.

**Akar yang sama:** fakta yang ada di DB disalin manual ke HTML/JS → cepat basi.

## Solusi

Prinsip 0013: **satu sumber kebenaran.** Harga & daftar produk berasal dari DB lewat API.

**Fix A — harga katalog dari DB.**
- `productSelect`: tambah `MIN(v.price) AS min_price` (variabel `v` sudah di-JOIN, aman
  dengan `GROUP BY p.id`).
- `serializeProduct`: sertakan `min_price`.
- `store.js` `productCard`: `money(product.min_price)` ganti `825000 + product.gsm * 1000`.
  Kalau `min_price` null (produk tanpa varian) → tampil "Harga menyusul", bukan angka karangan.

**Fix B — beranda dinamis.**
- `index.html`: grid `#koleksi` dikosongkan (skeleton "Memuat…"), tetap ada filter
  all/light/medium/structured. Tambah `<script>` yang fetch `/api/products` lalu render kartu
  dengan gaya yang sama (`.card`/`.swatch`/`.card-body`/`.tag`/`.code`).
- Judul "11 Koleksi" → diisi dari jumlah produk nyata.
- Filter pakai **event delegation** (kartu sekarang dinamis, bukan statis).
- Kalau API gagal → tampil pesan jujur ("Koleksi gagal dimuat"), **bukan** kartu palsu.
- Kartu beranda juga menampilkan `min_price` dari DB (bukan cuma kode/gramasi).

**Nol rumus harga di klien** setelah ini — angka uang hanya lahir di server.

## File yang disentuh

- `server/index.js` — `productSelect` (+`min_price`), `serializeProduct`.
- `store.js` — `productCard` pakai `min_price`.
- `index.html` — grid dinamis + script render beranda.
- Test baru: `tests/catalog-price.test.sh`, `tests/home-dynamic.test.sh`.
- `plans/0014-harga-beranda-satu-sumber.md` (dokumen ini).

## Test (TDD, bukti GAGAL dulu)

- `catalog-price.test.sh`
  - `/api/products` mengirim `min_price` = `MIN(price)` DB (cek 1 produk vs DB).
  - Bundle klien **nol** pola `825000` / `825e3`.
  - Kartu katalog memakai harga DB (bukan rumus).
- `home-dynamic.test.sh`
  - `index.html` (yang dilayani) **nol** `<article class="card"` statis di grid.
  - Bundle beranda memanggil `/products`.
  - Jumlah kartu setelah render = jumlah produk dari API.
  - Filter `data-filter` masih ada & berfungsi (event delegation).
- **NC (non-negotiable):** jalankan ke `HEAD` → semua GAGAL.

## Acceptance (terukur)

1. `grep -c 825000` di bundle klien = **0**.
2. `GET /api/products` punya field `min_price` = harga DB.
3. `index.html` yang dilayani tidak punya kartu produk hardcode (grid diisi JS).
4. Jumlah kartu beranda = jumlah produk API (berubah kalau produk ditambah).
5. Nol regresi: `catalog`/`admin-ui`/`checkout-*` tetap hijau.
6. Nol dependency baru.

## Yang TIDAK diubah

- Rumus ongkir & tier (sudah satu sumber sejak 0013).
- Desain visual (kelas CSS sama; cuma sumber datanya).
- Konten marketing beranda (hero, FAQ, keunggulan, spesifikasi) — tetap.
- Pembayaran (belum, sesuai keputusan user).
