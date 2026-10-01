# 0009 — Tutup kebocoran panel admin sebelum login

Status: ✅ **SELESAI & LIVE** (belum di-commit)
Tanggal: 2026-10-01
Laporan user: "kenapa Ringkasan operasional / Dashboard bisa diakses walaupun belum login?"
lalu "hampir semua menu di admin bisa diakses padahal belum login — harusnya ketutup
login dulu baru bisa diakses".

---

## Masalah

Buka `/admin` atau `/admin/produk` **tanpa login** → kerangka dashboard/workspace
**tetap terlihat**: judul "Dashboard", tombol "Keluar", header tabel (NOMOR, PELANGGAN,
TOTAL, STATUS, PEMBAYARAN), tombol "Buat produk", semua label form produk, dsb.

## Akar masalah (terukur, bukan dugaan)

Atribut `hidden` **dikalahkan** oleh aturan CSS `display` milik kelas elemen itu:

| Elemen | Atribut | CSS yang menang | Akibat |
|---|---|---|---|
| `#admin-dashboard` (`.admin-stack`) | `hidden` | `.admin-stack{display:grid}` | **tampil 930×282** |
| `#products-workspace` (`.admin-stack`) | `hidden` | `.admin-stack{display:grid}` | **tampil 930×1301** |
| `#image-preview` (`.image-preview`) | `hidden` | `.image-preview{display:flex}` | **tampil 872×114** |

CSS `[hidden]` bawaan browser = `display:none`, tapi **spesifisitasnya kalah** dari
aturan kelas (`.admin-stack`). Proyek ini sudah tahu jebakan itu — makanya ada
`.admin-panel[hidden]{display:none}` — tapi **aturan itu cuma dibuat untuk `.admin-panel`**,
tidak untuk `.admin-stack` / `.image-preview`. Jadi lubangnya setengah tertutup.

**Asal**: commit `2ade430` (plan 0005) — saat itu `#admin-dashboard` diberi class
`admin-stack` (yang `display:grid`) **tanpa** aturan penutupnya.

## Dampak — penting, jangan dibesar-besarkan

- **Data TIDAK bocor.** Semua API admin balas **401** tanpa login
  (`/api/admin/orders` → 401, `/api/admin/dashboard` → 401). Tabel kosong (0 baris),
  KPI kosong, daftar kategori kosong.
- Yang bocor = **kerangka UI + label** (nama kolom, nama field, tombol). Ini
  **information disclosure ringan**, bukan kebocoran data pelanggan.
- Tetap **harus diperbaiki**: user benar — panel admin tidak boleh tampil sebelum login.

## Fix

Tambah aturan penutup **umum** di akhir `store.css` (biar menang urutan):

```css
/* WAJIB: atribut `hidden` kalah spesifisitas dari aturan kelas (mis. .admin-stack{display:grid}).
   Tanpa ini, panel admin tampil sebelum login. Berlaku untuk SEMUA elemen. */
[hidden]{display:none!important}
```

**Kenapa `[hidden]{display:none}` global (bukan tambal satu-satu)?**
- Satu aturan menutup **semua** elemen `hidden` sekarang dan **di masa depan** — kelas
  bug ini tidak bisa terulang saat halaman baru ditambah.
- Semua JS di proyek ini menyembunyikan lewat **properti `.hidden`** (grep: 30+ pemakaian,
  **nol** pemakaian `style.display`) → `!important` **tidak** memblokir JS.
- `!important` dipakai justru karena atribut `hidden` harus menang atas aturan kelas —
  itu memang fungsi `hidden`.

## Test

`tests/hidden-guard.test.sh` (**BARU**) — cek statis, tanpa browser:

1. Aturan `[hidden]{display:none` ada di `store.css`.
2. Aturan itu muncul **setelah** `.admin-stack{display:grid}` (urutan menang).
3. **Setiap** elemen ber-atribut `hidden` di SEMUA `*.html` — kalau kelasnya punya
   aturan `display` di CSS, harus tertutup oleh `[hidden]` global.
4. Aturan lama `.admin-panel[hidden]{display:none}` masih ada (tidak regresi 2E).
5. `store.css` tetap CRLF.

