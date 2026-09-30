# Plan 0003 — Fase 1: Admin Order + perbaikan kontras `--rust`

**Tanggal:** 2026-09-30
**Status:** ✅ SELESAI & LIVE (2026-09-30)
**Owner:** andriaawn
**Turunan:** `plans/0002-cms-roadmap.md` (Fase 1)
**Kontrak desain:** `docs/design-system.md` · **Model CMS:** `docs/cms-architecture.md`
**Bukti:** `tests/admin-orders.test.sh` 12/12 · log: `logs/2026-09-30_fase1-admin-order.md` (lokal)

---

## Goal

Dua hal dalam satu fase:

1. **Halaman admin order** — admin bisa melihat & memproses pesanan (sekarang pesanan masuk
   tak bisa ditindaklanjuti dari UI).
2. **Perbaiki `--rust` yang gagal kontras WCAG AA** (4.14 di paper, 3.71 di cream) → ganti
   dengan `#a8562f` (5.12 / 4.59).

---

## Decisions

- **Halaman baru terpisah** (`admin-orders.html`), bukan modal di dashboard. Alasan: tabel
  order butuh ruang; dashboard tetap ringkas.
- **Detail order = panel samping (drawer)**, bukan modal besar. Alasan: modal besar di layar
  360px itu menyiksa; drawer bisa dibaca sambil tabel tetap terlihat.
- **Ubah status dari tabel langsung** (dropdown per baris) — 2 klik, bukan 3. Ini yang
  paling sering dilakukan.
- **Rejected:** ubah status massal di Fase 1 — belum perlu (nol order), tunda ke Fase 4.
- **Rejected:** ekspor CSV di Fase 1 — tunda (lihat `BACKLOG.md`).
- **Rejected:** grafik penjualan — itu Fase 4.
- **Perbaikan `--rust`** dilakukan lewat token, bukan cari-ganti hex. Alasan: satu titik
  ubah, dan konsisten dengan design system.
- **`--gold` tetap** (7.26:1 di ink, lolos) — jangan diutak-atik.

---

## File / task breakdown

### A. Perbaikan kontras (kecil, mandiri)

- `store.css` — `:root`:
  - `--rust: #b9653b` → **`#a8562f`**
  - `--muted: #687777` → **`#5c6a6a`** (4.12 → 4.97 di cream)
  - tambah token baru yang dibutuhkan admin (surface, border, status) sesuai
    `docs/design-system.md` §4

### B. Halaman admin order (baru)

- `admin-orders.html` — kerangka: sidebar + topbar + KPI strip + filter + tabel + drawer
- `admin-orders.js` — logika:
  - `GET /api/admin/orders` → render tabel
  - filter status + search (client-side, data sudah di tangan)
  - `GET /api/orders/:id` (admin) → isi drawer detail
  - `PATCH /api/admin/orders/:id` → ubah status + resi
  - toast feedback tiap aksi
  - empty state + loading skeleton
- `vite.config.ts` — daftarkan `adminOrders` sebagai entry build

### C. Rapikan yang sudah ada

- `admin.html` — sidebar `Orders → /admin-orders.html`; `Content → /admin-content.html`
  (placeholder sampai Fase 3); tambah item **Pelanggan** & **Pengaturan**? → **TIDAK**,
  cukup yang halamannya sudah ada (hindari link ke halaman yang belum dibangun)
- `admin-products.html` — sidebar `Orders → /admin-orders.html` (sekarang ke `admin.html#orders`)
- `store.js` — `loadAdminDashboard()`: baris order di dashboard di-link ke
  `/admin-orders.html?id=...`
- `store.css` — tambah style komponen admin: badge status, drawer, filter bar, toast,
  skeleton, empty state (sesuai design system §6)

### D. Sidebar konsisten di 3 halaman

Sekarang sidebar beda-beda isinya di tiap halaman (`admin.html` vs `admin-products.html`).
Samakan jadi satu daftar: Dashboard · Pesanan · Produk (+ yang sudah ada).

---

## Acceptance criteria

- [ ] Halaman order memuat data dari `GET /api/admin/orders`
- [ ] Filter status & search berfungsi (dites dengan data nyata)
- [ ] Klik baris → drawer detail: item, alamat, pembeli, total, status bayar, resi
- [ ] Ubah status tersimpan (`PATCH`) dan tabel ikut ter-update tanpa reload
- [ ] Input resi tersimpan & tampil
- [ ] Transisi status divalidasi: dropdown hanya menampilkan transisi sah
- [ ] Aksi destruktif (batal/refund) pakai modal konfirmasi
- [ ] Setiap aksi memunculkan toast
- [ ] Ada empty state & loading skeleton
- [ ] Sidebar `Pesanan` di ketiga halaman admin mengarah ke halaman yang benar
- [ ] `--rust` baru terukur ≥4.5:1 di paper **dan** cream (hitung ulang, bukan asumsi)
- [ ] Nol regresi: `tests/security.test.sh` tetap lulus
- [ ] Halaman dites **di layar 360px** (bukan cuma desktop)
- [ ] Nol error di console browser

---

## Test yang akan gw tulis (bukti, bukan keyakinan)

`tests/admin-orders.test.sh` — pola sama seperti `security.test.sh`:

1. Guest tanpa login → `GET /api/admin/orders` harus **401**
2. Login admin → `GET /api/admin/orders` → **200** + bentuk data benar
3. `PATCH` status tidak valid (mis. `"dikirim"`) → **400**
4. `PATCH` status valid (`paid` → `processing`) → **200**, cek tersimpan di DB
5. `PATCH` dengan resi → tersimpan, `GET /api/orders/:id` menampilkannya
6. **Buktikan test bisa gagal**: jalankan terhadap endpoint yang salah → harus FAIL

Plus **kontras dihitung ulang** dengan skrip (fungsi luminansi WCAG), bukan dikira.

---

## Open questions

1. **Nama menu**: "Pesanan" (Indonesia) atau "Orders" (Inggris)? Sidebar sekarang campur
   ("Dashboard", "Products", "Orders", "Content"). Usul: **seragamkan Indonesia** —
   Dashboard · Pesanan · Produk. Setuju?
2. **Perbaikan `--rust`** — ubah langsung di `store.css` (berlaku toko + admin), atau bikin
   token terpisah? Usul: **ubah langsung** (satu sumber, dan `#a8562f` masih kerabat dekat
   `#b9653b` — nuansa brand tidak berubah).
3. Order test: boleh gw bikin 2-3 order contoh di DB untuk menguji tampilan, lalu **hapus
   lagi** setelah selesai? (DB produksi, jadi gw bersihkan seperti kemarin.)

---

## Out of scope

- Ubah status massal, ekspor CSV, grafik penjualan (Fase 4)
- Upload gambar, bulk harga, kelola kategori/warna (Fase 2)
- Editor konten / taruh WA (Fase 3)
- Pembayaran (paling akhir)
- Dark mode (ditunda — `docs/design-system.md` §9)

---

<!--
Kalau approve: ubah Status → "✅ approved <tanggal>" dan kerjakan.
Selesai: log di logs/YYYY-MM-DD_fase1-admin-order.md
-->
