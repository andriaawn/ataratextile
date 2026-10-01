# 0010 — CMS nyaman dipakai di HP

Status: ✅ **SELESAI & LIVE** (belum di-commit)
Tanggal: 2026-10-01
Laporan user: "cek bagian varian Dan stock itu ui nya tumpang tindih kalo di mobile…
lu harus cek lagi keseluruhan cms untuk di mobile ui nya harus enak di lihat mata dan
navigasinya mudah. kalo perlu lu research lebih dalam dulu."

---

## ⚠️ TEMUAN SUSULAN: bug ini BUKAN cuma mobile

Saat mengukur sebelum patch, ternyata baris varian **rusak di SEMUA lebar**, termasuk desktop:

| Lebar | Baris | checkbox | nama warna | input | tombol |
|---|---|---|---|---|---|
| 1440px | 872px | **439px** | **80px** (kepencet) | 80/80/153px | **turun ke baris 2** |
| 1280px | 872px | **439px** | 80px | 80/80/153px | turun baris |
| 1024px | 661px | 228px | 80px | 80/80/153px | turun baris |
| 900px | 553px | 90px | 90px | 90/90/153px | turun baris |

Artinya **"desktop tidak berubah" tidak bisa jadi acceptance** — desktop memang harus
diperbaiki. Akar sama: grid berkolom tetap, jumlah anak berubah-ubah.

**Keputusan teknis: grid → flexbox.** Grid berkolom tetap (5) selalu geser karena DOM
punya 6 anak (7 kalau badge muncul). Flexbox dengan `flex-basis` + `min-width` membuat
input **turun baris** saat ruang kurang — bukan diperas jadi 24px. Tahan terhadap jumlah
anak yang berubah.

---

## Yang dilaporkan (dikonfirmasi terukur)

**Baris varian tumpang tindih di HP — BENAR.** Di 360px:

| Anak ke- | Elemen | Lebar hasil |
|---|---|---|
| 1 | checkbox pilih | 24px |
| 2 | nama warna | **24px** (terpotong) |
| 3 | input harga | **24px** (tak bisa diketik) |
| 4 | input grosir | **24px** |
| 5 | input stok | 153px |
| 6 | tombol Simpan | **24px, turun ke baris 2** |

Akar: `.variant-row` mendefinisikan **5 kolom** (`minmax(0,1fr) repeat(3,minmax(0,80px)) auto`)
tapi DOM-nya berisi **6 anak** (checkbox + warna + 3 input + tombol; +1 badge kalau stok
menipis). Anak ke-6 membungkus ke baris berikutnya, dan `minmax(0,1fr)`/`minmax(0,80px)`
memperas sisanya sampai **24px** — mustahil disentuh jari.

## Audit menyeluruh (diukur di 320/360/390/414px, dengan data terisi)

Ternyata **bukan satu bug** — pola yang sama muncul 3×: **form flex-wrap yang memeras
input jadi tak terpakai**.

| # | Tempat | @320 | @360 | @390 | @414 | Masalah |
|---|---|---|---|---|---|---|
| 1 | Baris varian | 24px | 24px | 24px | 24px | tumpang tindih, 6 anak vs 5 kolom |
| 2 | Form "Tambah varian" (5 kontrol + tombol) | **44px** | **29px** | 35px | 40px | semua input seukuran jempol, tak bisa diketik |
| 3 | Form "Harga bertingkat" (3 input + tombol) | 45px | **35px** | 45px | 53px | idem |

**Yang sudah bagus (jangan diutak-atik):**

| Area | Temuan |
|---|---|
| Overflow horizontal | **0px** di 320–414 semua halaman & tab (0007 sudah beres) |
| Tumpang tindih non-varian | **0** |
| Teks terpotong | **0** |
| Tabel lebar | scroll lokal di `.table-wrap` (`overflow:auto`) — benar |
| Navigasi sidebar admin | jadi baris horizontal, `overflow:auto`, target 45px — **sudah enak** |
| Tab Produk | `tablist` 332px di viewport 360, target 39–40px — **sudah enak** |

**Temuan sekunder (kualitas, bukan bug):**

| # | Temuan | Ukuran |
|---|---|---|
| 4 | Tombol sekunder kekecilan: "Hapus" 26px, "pilih file" 32px, "Lihat pratinjau" 32px | < 40px (WCAG 2.5.8 minta ≥24px, 2.5.5 minta 44px) |
| 5 | Font mikro 9–10px (`.store-brand small`, `th`, `label`) | 9px — batas baca bawah |
| 6 | 3 input di baris varian **tanpa label** — cuma angka (990000, 940000, 20). Di HP admin tak tahu mana harga/grosir/stok | aksesibilitas |

## Riset (ringkas, sumber di bawah)

- **WCAG 2.2 SC 2.5.8** (wajib): target ≥ **24×24** CSS px. **SC 2.5.5** (disarankan):
  ≥ **44×44** — Apple HIG 44pt, Material 48dp.
- **Tabel padat di HP**: jangan mengecilkan semua kolom — pilih: sembunyikan kolom
  sekunder, pindah ke `details`, scroll lokal terkendali, atau **ubah baris jadi kartu**.
