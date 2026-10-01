# 0006 — Fase 2: Product CMS

Status: ✅ **FASE 2 SELESAI** — 2A ✅ · 2B ✅ · 2C ✅ · 2D ✅ · **2E ✅ SELESAI & LIVE**
Tanggal: 2026-10-01
Turunan dari: [`0002-cms-roadmap.md`](0002-cms-roadmap.md) — bagian "FASE 2 — Product CMS"
Dokumen pendukung: [`docs/cms-architecture.md`](../docs/cms-architecture.md),
[`docs/design-system.md`](../docs/design-system.md)

---

## Progres

| Bagian | Status | Bukti |
|---|---|---|
| **2A — Upload gambar** | ✅ **SELESAI & LIVE** | `tests/uploads.test.sh` **38/38** · negative control GAGAL 3 |
| **2B — Bulk edit harga** | ✅ **SELESAI & LIVE** | `tests/bulk-price.test.sh` **36/36** · negative control GAGAL 7 |
| **2C — Kelola kategori & warna** | ✅ **SELESAI & LIVE** | `tests/catalog.test.sh` **37/37** · negative control GAGAL 10 |
| **2D — Badge stok menipis** | ✅ **SELESAI & LIVE** | `tests/low-stock.test.sh` **28/28** · negative control GAGAL 8 |
| **2E — Rapikan halaman Produk** | ✅ **SELESAI & LIVE** | `tests/admin-tabs.test.sh` **38/38** · negative control GAGAL 7 |

**2E yang terpasang:**
- Halaman Produk dipisah jadi **3 tab**: **Produk** · **Varian & stok** · **Kategori & warna**.
  Dulu semuanya satu gulungan panjang; begitu varian ditambah, form produk dan daftar
  kategori jadi jauh dari pandangan.
- **Panel tetap ada di HTML** (bukan dibuat ulang saat pindah tab) → teks yang sedang
  diketik tidak hilang, dan tidak ada kedip.
- Tab kedua & ketiga punya **`hidden` di HTML statis** (aturan lama: panel yang bergantung
  aksi jangan disembunyikan JS) supaya tidak berkedip saat halaman dimuat.
- **Klik "Varian" di baris produk otomatis pindah ke tab Varian** — admin tidak perlu
  mencari tabnya sendiri.
- `#products-message` ditaruh **di luar panel** supaya pesan sukses/gagal tetap terlihat
  dari tab mana pun.
- Aksesibilitas: `role="tablist"` / `role="tab"` / `role="tabpanel"` + `aria-selected` +
  `aria-controls` + `aria-labelledby`, dan tab bisa dijangkau dengan Tab lalu Enter.
- **Perbaikan 360px (temuan, bukan bagian rencana awal):** input punya lebar intrinsik,
  jadi grid `1fr 1fr` memaksa halaman melebar → scroll horizontal 82px di 360px.
  Diperbaiki dengan `minmax(0,1fr)` + `min-width:0`, dan baris varian ikut ditumpuk.
  **Sebelum:** overflow 82px. **Sesudah:** 0px di 360/390/414/768/1024/1280.

**2D yang terpasang:**
- `productSelect` + `serializeProduct` — ikut ambil `MIN(inv.low_stock_threshold)` dan hitung
  `low_stock: available_stock <= low_stock_threshold` **di server**. Browser tidak menghitung
  ulang, jadi tidak mungkin pratinjau beda dari kenyataan.
- `GET /api/admin/products/:id/variants` — tambah `low_stock_threshold` + `low_stock` per varian.
- `admin-products.html/js` — badge **"Menipis"** di kolom stok daftar produk dan di baris varian.
- `store.css` — token `--status-low-stock: #8a5a1e` + `.badge--low-stock`
  (putih di atasnya = **5.90:1**, lolos WCAG AA).
