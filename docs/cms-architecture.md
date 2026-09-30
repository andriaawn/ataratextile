# Arsitektur CMS — Admin Atandra

**Terakhir diperbarui:** 2026-09-30
**Status:** rancangan — jadi acuan pembangunan halaman admin

> Menjawab: CMS e-commerce yang lazim itu **terdiri dari modul apa saja**, dan mana yang
> kita butuh. Referensi: cara kerja admin panel CS-Cart, WooCommerce, Medusa, Saleor,
> Bagisto, dan Polaris (Shopify) — disaring jadi yang relevan untuk satu toko kecil.

---

## 1. Model umum CMS e-commerce

Semua platform e-commerce (dari WooCommerce sampai Medusa) bermuara ke **7 modul** yang
sama. Yang beda cuma seberapa dalam masing-masing:

| # | Modul | Isi | Sudah ada di backend kita? |
|---|---|---|---|
| 1 | **Dashboard** | Ringkasan: penjualan, order masuk, stok menipis | ✅ `GET /api/admin/dashboard` |
| 2 | **Katalog** | Produk, varian, kategori, warna, gambar, harga bertingkat | ✅ 20 endpoint |
| 3 | **Pesanan** | Daftar order, detail, ubah status, resi, catatan | ✅ endpoint ada, **UI belum** |
| 4 | **Pelanggan** | Daftar pelanggan, riwayat, alamat | ⚠️ data ada, endpoint khusus belum |
| 5 | **Konten** | Hero, banner, halaman statis, kontak | ❌ belum ada |
| 6 | **Pengaturan** | Toko, pengiriman, pembayaran, pajak, user admin | ⚠️ sebagian di `.env` |
| 7 | **Laporan** | Penjualan, produk terlaris, ekspor | ❌ belum ada |

**Kesimpulan:** backend kita **sudah menutup modul 1–3** (yang paling penting). Yang
kurang adalah **lapisan UI** untuk modul 3, lalu modul 4–7.

---

## 2. Struktur menu (6 item, maksimum yang sehat)

```
▸ Dashboard        /admin.html              ringkasan harian
▸ Pesanan ①        /admin-orders.html       kerja utama sehari-hari   ← FASE 1
▸ Produk           /admin-products.html     katalog (sudah ada, diperbaiki di FASE 2)
▸ Pelanggan        /admin-customers.html    FASE 4
▸ Konten           /admin-content.html      FASE 3
▸ Pengaturan       /admin-settings.html     FASE 5
```

Badge angka di sidebar = jumlah yang butuh perhatian (order pending). Ini yang bikin
operator tahu "ada kerjaan" tanpa buka halaman.

---

## 3. Layar per modul

### 3.1 Dashboard (`admin.html`) — ✅ ada, perlu dirapikan

| Blok | Isi |
|---|---|
| KPI | Penjualan (periode), Order masuk, Menunggu bayar, Stok menipis |
| Antrean | "5 pesanan perlu diproses hari ini" → link ke daftar terfilter |
| Grafik | Penjualan 7/30 hari (FASE 4) |
| Peringatan | Produk stok ≤ threshold, sample request baru |

**Aturan KPI:** setiap angka **wajib ada pembandingnya** (vs periode sebelumnya). Angka
telanjang tanpa konteks tidak menjawab pertanyaan apa pun.

### 3.2 Pesanan (`admin-orders.html`) — 🔴 FASE 1, prioritas utama

**Pertanyaan yang harus dijawab layar ini:** *"Pesanan mana yang perlu gw kerjakan
sekarang?"*

| Bagian | Isi |
|---|---|
| **KPI strip** | Menunggu bayar · Perlu dikemas · Dikirim · Selesai (bulan ini) |
| **Filter** | Status (tab/chip), rentang tanggal, search (no. order / nama / email) |
| **Tabel** | No. order · Tanggal · Pelanggan · Item · Total · Status · Aksi |
| **Detail** (panel/drawer) | Item + harga, alamat kirim, data pembeli, status pembayaran, resi |
| **Aksi baris** | Lihat detail · Ubah status · Isi resi |
| **Aksi massal** | Centang beberapa → ubah status massal, ekspor CSV |
| **Catatan internal** | Field catatan per order (tidak terlihat pelanggan) |

**Aturan penting (dari riset):**
- **Order itu immutable.** Setelah dibuat, item & harga **tidak boleh diubah**. Kalau
  pelanggan mau ubah → batal + order baru. (Backend kita sudah benar: `order_items`
  menyimpan snapshot `unit_price`.)
- **Transisi status divalidasi.** Dropdown hanya menampilkan transisi sah dari status
  sekarang. Server tetap memvalidasi (jangan percaya UI).
- **Aksi massal wajib.** Mengubah 20 order satu-satu itu neraka.
- **Filter + search wajib.** Tanpa ini, 100 order mustahil dikelola.
- **Empty state jelas.** "Belum ada pesanan."

