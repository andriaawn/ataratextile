# Referensi API — Atandra Textile Commerce

**Terakhir diperbarui:** 2026-09-30
**Base URL (production):** `https://txt.invesbot.my.id/api`
**Base URL (lokal):** `http://localhost:8787/api`

Semua body request/response = JSON. Autentikasi pakai cookie `atandra_session`
(`HttpOnly`, dikirim otomatis oleh browser).

**Legenda akses:** 🌐 publik · 👤 butuh login · 🔒 admin saja

---

## Health

| Method | Path | Akses | Keterangan |
|---|---|---|---|
| GET | `/health` | 🌐 | `{ ok: true, service: 'atandra-commerce-api' }` |

## Auth

| Method | Path | Akses | Keterangan |
|---|---|---|---|
| POST | `/auth/register` | 🌐 | Daftar customer. Body: `name, email, password` (min 8), `phone?`, `company_name?` |
| POST | `/auth/login` | 🌐 | Body: `email, password` → set cookie sesi |
| POST | `/auth/logout` | 🌐 | Hapus sesi + cookie |
| GET | `/auth/me` | 👤 | Info user yang sedang login |
| POST | `/auth/admin-register` | 🌐 | Daftar admin. **Butuh `invite_key`** (dari `ADMIN_INVITE_KEY`). Rate limit 5/jam/IP. 503 kalau key belum dikonfigurasi |
| POST | `/auth/change-password` | 👤 | Ganti password sendiri. Body: `current_password, new_password` (min 12). Wajib buktikan password sekarang. **Semua sesi user digugurkan** → cookie dihapus. Rate limit 5 gagal/15 menit/IP. 204 sukses |

## Katalog (publik)

| Method | Path | Akses | Keterangan |
|---|---|---|---|
| GET | `/categories` | 🌐 | Semua kategori |
| GET | `/products` | 🌐 | Daftar produk aktif. Query: `q` (cari nama/SKU/material), `category` (slug), `gsm` (±15). Tiap produk bawa `available_stock, low_stock_threshold, low_stock` |
| GET | `/products/:slug` | 🌐 | Detail produk + `variants`, `tiers`, `images` |
| GET | `/shipping/quote` | 🌐 | Query: `quantity`, `city` → `{ method, cost, estimatedDays }` |

## Order (publik + pemilik)

| Method | Path | Akses | Keterangan |
|---|---|---|---|
| POST | `/orders` | 🌐 | Bikin order. Body: `{ customer:{name,email,phone?,company_name?}, address:{address,city,province?,district?,postal_code?}, items:[{variant_id,quantity}], notes? }` |
| GET | `/orders/:id` | 🌐/👤 | Cek status. Guest dapat info dasar; **data pribadi hanya pemilik/admin** |
| POST | `/orders/:id/mock-payment` | 🌐 | ⚠️ **Development saja** — mati otomatis di production |
| POST | `/samples` | 🌐 | Request sample. Body: `customer_name, email, phone, product_id, color, quantity?, address` |

## Akun customer

| Method | Path | Akses | Keterangan |
|---|---|---|---|
| GET | `/account/profile` | 👤 | Profil customer |
| PATCH | `/account/profile` | 👤 | Ubah `name, phone, company_name` |
| GET | `/account/addresses` | 👤 | Daftar alamat |
| POST | `/account/addresses` | 👤 | Tambah alamat (semua field wajib) |
| PATCH | `/account/addresses/:id` | 👤 | Ubah alamat (scoped ke customer) |
| DELETE | `/account/addresses/:id` | 👤 | Hapus alamat (scoped ke customer) |
| GET | `/account/orders` | 👤 | Riwayat order sendiri |
| GET | `/account/orders/:id` | 👤 | Detail order sendiri + resi |
| POST | `/account/orders/:id/reorder` | 👤 | Item yang bisa dipesan ulang (stok tersedia) |

## Admin