- **Bug lama yang ikut sembuh:** `PATCH /api/admin/inventory/:variantId` **selalu 500** kalau
  body-nya cuma `{stock}` — `sql.js` melempar kalau ada parameter `undefined`, dan
  `low_stock_threshold` yang tidak dikirim diteruskan apa adanya. Artinya tombol "Simpan"
  di panel varian **tidak pernah berhasil** menyimpan stok. Sekarang dinormalkan ke `null`
  dulu (dan ambang divalidasi ≥ 0 integer → 400 kalau ngawur).

**2C yang terpasang:**
- `GET /api/admin/catalog` — kategori & warna **+ `usage_count`** (jumlah produk/varian
  yang memakai). Satu request, bukan dua daftar + hitung di browser.
- `PATCH /api/admin/colors/:id` (baru) · `DELETE /api/admin/categories/:id` ·
  `DELETE /api/admin/colors/:id`.
- **Hapus DITOLAK 409 kalau masih dipakai** — pesannya menyebut jumlahnya
  ("masih dipakai 11 produk"). Ini bukan kehati-hatian berlebihan: `products.category_id`
  NOT NULL tanpa `ON DELETE`, jadi menghapus kategori terpakai membuat **seluruh katalog
  kosong** (terbukti di negative control: produk publik 11 → 0).
- `PATCH /api/admin/categories/:id` sekarang balikin **409** kalau slug bentrok
  (dulu error-nya tidak tertangkap → 500).
- `admin-products.html/js` — daftar kategori & warna: jumlah pemakai, tombol Ubah
  (edit langsung di baris, bukan dialog browser), tombol Hapus **disabled** kalau dipakai.

**2B yang terpasang:**
- `POST /api/admin/variants/bulk-price` — `{ variant_ids, mode, value, field, dry_run }`.
  Mode `set` / `percent` / `amount`, field `price` / `wholesale_price` / `both`.
- **Atomik**: semua harga dihitung dulu; kalau satu saja jadi ≤ 0 → **400, nol yang berubah**
  (setengah jalan lebih buruk daripada tidak jalan).
- **`dry_run: true`** → hitung + kembalikan pratinjau tanpa menulis apa pun. Pratinjau yang
  dilihat admin = angka yang persis akan tersimpan (server yang menghitung, bukan browser).
- `admin-products.html/js` — panel "Ubah harga massal": checkbox per varian, pilih semua,
  mode, nilai, tabel pratinjau (sebelum → sesudah → selisih, warna naik/turun), Terapkan/Batal.
- `tests/uploads.test.sh` — test 2A dijadikan **idempoten** (dulu pilih "produk pertama" yang
  urutannya `created_at DESC` beresolusi detik → hasilnya berubah antar-run).

**2A yang terpasang:**
- `server/uploads.js` (baru) — magic bytes, hash nama, resize+strip EXIF via ffmpeg, hapus aman
- 7 endpoint baru: `POST/GET/DELETE /api/admin/uploads`, `GET/POST/DELETE /api/admin/products/:id/images`,
  `PATCH /api/admin/products/:id/images/:imageId/primary`
- CSP `img-src` + `blob:` (pratinjau sebelum unggah)
- `admin-products.html/js` — input file + drag & drop + pratinjau + galeri per produk
- `store.js` + `store.css` — halaman toko tampilkan **semua** gambar (thumbnail, klik ganti utama)
- `scripts/backup-uploads.sh` — gambar tidak di-commit, jadi ini yang menjaganya
- `.gitignore` + `public/uploads/`

---

## Goal

Halaman **Produk** sudah bisa lihat & tambah produk, tapi masih setengah jadi: gambar cuma
tempel URL, harga 44 varian harus diubah satu-satu, kategori/warna belum bisa dihapus, dan
stok menipis tidak kelihatan. Fase 2 menutup itu.

**Nol ubah backend yang sudah matang** (40 endpoint, keamanan teruji). Yang ditambah cuma
endpoint yang memang belum ada.

---

## Temuan (hasil baca kode, bukan asumsi)

