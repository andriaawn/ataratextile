# 0005 — Rapikan UI/UX CMS admin

Status: ✅ SELESAI & LIVE (2026-10-01)
Dasar: audit 2026-09-30 (browser + ukur kontras, bukan tebak).

## Masalah yang dibuktikan

| # | Temuan | Bukti | Status |
|---|--------|-------|--------|
| 1 | `/admin` (dashboard) belum ikut dirapikan | judul & header tabel Inggris; KPI tanpa hint; empty state polos | ✅ |
| 2 | Form login **kedip** di `/admin` & `/admin/produk` | `<div id="admin-auth">` tidak punya `hidden` → form tampil dulu, JS baru sembunyikan | ✅ |
| 3 | Nama produk **dobel** di tabel produk | `Double Pique 165 — Blend DTYDouble Pique`; `<small>` tanpa `.sub` | ✅ |
| 4 | Bahasa campur di halaman Produk | eyebrow/header/tombol Inggris | ✅ |
| 5 | Status produk tanpa badge | teks `active` polos | ✅ |
| 6 | Judul tab 3 pola beda | `Admin Commerce — …` / `Pesanan — Admin Atandra` / `Products Admin — …` | ✅ |
| 7 | Focus ring tidak kelihatan di header gelap | outline bawaan `#101010` vs `--deep #0d3132` = **1.36** | ✅ |
| 8 | `#9aa5a2` dipakai di 2 background berbeda | `.spec-grid small` di paper = **2.50** ❌ | ✅ |
| 9 | Token `--text-muted:#8a9694` = 3.01 ❌ | jebakan untuk kode berikutnya | ✅ |

## Koreksi audit (jujur)
Klaim awal "fokus keyboard NOL" **SALAH** — outline bawaan browser tetap ada dan match
`:focus-visible`. Masalah nyatanya #7: warnanya gelap sehingga hilang di header gelap.
Tidak ada elemen yang `outline:none`. Dikoreksi sebelum implementasi.

## Yang dikerjakan

### CSS (`store.css`) — satu titik, kena semua halaman
- **Cincin fokus dua warna** di `:focus-visible`: `outline:2px solid #ffd166` +
  `box-shadow:0 0 0 4px var(--ink)`. Terukur: kuning vs `--deep` **9.69**, halo vs paper
  **14.83** — jadi terbaca di permukaan gelap *dan* terang. Fallback `@supports`.
- `--text-muted` `#8a9694` → **`#63716f`** (5.01:1).
- `.spec-grid small` `#9aa5a2` → `var(--muted)` (2.50 → 5.55).
- Badge status produk: `.badge--active/draft/archived/out_of_stock` (semua ≥5.40 dengan teks putih).
- `.admin-stack`, `.register-details`, `.sub` global.

### `/admin` (dashboard) — diseragamkan ke pola `/admin/pesanan`
- `hidden` di panel login (anti-kedip), bahasa Indonesia, `.page-head` + `.kpi-strip`.
- Tabel `.table-wrap` + badge status + label Indonesia + `tabular-nums`.
- Daftar "Buat akun admin baru" dipindah ke `<details>` (form bersih, fungsi tetap).
- Hanya 8 pesanan terbaru ditampilkan (sebelumnya semua order tanpa batas).

### `/admin/produk`
- Bahasa Indonesia (eyebrow, header tabel, tombol, judul tab), tombol "Muat ulang".
- Fix bug dobel: `<span class="sub">`.
- Status pakai badge; tombol `Varian` / `Arsipkan` pakai kelas `.btn`.
- Panel loading (skeleton) menggantikan panel kosong yang berkedip.
- Tombol login di-bind **di luar** `try` — sebelumnya kalau sesi gagal, tombol login mati.
- Guard `bindAll()` supaya listener form tidak menumpuk saat login ulang.

### Judul tab
Satu pola: `Dashboard — Admin Atandra` · `Pesanan — Admin Atandra` · `Produk — Admin Atandra`.

## Bukti

| Cek | Hasil |
|---|---|
| `tests/admin-ui.test.sh` (baru) | **17/17 PASS** |
| `tests/admin-orders.test.sh` | **16/16 PASS** (nol regresi) |
| `tests/security.test.sh` | **10/10 PASS** (nol regresi) |
| **Negative control** | ubah balik ke kondisi lama → test baru **GAGAL 14/18 (exit 1)**; restore → 17/17 hijau |
| Browser: 3 halaman admin + 5 halaman toko | nol error console |
| Browser: Tab sampai habis | cincin fokus kuning terlihat di header gelap & tombol terang |
| Browser: `/admin` tanpa sesi | panel login punya `hidden` di HTML (tidak kedip) |
| Kontras | semua token ≥4.5; cincin fokus 9.69/14.83 |
| Responsive 360px | nol scroll horizontal di 3 halaman admin |
| DB produksi | tidak tersentuh (1 admin · 0 order · 11 produk · 0 reserved) |

## Tidak dikerjakan (YAGNI)
- Tidak pindah framework, tidak tambah dependency, tidak ubah backend.
- Dark mode tetap ditunda (keputusan design-system).
- Beranda (`index.html`) punya CSS inline sendiri — **tidak** disentuh (desain terpisah).
