# 0012 — CMS siap terima produk

Status: ✅ **SELESAI** 2026-10-01 — 315/315 hijau (13 suite) · NC 11 + 2 + 1 · LIVE
Tanggal: 2026-10-01
Latar: hasil audit `plans/0011-audit-cms.md`. User: *"data produk dari gw belom ada,
sengaja gw mulai dulu CMS belakang biar nanti kalo ada data produk beneran gw tinggal
upload aja produknya."*

---

## Masalah

### 1. 🚨 Tombol "Buat produk" SELALU GAGAL (blocker)

`POST /api/admin/products` mewajibkan 11 field, form CMS hanya punya 10.
Yang kurang: **`recommended_usage`**.

**Dibuktikan di throwaway:**
```
Submit persis field form  → HTTP 400 {"error":"Field produk belum lengkap"}
+ recommended_usage       → HTTP 201 ✅
```

**Kenapa lolos sampai sekarang:** semua test (`bulk-price`, `low-stock`, `uploads`)
memanggil API **langsung** dan **selalu mengirim `recommended_usage`**. Tidak ada test
yang memeriksa **form HTML**. Jadi API hijau, tapi form rusak — dan katalog yang ada
sekarang isinya hasil seed, bukan input admin, sehingga tak ada yang menyadari.

**Kecurigaan tambahan:** label field `description` di form berbunyi
**"Deskripsi / penggunaan"** — admin wajar mengira itu sudah "penggunaan",
padahal `recommended_usage` adalah field lain yang tidak ada sama sekali.

### 2. 4 field produk lain tidak bisa diisi dari form

| Field | Ada di DB/API | Kepakai di frontend | Bisa diisi form |
|---|---|---|---|
| `recommended_usage` | ✅ | ✅ kartu katalog (`store.js`) | ❌ |
| `moq` | ✅ | ✅ halaman produk (min qty, `store.js`) | ❌ |
| `featured` | ✅ | ✅ urutan `/api/products` (`ORDER BY featured DESC`) | ❌ |
| `sample_available` | ✅ | ⚠️ hanya badge statis di beranda | ❌ |
| `bestseller` | ✅ | ❌ tidak dipakai di mana pun | ❌ |

Artinya: admin **tak bisa** atur minimum order, tak bisa tandai produk unggulan,
tak bisa atur produk mana yang boleh diminta sample.

### 3. Pesan error tidak berguna

`"Field produk belum lengkap"` tidak menyebut field mana yang kurang → admin buta.

---

## ⚠️ Keputusan penting: beranda JANGAN dibikin dinamis dulu

Beranda (`index.html`) sekarang **statis**: 11 kartu `<article class="card">` hardcode,
**0 panggilan API**. Kalau `featured` mau kelihatan di beranda, beranda harus dibikin
render dari `/api/products` — itu **pekerjaan besar** (ubah markup, filter GSAP, CSS),
dan **di luar** tujuan user ("siap terima produk").

**Keputusan:**
- Plan ini **hanya** mengerjakan form produk (CMS).
- `featured` tetap diisi dari CMS, dan **efeknya sudah nyata di `/katalog`**
  (urutannya naik — `store.js` sudah pakai `/api/products` yang `ORDER BY featured DESC`).
- Beranda dinamis = **plan terpisah** (Fase 3), bukan sekarang.

---

## Perubahan

### A. Form produk — tambah field yang kurang (`admin-products.html`)

Di dalam `#product-form`, setelah blok `description`:

| Field baru | Kontrol | Default | Kenapa |
|---|---|---|---|
| `recommended_usage` | `<input>` teks, **wajib** | — | **Blocker.** Dipakai kartu katalog |
| `moq` | `<input type=number min=1>` | `1` | Dipakai halaman produk (min qty) |
| `sample_available` | `<select>` Bisa / Tidak | Bisa | Fitur sample B2B |
| `featured` | `<select>` Ya / Tidak | Tidak | Naikkan urutan di `/katalog` |
| `bestseller` | `<select>` Ya / Tidak | Tidak | Tandai terlaris |

**Kenapa `<select>` Bisa/Tidak, bukan checkbox:** nilai form dibaca pakai
`Object.fromEntries(new FormData(...))` — checkbox yang tidak dicentang **tidak ikut
terkirim**, jadi butuh penanganan khusus. `<select>` selalu terkirim ("1"/"0") →
nol perubahan logika JS. Konsisten dengan pola `status` yang sudah ada.

**Perbaikan label:** label `description` diubah dari "Deskripsi / penggunaan" →
**"Deskripsi"**, supaya tidak tertukar dengan `recommended_usage`
("Rekomendasi pemakaian").

### B. Pesan error menyebut field yang kurang (`server/index.js`)

`POST /api/admin/products` sekarang:
```js
if (!a || !b || ...) return res.status(400).json({ error: 'Field produk belum lengkap' });
```
Diubah: kumpulkan **daftar** field yang kosong, sebut di pesan + kirim array `missing`.
```js
const required = { category_id:'Kategori', name:'Nama', slug:'Slug', sku:'SKU',
  description:'Deskripsi', material:'Material', construction:'Construction',
  gsm:'GSM', width:'Lebar', weight_per_yard:'Berat/yard',
  recommended_usage:'Rekomendasi pemakaian' };
const missing = Object.keys(required).filter((k) => !req.body?.[k]);
if (missing.length) return res.status(400).json({
  error: `Field belum lengkap: ${missing.map((k) => required[k]).join(', ')}`,
  missing
});
```
Perilaku status tetap **400** (test lama tidak rusak); hanya pesannya jadi berguna.