| # | Fakta | Konsekuensi |
|---|---|---|
| F1 | **Nol alat upload**: tidak ada `multer`/`sharp`/ImageMagick. Deps cuma `cors`, `dotenv`, `express`, `sql.js` | Harus pakai `express.raw()` (bawaan Express) — **nol dependency baru** |
| F2 | `ffmpeg` **ada** di server (`/usr/bin/ffmpeg`) | Bisa resize/strip metadata gambar tanpa install apa pun |
| F3 | `express.json({ limit: '1mb' })` | Upload lewat JSON base64 akan kena limit — pakai `express.raw()` di route khusus |
| F4 | CSP: `img-src 'self' data:` | Preview `blob:` **akan diblokir** → perlu tambah `blob:` |
| F5 | Tabel `product_images` sudah ada (`product_id`, `url`, `alt`, `sort_order`) | Galeri multi-gambar tinggal dibangun, tidak perlu migrasi |
| F6 | `GET /api/products/:slug` **sudah** balikin `images[]` | Tapi `product.html` cuma render 1 gambar (`product.image`) — gambar ke-2 dst tak terpakai |
| F7 | `inventory.low_stock_threshold` ada, tapi `productSelect` **tidak** mengambilnya | Badge low-stock butuh tambah 1 kolom ke query |
| F8 | Endpoint kategori/warna: ada `GET` + `POST`, `PATCH` kategori. **Tidak ada** `PATCH` warna, `DELETE` keduanya | Perlu 3 endpoint baru + cek referensi sebelum hapus |
| F9 | 44 varian = 44 request kalau PATCH satu-satu | Bulk edit harga wajib, bukan opsional |
| F10 | `express.static(public/)` melayani apa saja yang ada di folder | Upload **wajib** divalidasi magic bytes + nama file diacak (jangan percaya ekstensi/nama) |
| F11 | `public/img/` (5.7 MB, 12 file) sudah di-commit; `public/uploads/` belum ada di `.gitignore` | Perlu keputusan: commit gambar user atau tidak |

---

## Decisions

### Sudah diputuskan (mekanisme, bukan selera)

- **Upload pakai `express.raw()` + `Content-Type: image/*`** — nol dependency baru. Menulis
  parser multipart sendiri = ~200 baris rawan bug; `multer` = dependency tambahan untuk
  sesuatu yang Express sudah bisa. Prinsip: **stdlib dulu**.
- **Validasi magic bytes, bukan ekstensi atau `Content-Type`.** JPEG `FF D8 FF`,
  PNG `89 50 4E 47`, WebP `RIFF....WEBP`. Nama file = hash isi + ekstensi dari jenis
  terdeteksi. **SVG DILARANG** (bisa berisi `<script>` → XSS, dan CSP kita mengizinkan
  `img-src 'self'`).
- **Resize pakai `ffmpeg`** (maks sisi terpanjang 1600px, strip metadata EXIF/GPS) —
  kalau ffmpeg gagal, simpan apa adanya dan jangan gagalkan upload. Batas keras 8 MB.
- **Hapus = arsip untuk produk** (sudah begitu), tapi **hapus nyata untuk gambar** (tidak
  ada gunanya mengarsipkan file). Kategori/warna: **tolak hapus kalau masih dipakai**.
- **Bulk harga punya mode** `set` / `+persen` / `+nominal` + **preview sebelum simpan** —
  karena 44 varian dan salah klik = 44 harga rusak.
- **Tambah `blob:` ke CSP `img-src`** — hanya untuk preview sebelum upload. Tidak
  melemahkan keamanan (blob: selalu same-origin).
- **Lanjutkan pola yang sudah ada**: `PAGES` di 3 tempat, URL bersih tanpa `.html`,
  kelas `.badge`/`.btn`/`.table-wrap`, `esc()` sebelum `innerHTML`.

### Ditolak

| Opsi | Alasan |
|---|---|
| `multer` / `formidable` | Dependency baru untuk hal yang `express.raw()` sudah cukup |
| `sharp` | Native module, build berat di VPS 2 CPU; `ffmpeg` sudah ada |
| Cloudinary / S3 | Biaya + pihak ketiga + kredensial tambahan, untuk 1 toko |
| Simpan gambar sebagai base64 di SQLite | DB membengkak, tidak bisa di-cache browser |
| Editor gambar di browser (crop/rotate) | YAGNI — belum ada yang minta |