**Negative control**: buang `[hidden]{display:none!important}` → test **GAGAL**.

**Uji browser** (throwaway + sesi disuntik): tanpa sesi → dashboard/workspace
**tinggi 0** & tidak ada judul admin yang terlihat; **dengan** sesi → dashboard tampil
normal (tidak ada regresi). Diukur di 320/360/390/768/1280.

## File yang berubah

| File | Perubahan |
|---|---|
| `store.css` | +1 aturan `[hidden]{display:none!important}` (append di akhir) |
| `tests/hidden-guard.test.sh` | **BARU** |
| `plans/0009-tutup-panel-admin.md` | **BARU** |
| `tests/admin-tabs.test.sh` | tambah 1 cek: `.admin-stack[hidden]` juga tertutup (regresi 2E) |
| `docs/design-system.md` | catat aturan: elemen `hidden` + kelas ber-`display` WAJIB ditutup `[hidden]` |
| `plans/README.md`, `plans/ROADMAP.md`, `HANDOFF.md` | status |

**Nol endpoint baru · nol HTML baru · nol JS berubah.**

## Acceptance criteria — SEMUA ✅

- [x] Tanpa login: `/admin` → dashboard **tinggi 0**, tidak ada judul "Dashboard" terlihat ✅ (live: `TINGGI-0`, judul cuma "Akses admin")
- [x] Tanpa login: `/admin/produk` → workspace **tinggi 0**, tidak ada label form terlihat ✅ (live: `TINGGI-0`)
- [x] Tanpa login: form login **tetap terlihat** ✅ (930×352 · tombol "Login admin" + 4 input)
- [x] Dengan login: dashboard & workspace tampil **normal** ✅ (930×572 & 930×1784; judul "Dashboard"/"Produk")
- [x] Semua elemen `hidden` di semua halaman tertutup ✅ (cek statis 8 halaman → **0 bocor**)
- [x] Suite penuh tetap hijau + idempoten ✅ (**275/275**, 11 suite, 2 putaran)
- [x] Negative control: buang aturan → test **GAGAL** ✅ (NC-1 **GAGAL 3** · NC-2 **GAGAL 1**)
- [x] `store.css` tetap CRLF ✅; nol perubahan HTML/JS/endpoint ✅

## Hasil

| | |
|---|---|
| Test baru | `tests/hidden-guard.test.sh` — **5 cek** (+1 di mode sumber: CRLF), 5/5 ✅ |
| Suite 2E | +1 cek (`10a2` penutup global) → 38 → **39** ✅ |
| Suite penuh | **275/275** (11 suite), idempoten 2× |
| Negative control | NC-1 GAGAL **3** · NC-2 GAGAL **1** ✅ |
| Uji browser | 8 halaman × tanpa sesi → **0 panel bocor**; dengan sesi → normal |
| Responsif | **0 overflow** @320/360/390/414/768/1024/1280 (tanpa & dengan sesi) |
| Deploy | LIVE — CSS live memuat `[hidden]{display:none!important}` |

**Temuan tambahan (aman, tidak perlu fix):** `/admin/pesanan` punya drawer `#drawer` yang
`display:flex` dan `aria-hidden="true"`, tapi digeser `translateX(460px)` → posisinya
**tepat di luar viewport** (x=1280 pada viewport 1280). Tidak terlihat user.

**Pelajaran (bug di TEST, ketemu lewat negative control):** cek `grep '\[hidden\]{display:none'`
itu **terlalu longgar** — ia cocok dengan `.admin-panel[hidden]{display:none}`, padahal aturan
itu TIDAK menutup `.admin-stack[hidden]`. Test jadi hijau padahal aturan global sudah dibuang
(NC-1 awalnya tidak GAGAL). **Fix**: cek **selector global** — `[hidden]` yang berdiri sendiri
(didahului awal baris/`}`/`,`), bukan sekadar substring. Ini persis kelas bug yang dijaga.

## Out of scope

- Ganti arsitektur jadi render server-side / middleware redirect (tidak perlu — API
  sudah 401, ini murni bug CSS).
- Uji penetrasi lanjutan.
