# Plan 0004 — URL bersih (hapus `.html` dari URL)

**Tanggal:** 2026-09-30
**Status:** ✅ SELESAI & LIVE (2026-09-30) — approved via "gasss bro"
**Bukti:** `tests/admin-orders.test.sh` 16/16 · negative control GAGAL 4/12 saat route dimatikan
**Log:** `logs/2026-09-30_url-bersih.md` (lokal)
**Owner:** andriaawn
**Kontrak:** `AGENTS.md` (alur kerja) · `docs/architecture.md`

## Masalah

Server **tidak punya route halaman** — semua halaman dilayani `express.static`:

```js
app.use(express.static(path.join(here, '..', 'dist')));   // baris 173
app.use(express.static(path.join(here, '..', 'public'))); // baris 174
```

Akibatnya nama URL = nama file. `/admin-orders.html`, `/shop.html`, dst.
`/` sudah bersih **hanya kebetulan** (express.static otomatis menyajikan `index.html`
untuk folder) → app jadi separuh bersih, separuh `.html`. Tidak konsisten, dan membocorkan
implementasi (kelihatan situs statis). WooCommerce/Shopify semua pakai `/admin/orders`.

**Bukan bug** — nol dampak fungsi/keamanan. Murni kebersihan + konsistensi.

## Keputusan

1. **Opsi A — tabel route tipis di Express + 301 dari URL lama.** Nol ubah pipeline build
   (tetap MPA Vite). Lebih eksplisit & mudah dibaca daripada mengubah struktur output Vite.
2. **Bahasa Indonesia** (pilihan user) — konsisten dengan UI.
3. **Scope: semua halaman** (admin + toko depan) — supaya konsisten total.
4. **URL lama `.html` di-301** ke URL baru (bukan 404) → bookmark/link lama tetap hidup.
5. **Query string dipertahankan** saat redirect (`?slug=`, `?id=`).
6. **Detail tetap pakai query param** (`/produk?slug=x`) — YAGNI, tidak perlu parsing path.
7. **Dev mode (Vite) ikut didukung** lewat plugin middleware kecil — supaya `npm run dev`
   tidak 404 saat mengklik URL bersih.

## Peta URL

| File | URL baru | Catatan |
|---|---|---|
| `index.html` | `/` | sudah bersih |
| `shop.html` | `/katalog` | daftar kain |
| `product.html` | `/produk?slug=<slug>` | `/produk` tanpa slug → redirect `/katalog` |
| `checkout.html` | `/keranjang` | |
| `account.html` | `/akun` | |
| `account-orders.html` | `/akun/pesanan` | |
| `account-order.html` | `/akun/pesanan/lihat?id=<no>` | |
| `admin.html` | `/admin` | |
| `admin-orders.html` | `/admin/pesanan` | |
| `admin-products.html` | `/admin/produk` | |

Redirect 301: `/index.html→/`, `/shop.html→/katalog`, `/product.html→/produk`,
`/checkout.html→/keranjang`, `/account.html→/akun`, `/account-orders.html→/akun/pesanan`,
`/account-order.html→/akun/pesanan/lihat`, `/admin.html→/admin`,
`/admin-orders.html→/admin/pesanan`, `/admin-products.html→/admin/produk`.

## File yang berubah

| File | Perubahan |
|---|---|
| `server/index.js` | tabel `PAGES` + `LEGACY`, redirect 301, route halaman — **sebelum** `express.static` |
| `vite.config.ts` | plugin `clean-urls-dev` (rewrite saat dev) |
| `index.html`, `shop.html`, `product.html`, `checkout.html`, `account.html`, `account-orders.html`, `account-order.html`, `admin.html`, `admin-orders.html`, `admin-products.html` | update semua link |
| `store.js`, `account.js`, `admin-products.js` | update link + **hapus hack mati** (`store.js:20`, cek `'Products'` yang sudah tidak ada) |
| `tests/admin-orders.test.sh` | + cek URL bersih 200, `.html` 301, query dipertahankan |
| `README.md`, `AGENTS.md`, `docs/architecture.md`, `HANDOFF.md` | update referensi URL |

## Acceptance criteria

- [ ] Semua URL bersih → **200**
- [ ] Semua URL `.html` lama → **301** ke URL baru
- [ ] Redirect mempertahankan query (`?slug=`, `?id=`)
- [ ] Nol link `.html` tersisa di source yang di-commit (kecuali `vite.config.ts` path file)
- [ ] `npm run dev` (Vite) juga melayani URL bersih
- [ ] `tests/admin-orders.test.sh` lulus (termasuk cek URL baru)
- [ ] `tests/security.test.sh` tetap 10/10 (nol regresi)
- [ ] Live: semua halaman 200, `.html` 301, login admin & ubah status masih jalan

## Out of scope

- Path param cantik (`/produk/<slug>`) — tetap query param (YAGNI).
- Pindah ke SPA framework / router client-side.
- Rename file fisik di disk (tetap `admin-orders.html` — cuma URL publiknya yang bersih).