---

## Rencana — 5 bagian, dikerjakan bertahap

Setiap bagian = **satu commit yang bisa direview**, dengan test + bukti sendiri.

### 2A — Upload gambar (paling penting, ini yang memblokir)
- `server/index.js`:
  - `POST /api/admin/uploads` — `express.raw({ type: ['image/jpeg','image/png','image/webp'], limit: '8mb' })`,
    validasi magic bytes, resize+strip via `ffmpeg`, simpan ke `public/uploads/<hash>.<ext>`.
  - `DELETE /api/admin/uploads/:name` — hapus file (validasi nama: hanya `[a-f0-9]{16,}\.(jpg|png|webp)`).
  - `POST/PATCH /api/admin/products/:id/images` — tambah/hapus baris `product_images`.
  - CSP: tambah `blob:` ke `img-src`.
- `admin-products.html/js` — input file + drag-drop + preview (pakai `blob:`), indikator
  progres, pesan error jelas ("bukan gambar", "terlalu besar"), hapus gambar.
- `store.js` `initProduct` — render **semua** `product.images[]` (sekarang cuma 1), klik
  untuk ganti gambar utama. `product.html` tambah wadah galeri.
- `tests/admin-uploads.test.sh` (baru) — magic bytes, SVG ditolak, file besar ditolak,
  guest ditolak, path traversal ditolak.

### 2B — Bulk edit harga
- `server/index.js` — `POST /api/admin/variants/bulk-price`:
  `{ variant_ids: [], mode: 'set'|'percent'|'amount', value: N }`, dibungkus
  `transaction()`, tolak harga ≤ 0.
- `admin-products.js` — panel bulk: pilih varian (checkbox semua/ per produk), pilih mode,
  **tabel preview harga lama → baru**, tombol simpan.
- `tests/admin-uploads.test.sh` atau file terpisah — mode set/persen/nominal, tolak nilai
  negatif, nol regresi ke 44 varian.

### 2C — Kelola kategori & warna (lengkap)
- `server/index.js` — `PATCH /api/admin/colors/:id`, `DELETE /api/admin/categories/:id`,
  `DELETE /api/admin/colors/:id`. Hapus **ditolak 409** kalau masih dipakai produk/varian.
- `admin-products.js` — daftar kategori & warna dengan tombol ubah/hapus + jumlah pemakai.

### 2D — Badge stok menipis
- `server/index.js` — `productSelect` tambah `MIN(inv.low_stock_threshold) AS low_stock_threshold`.
- `admin-products.js` — badge "Stok menipis" kalau `available_stock <= low_stock_threshold`.
- `admin.html` — kartu "Stok menipis" sudah ada; pastikan angkanya benar.

### 2E — Rapikan halaman Produk
- Panel dipisah jadi tab/section (Produk · Kategori & warna · Varian) supaya tidak jadi satu
  halaman panjang saat varian ditambah.
- Sesuai checklist `docs/design-system.md` §10 (loading, empty, error, 360px, bahasa Indonesia).

---

## File yang berubah (perkiraan)

| File | 2A | 2B | 2C | 2D | 2E |
|---|---|---|---|---|---|
| `server/index.js` | ✅ | ✅ | ✅ | ✅ | |
| `admin-products.html` | ✅ | ✅ | ✅ | | ✅ |
| `admin-products.js` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `store.js` | ✅ | | | | |
| `product.html` | ✅ | | | | |
| `store.css` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `vite.config.ts` | | | | | (kalau ada halaman baru) |
| `tests/*.test.sh` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `docs/api.md`, `docs/cms-architecture.md` | ✅ | ✅ | ✅ | ✅ | (2E: `docs/design-system.md` — nol endpoint baru) |

---

## Acceptance criteria