| Method | Path | Akses | Keterangan |
|---|---|---|---|
| GET | `/admin/dashboard` | 🔒 | Metrik: `sales, orders, pendingPayments, lowStock, samples` |
| GET | `/admin/orders` | 🔒 | Semua order + nama/email customer + status payment |
| PATCH | `/admin/orders/:id` | 🔒 | Ubah `status` + `tracking_number`. Status valid: `pending_payment, paid, processing, packed, shipped, completed, cancelled, refunded` |
| GET | `/admin/categories` | 🔒 | Kategori (termasuk non-aktif) |
| POST | `/admin/categories` | 🔒 | Body: `name, slug` |
| PATCH | `/admin/categories/:id` | 🔒 | Body: `name, slug` |
| GET | `/admin/colors` | 🔒 | Daftar warna |
| PATCH | `/admin/colors/:id` | 🔒 | Ubah `name, code`. Kode bentrok → 409, tidak ada → 404 |
| GET | `/admin/catalog` | 🔒 | Kategori & warna **+ `usage_count`** (jumlah produk/varian yang memakai) |
| DELETE | `/admin/categories/:id` | 🔒 | Hapus kategori. **409 kalau masih dipakai** produk (`usage_count` ikut dikirim), 404 kalau tidak ada |
| DELETE | `/admin/colors/:id` | 🔒 | Hapus warna. **409 kalau masih dipakai** varian, 404 kalau tidak ada |
| POST | `/admin/colors` | 🔒 | Body: `name, code` (code unik) |
| GET | `/admin/products` | 🔒 | Semua produk (termasuk draft/archived) |
| POST | `/admin/products` | 🔒 | Buat produk. Field wajib: `category_id, name, slug, sku, description, material, construction, gsm, width, weight_per_yard, recommended_usage`. Opsional: `moq` (default 1, min 1), `sample_available` (default 1), `featured` (default 0), `bestseller` (default 0), `status` (default draft), `image`. Field kurang → **400** dengan pesan menyebut nama field + array `missing` |
| PATCH | `/admin/products/:id` | 🔒 | Ubah field produk |
| DELETE | `/admin/products/:id` | 🔒 | **Soft delete** → `status='archived'` (riwayat tetap utuh) |
| GET | `/admin/products/:id/variants` | 🔒 | Varian produk + stok + `low_stock_threshold` + **`low_stock`** (dihitung server) |
| POST | `/admin/products/:id/variants` | 🔒 | Body: `color_id, sku, price, wholesale_price, stock?, low_stock_threshold?` |
| PATCH | `/admin/variants/:id` | 🔒 | Ubah `sku, price, wholesale_price, active` |
| PATCH | `/admin/inventory/:variantId` | 🔒 | Body: `stock` (≥ reserved), `low_stock_threshold?` (≥ 0, integer). Kirim `stock` saja **tidak** mengubah ambang |
| POST | `/admin/variants/bulk-price` | 🔒 | Ubah harga banyak varian sekaligus. Body: `{ variant_ids:[], mode:'set'\|'percent'\|'amount', value, field?:'price'\|'wholesale_price'\|'both', dry_run? }`. **Atomik**: satu harga jadi ≤ 0 → 400 & nol yang berubah. `dry_run:true` → hanya pratinjau, tidak menulis |
| PUT | `/admin/products/:id/pricing` | 🔒 | Ganti tier harga. Body: `{ tiers:[{min_quantity, max_quantity?, price, label?}] }` |
| POST | `/admin/uploads` | 🔒 | Upload gambar. Body = **file mentah** (bukan multipart), `Content-Type: image/*`. Validasi magic bytes: JPEG/PNG/WebP saja. Maks 8 MB. Balikin `{name, url, bytes, originalBytes}`. Nama file = hash isi (idempoten) |
| GET | `/admin/uploads` | 🔒 | Daftar file di `public/uploads/` |
| DELETE | `/admin/uploads/:name` | 🔒 | Hapus file. `:name` wajib `[a-f0-9]{16,64}\.(jpg\|png\|webp)` — path traversal ditolak 400 |
| GET | `/admin/products/:id/images` | 🔒 | Galeri produk, urut `sort_order` |
| POST | `/admin/products/:id/images` | 🔒 | Tambah gambar. Body: `{url, alt?}`. `url` wajib `/uploads/<hash>.<ext>` atau `/img/<file>` — URL luar ditolak 400 |
| DELETE | `/admin/products/:id/images/:imageId` | 🔒 | Hapus dari galeri. File fisik ikut terhapus **hanya kalau tidak dipakai produk lain** |
| PATCH | `/admin/products/:id/images/:imageId/primary` | 🔒 | Jadikan gambar utama (`sort_order=0`), sisanya digeser |

---

## Contoh

**Bikin order:**
```bash
curl -X POST https://txt.invesbot.my.id/api/orders \
  -H 'Content-Type: application/json' \
  -d '{
    "customer": { "name": "Budi", "email": "budi@example.com", "phone": "0812..." },
    "address":  { "address": "Jl. Contoh 1", "city": "Bandung", "province": "Jawa Barat" },
    "items":    [{ "variant_id": 1, "quantity": 5 }]
  }'
```

**Ubah status order (admin):**
```bash
curl -X PATCH https://txt.invesbot.my.id/api/admin/orders/1 \
  -H 'Content-Type: application/json' \
  -b "atandra_session=<token>" \
  -d '{ "status": "shipped", "tracking_number": "JNE123456789" }'
```

## Kode error

| Kode | Arti |
|---|---|
| 400 | Input tidak valid / stok tidak cukup |
| 401 | Belum login |
| 403 | Login tapi bukan admin / invite key salah |
| 404 | Tidak ditemukan (atau endpoint sengaja disembunyikan) |
| 409 | Konflik — email/SKU/slug duplikat |
| 429 | Kena rate limit |
| 503 | Fitur belum dikonfigurasi (mis. `ADMIN_INVITE_KEY` kosong) |