### C. Tampilkan pesan error itu di CMS (`admin-products.js`)

`bindProductForm` sekarang menampilkan pesan sukses/gagal. Pastikan jalur **gagal**
menampilkan `error.message` dari server (yang sekarang sudah menyebut field), bukan
pesan generik.

### D. Test baru: form vs API harus cocok (`tests/product-form.test.sh`)

**Ini penjaga sebenarnya** — supaya bug "field API tidak ada di form" tidak terulang.

1. **Statis:** ekstrak semua `name="..."` dari `#product-form` di `admin-products.html`;
   ekstrak daftar field wajib dari `POST /api/admin/products` di `server/index.js`.
   **Assert setiap field wajib ada di form.** → GAGAL di kode sekarang (bukti NC).
2. **Fungsional:** login admin, POST persis payload yang bisa dihasilkan form →
   harus **201**. → GAGAL di kode sekarang (400).
3. Field baru (`moq`, `sample_available`, `featured`, `bestseller`) terkirim & tersimpan.
4. `moq` < 1 ditolak / dinormalkan ke 1.
5. Pesan 400 menyebut nama field yang kurang.

---

## Acceptance criteria

- [x] Form "Buat produk" punya **semua 11 field wajib** API
- [x] POST payload persis dari form → **201** (bukan 400)
- [x] 5 field baru bisa diisi & tersimpan; terlihat saat edit/reload
- [x] Pesan 400 menyebut field yang kurang (bukan generik)
- [x] `moq` default 1, tidak bisa 0/negatif
- [x] Test baru GAGAL di kode lama, LULUS di kode baru (negative control 11 + 2 + 1)
- [x] Suite penuh **315/315** & idempoten 2 putaran
- [x] `admin-products.html` + `store.css` tetap CRLF (store.css tidak disentuh)
- [x] Nol endpoint baru, nol halaman baru, nol perubahan DB schema

## ⚠️ Temuan susulan saat implementasi (tidak terduga)

**Bug `event.currentTarget` jadi `null` setelah `await`** — kena **4 handler**:
`#product-form`, `#category-form`, `#color-form`, `#variant-form` (admin) +
`#address-form` (pelanggan, `account.js`).

Selama ini **tersembunyi** karena form produk selalu gagal 400 → baris `reset()` tidak
pernah tercapai. Setelah blocker diperbaiki, produk berhasil dibuat → `reset()` tercapai →
**muncul**: produk tersimpan **tapi UI bilang gagal** (`Cannot read properties of null`).

Ketemu lewat **uji browser ujung-ke-ujung**, bukan lewat unit test. Pelajaran: setelah
memperbaiki blocker, **uji ulang alur penuh** — bug berikutnya bisa bersembunyi di baliknya.

### ⚠️ Flag boolean dari form = string (temuan tambahan)

`<select>` mengirim `"0"`; `"0"` itu **truthy** → `featured ? 1 : 0` mengubah "Tidak"
jadi `1`. Ditutup dengan `flagValue()` di server. Dibuktikan NC: balikkan hanya
normalisasi itu → cek 10 & 13 GAGAL.

## Verifikasi lengkap

| Uji | Hasil |
|---|---|
| Suite baru `product-form` | **19/19** |
| Suite penuh 13 suite | **315/315**, suite_rc=0 |
| Idempoten 2 putaran (reset DB) | lihat `logs/2026-10-01_cms-siap-terima-produk.md` |
| NC-1 kode lama (`HEAD`) | **GAGAL 11** ✅ |
| NC-2 flag dinormalkan cara lama | **GAGAL 2** (cek 10 & 13) ✅ |
| NC-3 `currentTarget` dibalik | **GAGAL 1** (cek 16) ✅ |
| Browser: form produk | "Produk berhasil dibuat." · DB moq=5, sample=0, featured=1 ✅ |
| Browser: form varian | varian tersimpan, form direset ✅ |
| Browser: form kategori & warna | "berhasil ditambahkan." ✅ |
| Browser: form alamat pelanggan | alamat tersimpan, 0 error console ✅ |

## Yang TIDAK dikerjakan (sengaja)

- ❌ Beranda dinamis (Fase 3, plan terpisah)
- ❌ `payments.status` sinkron (temuan #1 di 0011) — beda plan
- ❌ Ongkir satu rumus (temuan #2) — beda plan
- ❌ Sample request form di storefront (temuan #3) — beda plan
- ❌ Kelola pelanggan / export CSV / notifikasi

## Perkiraan dampak file

| File | Perubahan |
|---|---|
| `admin-products.html` | +5 field, ubah 1 label |
| `server/index.js` | pesan error 400 lebih informatif |
| `admin-products.js` | tampilkan pesan error dari server |
| `tests/product-form.test.sh` | **baru** |
| `tests/responsive.test.sh` / `mobile-cms.test.sh` | mungkin +cek form baru tetap rapi di HP |
| `plans/0012-cms-siap-terima-produk.md` | dokumen ini |
| `docs/api.md` | catatan pesan 400 |
| `plans/README.md`, `plans/ROADMAP.md`, `HANDOFF.md` | status |

**Nol endpoint baru. Nol halaman baru. Nol perubahan schema.**