**2A (selesai):**
- [x] Upload gambar: JPEG/PNG/WebP diterima, **SVG & file non-gambar ditolak** (37/37)
- [x] File > 8 MB ditolak dengan pesan jelas (413, pesan Indonesia)
- [x] Nama file diacak (hash) — nama asli user tidak dipakai (path traversal & XSS)
- [x] Gambar di-resize ke ≤1600px + metadata EXIF dibuang
- [x] Gambar ke-2 dst tampil di halaman produk (thumbnail, klik ganti utama)
- [x] Negative control GAGAL (file jahat diterima 201 & path traversal lolos saat validasi dimatikan)
- [x] `tests/security.test.sh` **10/10** · `admin-orders` **16/16** · `admin-ui` **17/17** (nol regresi)
- [x] DB produksi tidak tersentuh (test di throwaway `/tmp/atara_test6`, port 8881)

**2B (selesai):**
- [x] Bulk harga: 44 varian berubah dalam **1 request**, preview cocok dengan hasil (36/36)
- [x] **Atomik** — satu harga jadi ≤ 0 → 400 & **nol yang berubah** (bukti negative control 7b)
- [x] `dry_run` tidak menulis apa pun (pratinjau aman)
- [x] Mode `set`/`percent`/`amount` × field `price`/`wholesale_price`/`both`
- [x] Endpoint tanpa login → 401; nilai bukan angka / mode ngawur / daftar kosong → 400
- [x] Negative control GAGAL 7 cek (harga negatif tersimpan & varian lain ikut rusak)
- [x] Test **idempoten** — 2× berturut-turut di DB yang sama, hasil sama (117/117)
- [x] DB produksi tidak tersentuh (11 produk · 44 varian · 0 order)

**2C (selesai):**
- [x] Hapus kategori/warna yang masih dipakai → **409**, tidak merusak data (37/37)
- [x] Negative control GAGAL 10 cek — tanpa cek pemakai, **seluruh katalog kosong** (11 → 0 produk)
- [x] `PATCH` warna (baru); `PATCH` kategori slug bentrok → 409 (dulu 500)
- [x] `usage_count` ditampilkan di UI; tombol Hapus disabled kalau dipakai
- [x] Test idempoten (154/154 dua kali berturut-turut)

**2D (selesai):**
- [x] Badge "Stok menipis" kalau `available_stock <= threshold` — di daftar produk & baris varian
- [x] `low_stock` dihitung **server** (satu sumber kebenaran), browser tidak hitung ulang
- [x] Ambang batas benar-benar dibaca (dinaikkan → ikut berubah), batas `<=` bukan `<`
- [x] Kontras badge lolos WCAG AA (putih di `#8a5a1e` = 5.90:1)
- [x] Negative control GAGAL 8 cek
- [x] Test idempoten (182/182 dua kali berturut-turut)

**2E (selesai):**
- [x] Halaman Produk dirapikan jadi **3 tab**: Produk · Varian & stok · Kategori & warna (38/38)
- [x] Panel tetap di HTML → ketikan yang belum disimpan **tidak hilang** saat pindah tab
- [x] Klik "Varian" di baris produk **otomatis pindah tab** (tidak perlu cari tabnya)
- [x] Tab bisa dijangkau keyboard (Tab + Enter), `role=tablist/tab/tabpanel` + `aria-selected`
- [x] **Nol error console**; nol scroll horizontal di 360/390/414/768/1024/1280
- [x] Negative control GAGAL 7 cek (tanpa `minmax(0,1fr)`: halaman melebar 82px di 360px)
- [x] Test idempoten (220/220 dua kali berturut-turut)
- [x] DB produksi tidak tersentuh (11 produk · 44 varian · 0 order)

---

## Pelajaran dari 2A (jangan diulang)

1. **`ffprobe`/`ffmpeg` gagal ≠ upload gagal** — file tetap disimpan apa adanya, cuma
   dicatat di log. Upload tidak boleh bergantung pada alat bantu.
2. **Server membatasi 120 request/menit per IP.** Suite test mengirim ~45 request, jadi
   **jangan** jalankan suite berulang di server yang sama dalam satu menit — hasilnya
   menyesatkan (elemen "hilang" padahal cuma kena 429). Runner `atara_run_all.sh`
   me-restart server tiap suite.
