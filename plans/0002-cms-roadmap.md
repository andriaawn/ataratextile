# Plan 0002 — CMS & Commerce (roadmap pengerjaan)

**Tanggal:** 2026-09-30
**Status:** 📋 backlog — belum mulai, menunggu pilihan user
**Owner:** andriaawn
**Turunan dari:** `logs/2026-09-30_plan-cms.md` (dipindah ke sini sesuai konvensi)
**Dokumen pendukung:**
- [`docs/cms-architecture.md`](../docs/cms-architecture.md) — model CMS (7 modul, layar per modul)
- [`docs/design-system.md`](../docs/design-system.md) — kontrak desain (layout, tipografi, warna, komponen)

---

## Goal

Bangun lapisan **admin/CMS** di atas backend yang sudah ada, supaya produk & order bisa
dikelola dari UI — tanpa mengubah backend yang sudah matang dan aman.

---

## Temuan audit (2026-09-30)

### ✅ Yang sudah bagus — JANGAN diutak-atik

| Lapisan | Kondisi |
|---|---|
| Backend API | **34 endpoint** — CRUD produk, varian, kategori, warna, inventory, order, pricing |
| Keamanan | scrypt+salt+timingSafeEqual, prepared statements, CORS whitelist, rate limit, CSP, IDOR fix, XSS fix |
| Database | SQLite — products, product_variants, categories, colors, orders, order_items, customers, addresses, users, sessions, inventory, price_tiers, payments, shipments, sample_requests |
| Frontend toko | 9 halaman, design language konsisten |
| Deploy | Cloudflare Tunnel + systemd, auto-start, HTTPS |

**Kesimpulan: backend sudah matang. Yang kurang cuma LAPISAN ADMIN di frontend.**

### ❌ Masalah

| # | Masalah | Dampak | Prioritas |
|---|---|---|---|
| B1 | Sidebar admin `Orders → /checkout.html` | Klik Orders malah ke checkout customer | 🔴 |
| B2 | Sidebar admin `Content → /` | Klik Content malah ke beranda publik | 🔴 |
| B3 | **Tidak ada halaman admin untuk kelola order** | Admin nggak bisa proses pesanan | 🔴 |
| B4 | Tidak ada upload gambar (form cuma field `image` teks) | Harus tempel URL manual | 🟠 |
| B5 | Kategori cuma 1, warna cuma 4 | Katalog nggak fleksibel | 🟠 |
| B6 | Harga placeholder `825000 + gsm*1000` | Harga nggak realistis | 🟡 (ditunda user) |
| B7 | Tidak ada halaman kelola customer | Susah lihat pelanggan | 🟡 |
| B8 | Tidak ada editor konten beranda | Ganti teks harus edit kode | 🟡 |
| B9 | Tidak ada audit log aksi admin | Nggak tahu siapa ubah apa | 🟢 |
| B10 | Tidak ada grafik penjualan | Cuma angka mentah | 🟢 |

---

## Decisions

- **Lanjutkan backend yang ada**, bangun UI admin di atasnya.
- **Rejected:** WordPress/WooCommerce — berat, butuh PHP+MySQL, security risk, migrasi total.
- **Rejected:** Shopify/Medusa/Saleor — bayar bulanan / berat / overkill.
- **Rejected:** Strapi/Directus — harus ganti backend & DB, belajar sistem baru.
- **Harga dibiarkan placeholder** (keputusan user) sampai CMS selesai.

## Best practice yang jadi acuan

**Produk:**
1. Harga & stok di **varian**, bukan produk ✅ (sudah benar di schema)
2. **Archive, jangan hard delete** ✅ (sudah ada)
3. Slug unik & stabil; stok = angka + `low_stock_threshold`
4. **Bulk edit harga** — 44 varian kalau satu-satu = neraka

**Order:**
1. Status berurutan: `pending_payment → paid → processing → packed → shipped → completed`
   (+ `cancelled` / `refunded`). Validasi transisi.
2. **Order immutable** — item & harga tak boleh diubah setelah dibuat (audit trail)
3. **Snapshot harga** di `order_items.unit_price` ✅ (sudah benar)
4. Aksi wajib: lihat detail, ubah status, **input resi**, catatan internal, export CSV
5. Filter & search: status, tanggal, nama, nomor order

**UX admin:**
1. Sidebar + konten (maks 7 menu)
2. Setiap aksi beri feedback ("Produk disimpan ✅")
3. Konfirmasi modal untuk aksi destruktif
4. Tabel sortable + paginasi kalau > 25 baris
5. Mobile-friendly

**Konten:**
1. Simpan di tabel key-value, bukan hardcode di HTML
2. Field yang perlu diedit: hero, banner, tentang, kontak (WA/email/alamat), sosial media

---

## File / task breakdown (per fase)

### 🔴 FASE 1 — Admin Order (paling penting)
- `admin-orders.html` (baru) — tabel order + filter + detail + ubah status + resi + catatan
- `admin-orders.js` (baru)
- `admin.html` — fix sidebar `Orders → /admin-orders.html`; badge order pending
- `vite.config.ts` — daftarkan `adminOrders` sebagai entry
- `store.css` — style modal konfirmasi (kalau belum ada)

### 🟠 FASE 2 — Product CMS
- `server/index.js` — endpoint `POST /api/admin/upload` (multipart → `public/uploads/`)
- `admin-products.html` + `.js` — upload gambar + preview, bulk harga, badge low-stock
- Halaman/panel kelola kategori & warna
- `server/index.js` — endpoint CRUD kategori/warna yang belum ada (DELETE)

### 🟡 FASE 3 — Konten
- `server/schema.sql` — tabel `site_content` (key TEXT PK, value TEXT)
- `server/index.js` — `GET /api/content`, `PUT /api/admin/content/:key`
- `admin-content.html` + `.js`
- `index.html` — baca konten dari API (fallback ke teks sekarang)
- **Taruh WA di halaman kontak** (sesuai rencana user)

### 🟡 FASE 4 — Customer & Laporan
- `admin-customers.html` + `.js`
- `admin.html` — grafik penjualan 7/30 hari
- Endpoint export CSV order

### 🟢 FASE 5 — Polish
- Audit log, peran admin, notifikasi otomatis, dark mode

### ⏭️ Terakhir — Pembayaran
- Pilih gateway (Midtrans paling populer di ID)
- Webhook + verifikasi signature (jangan percaya status dari frontend)
- Butuh rekening bisnis + KTP/NPWP

---

## Acceptance criteria (Fase 1)

- [ ] `admin-orders.html` menampilkan order dari `GET /api/admin/orders`
- [ ] Filter status + search berfungsi
- [ ] Detail order menampilkan item + alamat + pembeli + total
- [ ] Ubah status via `PATCH /api/admin/orders/:id`, transisi divalidasi
- [ ] Input resi tersimpan
- [ ] Sidebar `Orders` mengarah ke halaman yang benar
- [ ] Dites dengan order nyata (bukan cuma "harusnya jalan")
- [ ] Nol regresi: `tests/security.test.sh` tetap lulus

---

## Open questions

1. Mulai dari Fase 1 (Admin Order)?
2. Upload gambar: simpan di server (`public/uploads/`) atau Cloudinary?
3. Preferensi tampilan admin?

## Out of scope

- Ganti backend / framework.
- Ganti harga (ditunda user).
- Integrasi pembayaran (paling akhir).
- Pindah ke CMS jadi (lihat "Ditolak" di `ROADMAP.md`).
