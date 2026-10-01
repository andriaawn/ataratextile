# 0007 — Perbaiki halaman admin yang bocor di layar sempit

Status: ✅ **SELESAI & LIVE** (belum di-commit)
Tanggal: 2026-10-01
Turunan dari: temuan audit responsif Fase 2 (bukan bagian `plans/0006`)

---

## Masalah

Audit responsif Fase 2 menemukan dua halaman admin **melebar melewati layar**
(scroll horizontal), padahal halaman Produk (Fase 2) sendiri bersih.

| Halaman | 320px | 360 | 480 | 768 | 900 | 1024 | ≥1280 |
|---|---|---|---|---|---|---|---|
| `/admin` (Dashboard) | 1px | 0 | 0 | 11px | 0 | 0 | 0 |
| `/admin/pesanan` | **478px** | 438 | 318 | 286 | 169 | 45px | 0 |

Di HP, halaman Pesanan ~1,5× lebar layar. Baru normal di ≥1280px.

## Akar masalah (terukur, bukan tebakan)

`.admin-main{display:grid}` **tanpa** `grid-template-columns`. Grid membuat kolom
implisit berukuran `auto`, dan `auto` **tidak mau menyusut di bawah min-content**.
Di halaman Pesanan min-content = tabel 7 kolom = **782px** → `.admin-main` jadi
784px walau parent-nya 292px.

Dibuktikan dengan tes sembunyikan-lalu-ukur di browser:
- sembunyikan tabel pesanan → overflow **478 → 0** (penyebabnya tabel)
- sembunyikan `#orders-workspace` → **478 → 0**
- `.table-wrap` sudah `overflow:auto`, tapi itu **tidak menolong** selama kolom
  grid-nya sendiri masih bisa melebar

Dashboard: `.kpi-strip{grid-template-columns:repeat(4,1fr)}` — `1fr` = `minmax(auto,1fr)`,
`auto` = min-content label terpanjang ("STOK MENIPIS") → 90px/kolom → 1px di 320px.

**Kenapa halaman Produk selamat?** 2E menambahkan `.admin-panel{min-width:0}` —
tanpa sengaja menutup lubang yang sama.

**Bukan regresi 2E.** `.admin-layout`/`.admin-main` lahir di `913c663` (Fase 1).
`git diff 572bfdf..b3e6916 -- store.css` membuktikan 2E tidak menyentuhnya.

## Perbaikan

Satu blok di `store.css`, pola yang sama dengan yang sudah dipakai di halaman Produk:

```css
.admin-layout{grid-template-columns:minmax(0,220px) minmax(0,1fr)}
.admin-main{grid-template-columns:minmax(0,1fr);min-width:0}
.admin-side{min-width:0}
.kpi-strip{grid-template-columns:repeat(4,minmax(0,1fr))}
@media (max-width:760px){
  .admin-layout{grid-template-columns:minmax(0,1fr)}
  .kpi-strip{grid-template-columns:repeat(2,minmax(0,1fr))}
}
```

**Sudah diuji live di browser sebelum ditulis ke repo:** 0px di 14 lebar
(320–1440) untuk ketiga halaman admin, dan geometri desktop 1280px **identik
sampai piksel** (tidak ada perubahan tampilan).

## Yang TIDAK diubah

- **Tabel tetap lebar.** Tabel pesanan 7 kolom tetap 782px — itu benar; dia
  discroll di dalam kotaknya, bukan melebarkan halaman.
- **Drawer & modal tidak diubah** — sudah pakai `min(460px,100%)` / `min(400px,100%)`,
  sudah 0 overflow di 320/360/414 (diuji dengan drawer & modal terbuka).
- **Storefront tidak diubah** — sudah bersih di 10 lebar × 6 halaman.
- **Nol endpoint baru.** Nol perubahan HTML. Nol perubahan JS.

## Acceptance criteria

- [x] Ketiga halaman admin: **0px scroll horizontal** di 320/360/390/414/480/600/700/760/768/820/900/1024/1280/1440
- [x] Tampilan desktop 1280px **tidak berubah** (geometri sidebar & main identik sampai piksel)
- [x] Drawer & modal tetap 0 overflow di 320/360/414
- [x] `tests/responsive.test.sh` menangkap regresi (penjaga CSS di bundle) — **27/27**
- [x] Negative control: hapus `minmax` → test **GAGAL 12 cek**
- [x] Suite penuh tetap hijau + idempoten — **247/247 dua kali**
- [x] DB produksi tidak tersentuh

## Bukti pengukuran (browser sungguhan, halaman TERISI)

Dua kali diukur: sekali dengan halaman login kosong (menyesatkan), sekali dengan
sesi admin disuntik ke DB throwaway supaya tabel/KPI benar-benar berisi.

| Halaman | Sebelum | Sesudah |
|---|---|---|
| `/admin` | 1px @320 · 11px @768 | **0 di 14 lebar** |
| `/admin/pesanan` | 478px @320 · 438 @360 · 384 @414 · 286 @768 · 45 @1024 | **0 di 14 lebar** |
| `/admin/produk` | 0 | **0** (tidak berubah) |

**Negative control fungsional** (fix dibalik di browser, halaman terisi):
`/admin` → 1px @320 & 11px @768 muncul lagi · `/admin/pesanan` → 478/438/384/286/45
muncul lagi. **Semua tertangkap.**

## Pelajaran

1. **Mengukur halaman yang belum terisi = mengukur form login, bukan tabel.** Sesi
   produksi gw kedaluwarsa, jadi pengukuran pertama cuma melihat form login → "0px"
   yang tidak membuktikan apa pun. Untuk membuktikan, suntik sesi admin ke DB
   throwaway (tanpa mengetik password) supaya tabel benar-benar terisi.
2. **`overflow:auto` pada anak tidak menolong kalau induknya grid.** `.table-wrap`
   sudah `overflow:auto`, tapi `.admin-main` (grid tanpa `grid-template-columns`)
   tetap memakai min-content tabel sebagai minimum kolom → halaman melebar.
   Penguncinya harus di **induk grid**, bukan di tabel.
3. **Aturan CSS lama boleh dibiarkan** selama blok perbaikan ditaruh **setelahnya**
   (CSS memakai deklarasi terakhir yang menang). Test harus memeriksa **urutan**,
   bukan cuma keberadaan.
4. **Pola pencarian di test harus cocok dengan CSS yang sudah diminifikasi.** Pola
   `admin-layout{display:grid;grid-template-columns:220px 1fr}` gagal karena aturan
   aslinya masih punya `;gap:30px;padding:35px 0}` di belakangnya → alarm palsu
   "urutan salah". Ambil prefix yang cukup, jangan seluruh deklarasi.
5. **Proses throwaway bisa nyangkut dan memalsukan hasil.** Server `/tmp/atara_test6`
   yang cwd-nya sudah `(deleted)` tetap memegang port 8881 → server runner gagal
   bind → HTML kosong → 3 suite "gagal" padahal kodenya benar. Cek port dulu
   sebelum menyalahkan kode.
6. **Jangan `pkill -f <pola>`** kalau pola itu ada di command line kita sendiri —
   shell ikut terbunuh. Iterasi `/proc/*/cwd` dan bandingkan `readlink`.