3. **Minifier mengganti nama fungsi** di bundle (`resetImagePreview` hilang, `statusBadge`
   di plan 0005 juga). Test bundle harus cek **markup/atribut stabil** atau **jumlah
   kemunculan**, bukan nama fungsi.
4. **Satu halaman bisa memuat >1 bundle** `store-*.js` (satu kecil untuk `modulepreload`).
   Jangan `head -1` — gabungkan semuanya.
5. **`bindGallery` dipanggil tiap klik "Varian"** → tanpa penjaga `dataset.bound`, satu
   file terunggah berkali-kali. Elemen HTML statis = listener hanya sekali.
6. **`pkill -f 'pola'` bisa membunuh shell sendiri** kalau pola cocok dengan command
   shell-nya. Pakai `process_manage kill` dengan `session_id`.

## Pelajaran dari 2B (jangan diulang)

7. **Test yang memilih "item pertama" dari endpoint list itu flaky.** `ORDER BY created_at DESC`
   beresolusi **detik**, jadi dua produk yang dibuat dalam detik yang sama urutannya tidak
   pasti. Test 2A dulu ambil `products[0]` dan berasumsi produk itu punya gambar utama —
   begitu test 2B bikin produk baru, asumsi itu pecah. **Pilih item berdasarkan sifat yang
   diuji** (`next(p for p in products if p['image'] != url)`), bukan berdasarkan posisi.
8. **Test harus idempoten.** Jalankan suite 2× berturut-turut di DB yang sama — kalau hasilnya
   beda, test-nya yang salah, bukan kodenya. Bukti: 117/117 dua kali berturut-turut.
9. **Produk buatan test sebaiknya `status: 'draft'`.** Produk `active` muncul di `/api/products`
   dan menggeser asumsi test lain. `draft` tetap bisa dites (endpoint admin tidak filter status).
10. **Negative control wajib: rusak → restart → test.** Kalau kode rusak crash saat start,
    semua hasil jadi `000` (koneksi gagal) dan itu **bukan** bukti — test tidak pernah jalan.

## Pelajaran dari 2C (jangan diulang)

11. **Hapus baris yang direferensikan `NOT NULL` tanpa `ON DELETE` = katalog bisa hilang.**
    `products.category_id` NOT NULL; menghapus kategori yang dipakai tidak error di SQLite
    (FK tidak dipaksa), tapi `JOIN categories` di `productSelect` langsung membuang **semua**
    produk → `/api/products` balikin 0. Selalu hitung pemakai SEBELUM hapus.
12. **`PATCH` yang bisa melanggar UNIQUE wajib dibungkus `try/catch`.** Versi lama
    `PATCH /admin/categories/:id` tidak menangkap error → slug bentrok = **500**, bukan 409.
13. **Jangan pakai `window.prompt`/`confirm` di CMS.** Itu keluar dari design system,
    tidak bisa ditata, dan memblokir. Edit langsung di baris.
14. **Satu endpoint ringkasan (`/admin/catalog` + `usage_count`) lebih baik daripada dua
    daftar + hitung di browser** — hitungannya ikut transaksi yang sama, jadi tidak basi.

---

## Pelajaran dari 2D (jangan diulang)

15. **`sql.js` MELEMPAR kalau ada parameter `undefined`** (`statement.bind` → `undefined`).
    Jangan pernah mengoper nilai `req.body` yang mungkin tidak ada langsung ke `run()`/`all()`.
    Normalkan ke `null` dulu. Bug ini diam-diam membuat `PATCH /admin/inventory/:id` **selalu
    500** saat cuma kirim `stock` — tombol "Simpan" di panel varian tidak pernah bekerja, dan
    tidak ada yang sadar karena UI-nya hanya menampilkan pesan sukses palsu. **Selalu kirim
    body yang benar-benar diuji, bukan yang "seharusnya".**
