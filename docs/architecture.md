# Arsitektur — Atandra Textile Commerce

**Terakhir diperbarui:** 2026-09-30

---

## 1. Gambaran besar

```
                    Internet
                       │
                       ▼
        ┌──────────────────────────────┐
        │  Cloudflare (DNS + HTTPS)     │
        │  txt.invesbot.my.id           │
        └──────────────┬───────────────┘
                       │  Cloudflare Tunnel "invesbot-web"
                       ▼
             127.0.0.1:8787
                       │
        ┌──────────────┴───────────────┐
        │  systemd: atara-web           │
        │  node server/index.js         │
        │  (Express 5)                  │
        └──────────────┬───────────────┘
                       │
        ┌──────────────┴───────────────┐
        │  Express static               │
        │   ├── dist/   (build Vite)    │
        │   └── public/ (gambar)        │
        └──────────────┬───────────────┘
                       │
                       ▼
              data/atandra.sqlite
```

**Satu proses melayani dua hal:** API (`/api/*`) dan file statis (halaman HTML + gambar).
Tidak ada server frontend terpisah di production.

## 2. Lapisan

| Lapisan | Teknologi | Lokasi |
|---|---|---|
| Ingress | Cloudflare Tunnel | `/etc/cloudflared/invesbot-web.yml` (root-only) |
| Process manager | systemd | `/etc/systemd/system/atara-web.service` |
| Backend | Node.js + Express 5 | `server/index.js` |
| Auth | scrypt + salt + timingSafeEqual | `server/auth.js` |
| Database | SQLite (better-sqlite3-style helper) | `server/db.js` + `data/atandra.sqlite` |
| Schema | SQL | `server/schema.sql` |
| Provider (payment/shipping/notif) | Abstraksi manual | `server/services.js` |
| Frontend | HTML + JS vanilla (nol framework) | `*.html`, `store.js`, `account.js`, `admin-products.js`, `admin-orders.js` |
| Build | Vite (multi-page) | `vite.config.ts` |
| Style | CSS tunggal, design token di `:root` | `store.css` |

## 2b. URL publik

URL publik **bersih (tanpa `.html`)**. Tidak ada router halaman — pemetaan URL → file ada
di **satu tabel** `PAGES` di `server/index.js` (bagian bawah, sebelum `express.static`).
URL lama `.html` di-**301** ke URL bersih (query string dipertahankan), jadi bookmark lama
tetap hidup. Saat `npm run dev`, plugin `clean-urls-dev` di `vite.config.ts` melakukan
rewrite yang sama supaya dev tidak 404.

| URL | File |
|---|---|
| `/` | `index.html` |
| `/katalog` | `shop.html` |
| `/produk?slug=<slug>` | `product.html` |
| `/keranjang` | `checkout.html` |
| `/akun` | `account.html` |
| `/akun/pesanan` | `account-orders.html` |
| `/akun/pesanan/lihat?id=<no>` | `account-order.html` |
| `/admin` | `admin.html` |
| `/admin/pesanan` | `admin-orders.html` |
| `/admin/produk` | `admin-products.html` |

**Aturan:** kalau menambah halaman, daftarkan di **tiga** tempat — `PAGES` di
`server/index.js`, `PAGES` di `vite.config.ts` (untuk dev), dan `build.rollupOptions.input`
(untuk build). Detail: `plans/0004-clean-urls.md`.

## 3. Model data (ringkas)

```
categories ──< products ──< product_variants ──< inventory
                    │              │
                    │              └──< order_items >── orders
                    ├──< product_images
                    └──< price_tiers        colors ──< product_variants

customers ──< addresses
          ──< orders ──< payments
                    ──< shipments
users (role: customer|admin) ──< sessions
sample_requests ──> products
```

**Poin penting:**
- **Harga & stok ada di `product_variants`**, bukan di `products`. Produk = "Double Pique
  165", varian = "Double Pique 165 — Navy".
- **`order_items` menyimpan snapshot** (`product_name`, `variant_name`, `sku`,
  `unit_price`) — bukan referensi ke harga produk sekarang. Jadi riwayat order tetap utuh
  meski harga produk berubah. ✅
- **Stok dipisah:** `inventory.stock` (fisik) dan `inventory.reserved_stock` (dipesan tapi
  belum dibayar). Stok tersedia = `stock - reserved_stock`.
- **Archive, bukan delete:** `products.status IN ('active','draft','archived','out_of_stock')`.

## 4. Alur order

```
1. Pembeli isi checkout
2. POST /api/orders
   └── transaction:
       ├── cari/bikin customer
       ├── simpan address
       ├── validasi tiap varian (aktif + stok cukup)
       ├── hitung harga per tier kuantitas
       ├── INSERT orders + order_items
       ├── UPDATE inventory.reserved_stock += qty   ← reservasi
       ├── INSERT payments (status 'pending')
       └── INSERT shipments
3. Status awal: 'pending_payment'
4. Pembayaran dikonfirmasi (manual sekarang; gateway nanti via webhook)
   └── UPDATE payments.status='paid', orders.status='paid'
       └── stock -= qty, reserved_stock -= qty
5. Admin proses: processing → packed → shipped (isi resi) → completed
```

**Status order yang valid** (urut):
`pending_payment` → `paid` → `processing` → `packed` → `shipped` → `completed`
plus `cancelled` dan `refunded`.

## 5. Keamanan

| Kontrol | Implementasi |
|---|---|
| Hash password | `scrypt` + salt 16 byte + `timingSafeEqual` |
| SQL injection | **Prepared statement + parameter binding** di semua query |
| Sesi | Token 32 byte acak, cookie `HttpOnly` + `SameSite=Lax` + `Secure` (production), TTL 7 hari |
| Otorisasi | `requireAuth` + `requireRole('admin')`; endpoint akun di-scope ke `customer_id` |
| IDOR | `GET /api/orders/:id` — guest hanya lihat status, data pribadi hanya pemilik/admin |
| XSS | Helper `esc()` diterapkan ke semua `innerHTML` |
| Rate limit | 120 req/menit per IP; registrasi admin 5 percobaan/jam |
| Security headers | CSP, `X-Frame-Options: DENY`, `nosniff`, `Referrer-Policy`, `Permissions-Policy` |
| CORS | Whitelist `ALLOWED_ORIGINS` |
| Fail-fast | `seedAdmin` menolak password lemah di production (server tak start) |
| Mock payment | Mati otomatis kalau `NODE_ENV=production` |

## 6. Catatan operasional

- **Ubah frontend** → wajib `npm run build` (backend menyajikan `dist/`, bukan sumbernya).
- **Ubah backend** → cukup restart service.
- **Restart service** → butuh `nsenter` via `docker run --privileged --pid=host` (nol sudo).
- **Backup DB** → `cp data/atandra.sqlite <tujuan>` (tapi stop dulu prosesnya, kalau tidak
  dia menulis ulang).
- **Config tunnel itu dipakai bersama** dengan layanan lain — backup sebelum edit.
