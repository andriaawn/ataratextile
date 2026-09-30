# Roadmap — apa yang tersisa

**Updated:** 2026-09-30
**Status:** Live di https://txt.invesbot.my.id · Fase 1 (admin Order) ✅ selesai · Fase 2 berikutnya

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

---

## Tersisa — per prioritas

### P1 — sebelum ada pembeli nyata

| # | Item | Effort | Kenapa penting | Trigger |
|---|---|---|---|---|
| 1 | ~~Halaman admin Order~~ | M | ✅ **SELESAI** 2026-09-30 | — |
| 2 | ~~Fix sidebar admin~~ | S | ✅ **SELESAI** (sekalian seragamkan menu) | — |
| 3 | **Upload gambar produk** (sekarang cuma tempel URL) | M | Nggak bisa tambah produk tanpa URL gambar | **SEKARANG** |
| 4 | **Harga asli** (sekarang placeholder `825000 + gsm*1000`) | S | Harga palsu terlihat pembeli | user siapkan daftar harga |

### P2 — setelah ada transaksi

| # | Item | Effort | Kenapa penting | Trigger |
|---|---|---|---|---|
| 5 | Kelola kategori & warna (sekarang 1 kategori, 4 warna) | S | Katalog nggak bisa tumbuh | >1 kategori dibutuhkan |
| 6 | Editor konten (hero, banner, **kontak + WA**) | M | Ganti teks harus edit kode | user mau ubah tampilan |
| 7 | Halaman kelola customer | S | Lihat pelanggan & riwayat | >10 pelanggan |
| 8 | Export order CSV (pembukuan) | S | Rekap manual melelahkan | saat pembukuan bulanan |
| 9 | **Pembayaran** (Midtrans/Xendit) | L | Uang masuk otomatis | setelah alur order matang |

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
| Pindah ke WordPress/WooCommerce | Backend sudah punya 34 endpoint; migrasi = buang kerja + risiko keamanan baru |
| Pindah ke Shopify/Medusa/Saleor | Bayar bulanan / berat / overkill untuk 1 toko |
| Ganti ke headless CMS (Strapi/Directus) | Harus ganti backend & DB; UI admin bisa dibangun di atas backend yang ada |
| Ganti framework ke Spec Kit / BMAD | Overhead 9×–berat; proyek ini brownfield, 1 developer. Lihat `plans/0001` |
| Editor visual drag-and-drop (page builder) | Kompleks, rapuh, nggak sepadan untuk katalog sederhana |