16. **Hitung di server, sekali saja.** `low_stock` dihitung di `serializeProduct`; UI varian
    awalnya menghitung ulang di browser (`available_stock <= threshold`) — itu dua rumus untuk
    satu fakta, dan cepat atau lambat akan berbeda. Server mengirim `low_stock` boolean; UI
    cuma menampilkan.
17. **Batas "menipis" adalah `<=`, bukan `<`.** Stok 5 dengan ambang 5 **sudah** menipis. Ini
    persis jenis kesalahan yang tidak kelihatan sampai ada yang kehabisan stok.
18. **Komentar `//` di tengah baris bisa mematikan sisa baris itu.** `server/index.js` gaya
    satu-baris-per-handler: menempelkan `// komentar` di tengah handler membuat semua kode
    sesudahnya jadi komentar → `node --check` gagal "Unexpected end of input". Taruh komentar
    di baris sendiri.
19. **Kalau `node --check` bilang sintaks rusak, cari dulu apakah itu regresi kita** — bandingkan
    `git show HEAD:file` vs working dengan tokenizer sederhana (kurung/literal/komentar
    seimbang). Di sini pengeceknya menemukan kurung yang "masih terbuka" di baris yang tepat.

---

## Pelajaran dari 2E (jangan diulang)

20. **Grid `1fr 1fr` MELEBAR kalau isinya input.** Input punya lebar intrinsik (~20 karakter);
    `1fr` = `minmax(auto, 1fr)`, dan `auto` tidak mau menyusut di bawah lebar intrinsik →
    kolom memaksa halaman melebar (di sini **82px di layar 360px**). Pakai
    **`minmax(0, 1fr)`**, dan untuk baris grid yang lebih rumit tambahkan `min-width: 0`
    pada anaknya. Ini jenis bug yang tidak kelihatan di desktop dan baru muncul di HP.
21. **Uji lebar layar dengan emulasi CDP, bukan `window.resizeTo`.** `resizeTo` diabaikan
    browser (viewport tetap 1280) → kesimpulan "aman" palsu. `Emulation.setDeviceMetricsOverride`
    baru berlaku setelah beberapa ratus milidetik — **tunggu sampai `innerWidth` benar-benar
    berubah**, jangan asumsi. Tanpa itu, pengukuran pertama selalu bohong.
22. **Cek dulu apakah bug itu regresi kita.** Sebelum memperbaiki overflow 360px, `git show
    HEAD:admin-products.html` dibandingkan: `.table-wrap` sudah ada di dalam grid `.admin-stack`
    sejak sebelum 2E. Tahu itu bukan regresi mengubah keputusan (tetap diperbaiki, tapi tidak
    menyalahkan perubahan sendiri).
23. **Panel tab jangan dibuat ulang saat pindah.** Cukup `hidden` + `display:none`. Kalau panel
    dibangun ulang, teks yang sedang diketik hilang dan halaman berkedip.
24. **`hidden` di HTML statis + `display:grid` di CSS saling membatalkan.** Aturan
    `.admin-panel[hidden]{display:none}` **wajib ada** setelah aturan grid, kalau tidak panel
    yang seharusnya sembunyi tetap tampil. (Ini juga yang diuji negative control 10a.)

---

## Out of scope (jangan dikerjakan di sini)

- Harga asli (masih placeholder) — keputusan user, terpisah.
- Editor konten beranda / taruh WA (itu Fase 3).
- Halaman pelanggan, export CSV, grafik penjualan (Fase 4).
- Pembayaran (paling akhir).
- Ganti backend/framework.

---

## Pertanyaan yang butuh jawaban sebelum mulai

1. **Mulai dari mana?** → ✅ **2A (upload gambar) dulu.**
2. **Gambar disimpan di mana?** → ✅ **Server** (`public/uploads/`).
3. **Gambar di-commit ke git?** → ✅ **Tidak** — masuk `.gitignore`, plus skrip backup
   terpisah (karena repo publik dan server bisa rusak).

**Disetujui 2026-10-01.** Mulai dari 2A.
