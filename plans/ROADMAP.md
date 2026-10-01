# Roadmap — apa yang tersisa

**Updated:** 2026-10-01
**Status:** Live di https://txt.invesbot.my.id · Fase 1 (admin Order) ✅ · URL bersih ✅ · UI/UX CMS ✅ · **Fase 2 SELESAI** (2A upload gambar ✅ · 2B bulk harga ✅ · 2C kategori & warna ✅ · 2D badge stok menipis ✅ · 2E halaman Produk jadi tab ✅) · **Responsif admin ✅ (0007)** · **Ganti password sendiri ✅ (0008)** · **Tutup panel admin sebelum login ✅ (0009)** · **CMS nyaman di HP ✅ (0010)** · **CMS siap terima produk ✅ (0012)** · Fase 3 berikutnya

> Satu sumber kebenaran untuk "apa yang belum dikerjakan". Setiap item menunjuk ke
> detailnya. Jaga tetap akurat — roadmap basi itu menyesatkan.

---

## Selesai (jangan dikerjakan ulang)

| Area | Bukti |
|---|---|
| Rewrite repo: hapus DB berisi data pribadi + `dist/` dari history | commit `d66f076`, diverifikasi dari clone fresh |
| Tutup 5 kerentanan (IDOR, admin takeover, mock-payment, login admin, XSS) | commit `a7bee63`, `tests/security.test.sh` (lama 2/10 → baru 10/10) |
| Hapus nomor WA dari frontend, arahkan ke belanja di website | commit `a7bee63` |
| DB bersih (0 order, 0 customer) + katalog 11 produk / 44 varian | diverifikasi 2026-09-30 |
| Deploy live via Cloudflare Tunnel + systemd `atara-web` | `logs/2026-09-30_deploy-live.md` |
| Akun admin (login terverifikasi via domain live) | `logs/2026-09-30_deploy-live.md` |
| Adopsi framework (AGENTS.md, HANDOFF.md, plans/, docs/) | `plans/0001-adopt-framework.md` |
| **Fase 1: halaman admin Order** (tabel, filter, drawer, ubah status, resi) | commit `fase1`, `tests/admin-orders.test.sh` 12/12 |
| **Fix sidebar admin** (`Orders → /admin-orders.html`, `Content → /` dihapus) | commit `fase1` |
| **Kontras `--rust` & `--muted`** (WCAG AA) | `docs/design-system.md` §4, terukur 5.12/4.59 & 5.55/4.97 |
| **URL bersih tanpa `.html`** (`/katalog`, `/admin/pesanan`, …) + 301 dari URL lama | `plans/0004-clean-urls.md`, `tests/admin-orders.test.sh` 16/16 |
| **Rapikan UI/UX CMS** (fokus keyboard, anti-kedip, dashboard & produk diseragamkan, badge status produk) | `plans/0005-ui-ux-rapi.md`, `tests/admin-ui.test.sh` 17/17 |

---

## Tersisa — per prioritas

### P1 — sebelum ada pembeli nyata

| # | Item | Effort | Kenapa penting | Trigger |
|---|---|---|---|---|
| 1 | ~~Halaman admin Order~~ | M | ✅ **SELESAI** 2026-09-30 | — |
| 2 | ~~Fix sidebar admin~~ | S | ✅ **SELESAI** (sekalian seragamkan menu) | — |
| 3 | ~~Upload gambar produk~~ | M | ✅ **SELESAI** (2A) | — |
| 3b | ~~Form "Buat produk" selalu gagal 400~~ | XS | ✅ **SELESAI** (0012) — `recommended_usage` hilang dari form | — |
| 3c | ~~5 field produk tak bisa diisi (moq/featured/sample/bestseller)~~ | S | ✅ **SELESAI** (0012) | — |
| 4 | **Harga asli** (sekarang placeholder `825000 + gsm*1000`) | S | Harga palsu terlihat pembeli | **user siapkan daftar harga** |
| 5 | **Sinkronkan `payments.status`** + betulkan KPI dashboard | S | Order `refunded` masih dihitung "menunggu bayar" (temuan 0011, ada bukti) | **SEKARANG** |
| 6 | **Ongkir satu rumus** (checkout pakai `/api/shipping/quote`) | S | Pelanggan lihat +35.000, ditagih +28.000 (beda Rp 7.000) | **SEKARANG** |

### P2 — setelah ada transaksi

| # | Item | Effort | Kenapa penting | Trigger |
|---|---|---|---|---|
| 7 | ~~Kelola kategori & warna~~ | S | ✅ **SELESAI** (2C) | — |
| 8 | **Sambungkan sample request** (form storefront + halaman admin) | M | Endpoint sudah hidup tapi nol pemanggil (temuan 0011) | user mau fitur sample |
| 9 | Editor konten (hero, banner, **kontak + WA**) | M | Ganti teks harus edit kode | user mau ubah tampilan |
| 10 | **Beranda dinamis** (sekarang 11 kartu hardcode, nol API) | M | `featured`/`bestseller` tak terlihat di beranda | Fase 3 |
| 11 | Halaman kelola customer | S | Lihat pelanggan & riwayat | >10 pelanggan |
| 12 | Export order CSV (pembukuan) | S | Rekap manual melelahkan | saat pembukuan bulanan |
| 13 | **Pembayaran** (Midtrans/Xendit) | L | Uang masuk otomatis | setelah alur order matang |

### P3 — utang teknis

| # | Item | Effort | Kenapa penting | Trigger |
|---|---|---|---|---|
| 10 | Grafik penjualan di dashboard | M | Angka mentah kurang berguna | >50 order |
| 11 | Audit log aksi admin | M | Tahu siapa ubah apa | kalau ada >1 admin |
| 12 | Peran admin (owner vs staff) | M | Staff tak boleh lihat harga beli | kalau rekrut staff |
| 13 | Notifikasi email/WA saat status berubah | M | Pelanggan nggak tahu progres | setelah order jalan |

---

## Ditunda dengan sengaja

Lihat [`BACKLOG.md`](../BACKLOG.md) — setiap item ada alasan + trigger.

---

## Ditolak (jangan diajukan lagi tanpa alasan baru)

| Item | Alasan |
|---|---|
| Pindah ke WordPress/WooCommerce | Backend sudah punya 53 endpoint; migrasi = buang kerja + risiko keamanan baru |
| Pindah ke Shopify/Medusa/Saleor | Bayar bulanan / berat / overkill untuk 1 toko |
| Ganti ke headless CMS (Strapi/Directus) | Harus ganti backend & DB; UI admin bisa dibangun di atas backend yang ada |
| Ganti framework ke Spec Kit / BMAD | Overhead 9×–berat; proyek ini brownfield, 1 developer. Lihat `plans/0001` |
| Editor visual drag-and-drop (page builder) | Kompleks, rapuh, nggak sepadan untuk katalog sederhana |