### 3.3 Produk (`admin-products.html`) — ⚠️ ada, diperbaiki di FASE 2

Sudah punya: daftar produk, form produk, editor varian, editor harga bertingkat, stok.

Yang perlu ditambah:

| # | Tambahan | Kenapa |
|---|---|---|
| 1 | **Upload gambar** (sekarang tempel URL) | Tanpa ini, nambah produk = cari URL manual |
| 2 | **Bulk harga** — set harga semua varian sekaligus | 44 varian satu-satu = neraka |
| 3 | **Badge stok menipis** di tabel | Lihat masalah tanpa buka tiap produk |
| 4 | **Kelola kategori & warna** (sekarang 1 kategori, 4 warna) | Katalog tak bisa tumbuh |
| 5 | Modal konfirmasi archive | Cegah salah klik |
| 6 | Duplikat produk | Bikin varian dari yang mirip |

**Prinsip:** harga & stok di **varian**, bukan produk. Archive, jangan hapus.

### 3.4 Pelanggan (`admin-customers.html`) — FASE 4

| Isi |
|---|
| Tabel: nama · email · telepon · jumlah order · total belanja · terakhir order |
| Detail: profil, alamat tersimpan, riwayat order |
| Ekspor CSV |

Butuh endpoint baru: `GET /api/admin/customers`.

### 3.5 Konten (`admin-content.html`) — FASE 3

Field yang perlu bisa diedit (simpan di tabel `site_content` key-value, bukan hardcode):

| Field | Contoh |
|---|---|
| `hero_title`, `hero_subtitle` | judul beranda |
| `hero_cta_text`, `hero_cta_url` | tombol beranda |
| `about_text` | section tentang |
| `contact_whatsapp` | **nomor WA di sini** (sesuai rencana — bukan di CTA) |
| `contact_email`, `contact_address` | kontak |
| `social_*` | link sosial media |
| `banner_*` | banner promo (opsional) |

Plus halaman statis: Tentang, Kebijakan Privasi, Syarat & Ketentuan, Cara Order.

**Aturan:** ada **preview** sebelum simpan. Jangan biarkan operator menebak tampilannya.

### 3.6 Pengaturan (`admin-settings.html`) — FASE 5

| Tab | Isi |
|---|---|
| Toko | nama, alamat, kontak |
| Pengiriman | tarif, kurir, estimasi |
| Pembayaran | provider, status |
| Pajak | tarif, aktif/tidak |
| Pengguna admin | daftar admin, peran, nonaktifkan |
| Audit log | siapa mengubah apa kapan |

---

## 4. Pola kerja yang dipakai ulang di semua halaman

Semua halaman admin mengikuti pola yang sama — biar operator cuma belajar sekali:

```
1. Page header    → judul + deskripsi + aksi utama (kanan)
2. KPI strip      → 3-4 angka kunci dengan pembanding
3. Filter bar     → search + dropdown + tanggal + reset
4. Tabel utama    → sortable, hover, aksi per baris
5. Bulk bar       → muncul saat ada baris dicentang
6. Paginasi       → 25/50/100 per halaman
7. Empty state    → kalau nol data, tampilkan ajakan aksi
```

Detail (order/produk/pelanggan) dibuka sebagai **drawer/panel samping** atau halaman
terpisah — bukan modal besar (modal besar di mobile itu menyiksa).

---

## 5. Yang sengaja TIDAK dibangun

| Item | Alasan |
|---|---|
| Editor visual drag-and-drop | Rapuh, HTML jadi tak terawat, nggak sepadan untuk katalog sederhana |
| "Wall of charts" | Grafik hanya kalau menjawab pertanyaan; bukan dekorasi |
| Multi-bahasa | Semua pelanggan orang Indonesia (lihat `BACKLOG.md`) |
| Peran/izin rumit | 1–2 admin saja; cukup owner vs staff (FASE 5) |
| Marketplace sync | Sinkronisasi dua arah = risiko oversell; tunda (`BACKLOG.md`) |
| Bikin order manual dari admin | Fitur lanjutan (Bagisto punya); belum perlu |

---

## 6. Urutan pembangunan (mengikuti `plans/ROADMAP.md`)

| Fase | Modul | Kenapa di urutan ini |
|---|---|---|
| **1** | Pesanan | Order = uang masuk. Tanpa ini, pesanan tak bisa diproses |
| **2** | Produk (perbaikan) | Tanpa upload gambar, tambah produk nggak praktis |
| **3** | Konten | Taruh WA + edit tampilan tanpa sentuh kode |
| **4** | Pelanggan + Laporan | Butuh data dulu (>10 pelanggan, >50 order) |
| **5** | Pengaturan + Polish | Terakhir; butuh multi-admin dulu |
| **⏭** | Pembayaran | Paling akhir (keputusan user) |