- **Form**: di coarse pointer naikkan `min-height` kontrol jadi 44px; **input font
  ≥16px** supaya iOS tidak auto-zoom saat fokus.
- **Jangan bergantung pada hover**; beri jarak antar-aksi agar tidak salah tekan.
- Pakai `@media (pointer:coarse)` untuk **interaksi**, `max-width` untuk **layout**.

Sumber: W3C WAI (Understanding SC 2.5.5 / 2.5.8), praktik admin WordPress touch-friendly,
pola ActiveAdmin mobile (baris tabel → kartu + `data-label`), pedoman dashboard mobile.

## Rencana perbaikan (murni CSS + sedikit markup)

### A. Baris varian jadi kartu di HP (≤640px) — SUDAH DITULIS, tinggal dirapikan

Sudah diterapkan & terbukti: input 290px×38px, tombol 290px×40px, **0 tumpang tindih**.
Tinggal: beri **label kecil di atas tiap input** (harga / grosir / stok) — karena
`<input>` tidak bisa pakai `::before`, label ditambah sebagai elemen.

### B. Form "Tambah varian" & "Harga bertingkat": 1 kontrol per baris di HP (≤640px)

`inline-form` jadi `display:grid; grid-template-columns:minmax(0,1fr)` → tiap kontrol
lebar penuh. Tombol submit juga lebar penuh. Input **font 16px** (cegah zoom iOS) +
`min-height:44px`.

### C. Tombol & target sentuh naik ke ≥44px di HP

`.btn`, `.chip`, tombol baris, "pilih file", "Hapus" → `min-height:44px` di ≤640px.
Checkbox di baris varian: area sentuh diperbesar (padding, bukan ukuran kotak).

### D. Tipografi mikro dinaikkan di HP

`th`/`label`/`small` yang 9–10px → **11px** di ≤640px. Nol perubahan kontras token.

### E. (opsional, murah) Tabel → kartu di HP

Ini yang paling berdampak tapi paling banyak ubah markup. **Usul: TIDAK sekarang** —
tabel sudah punya scroll lokal yang benar dan nol overflow. Kalau nanti kerasa sempit,
bikin plan terpisah.

## File yang berubah

| File | Perubahan |
|---|---|
| `store.css` | blok `@media(max-width:640px)` + `@media(pointer:coarse)` — kartu varian, form 1 kolom, target 44px, font naik |
| `admin-products.js` | label kecil di baris varian (harga/grosir/stok) — **teks saja, nol endpoint** |
| `tests/mobile-cms.test.sh` | **BARU** — cek penanda CSS + label |
| `tests/responsive.test.sh` | +cek: form & baris varian tidak diperas (<60px) di 360px |
| `docs/design-system.md` | aturan: form 1 kolom di ≤640px, target 44px, input 16px |
| `plans/README.md`, `plans/ROADMAP.md`, `HANDOFF.md` | status |

**Nol endpoint baru · nol halaman baru · nol perubahan HTML.**

## Acceptance criteria — SEMUA ✅

- [x] Baris varian di 320/360/390/414: **0 tumpang tindih**, tiap input ≥ **120px** (dapat 250–558px)
- [x] Form "Tambah varian" & "Harga bertingkat": tiap kontrol ≥ **120px** (dapat 250–558px, dulu 29–55px)
- [x] Semua target sentuh ≥ **44px** di ≤640px
- [x] Input font ≥ **16px** di ≤640px (cegah auto-zoom iOS)
- [x] Tiap input baris varian punya **label terlihat** (Harga/Grosir/Stok)
- [x] Teks mikro ≥ **11px** di ≤640px
- [x] Overflow horizontal **0px** di 320–1440, semua halaman & tab
- [x] ~~Desktop tidak berubah~~ → **dibatalkan**: desktop juga rusak, kini diperbaiki
- [x] Suite penuh hijau + idempoten (296/296 × 2); **negative control GAGAL 2/1/3**
- [x] Nol regresi kontras (token warna tidak disentuh)

**Hasil ukur (browser, data terisi):**

| | 320 | 360 | 414 | 640 | 768 | 1440 |
|---|---|---|---|---|---|---|
| overflow | 0 | 0 | 0 | 0 | 0 | 0 |
| diperas <100px | 0 | 0 | 0 | 0 | 0 | 0 |
| tumpang tindih | 0 | 0 | 0 | 0 | 0 | 0 |

**Live:** semua aturan fix ada di `store-DYmSu7XF.css`; label `.vf` di `adminProducts-RqF7KKgH.js`.
**Fungsional:** harga/stok tersimpan + persist, 0 error console.

## Out of scope

- Tabel → kartu (plan terpisah kalau perlu)
- Ganti kerangka CSS / framework UI
- Dark mode, animasi, PWA
- Halaman storefront (fokus: CMS admin, sesuai laporan)

## Sumber riset

- W3C WAI — Understanding SC 2.5.5 Target Size (Enhanced, 44px) & 2.5.8 (Minimum, 24px)
- Praktik admin touch-friendly (target 44px, `pointer:coarse`, tabel → kartu)
- Pola ActiveAdmin mobile: baris → kartu + `data-label`, form 1 kolom, input 16px
- Pedoman dashboard mobile: target jempol, hindari hover-only, scroll lokal
