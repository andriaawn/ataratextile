# 0015 — Sample request: sambungkan jalur yang sudah setengah hidup

**Status:** MENUNGGU APPROVE
**Tanggal:** 2026-10-07
**Latar:** temuan `plans/0011-audit-cms.md` #3. Fitur "minta sample kain" **penting untuk
B2B tekstil** (pembeli minta contoh dulu sebelum order roll), dan backend-nya **sudah 80%
siap** — tapi nol UI, jadi tidak bisa dipakai sama sekali.

## Bukti kondisi sekarang (terukur)

| Bagian | Status |
|---|---|
| Tabel `sample_requests` | ✅ ada (id, customer_name, email, phone, product_id, color, quantity, address, status, created_at) |
| `POST /api/samples` | ✅ **hidup** (live → 400 kalau body kosong, bukan 404) |
| `notifications.emit('sample_request')` | ✅ dipanggil |
| KPI `dashboard.samples` | ✅ server mengirim |
| Form di storefront | ❌ **nol pemanggil** `/api/samples` |
| Dashboard merender `samples` | ❌ cuma 4 KPI, `samples` diabaikan |
| Halaman admin sample | ❌ tidak ada |

**Akibat:** jalur ini **setengah hidup** — lebih buruk daripada tidak ada: ada KPI yang
selalu 0, ada endpoint yang tak terjangkau. Melanggar prinsip *"kalau tidak nyambung,
lepaskan"*.

## Solusi (menyambungkan, bukan menambah fitur baru)

**A. Storefront — form "Minta sample" di halaman produk.**
- `store.js` `initProduct`: tambah tombol/blok "Minta sample" (muncul kalau
  `product.sample_available`). Klik → form inline (nama, email, WA, warna, qty, alamat) →
  `POST /api/samples`.
- Warna default = varian yang sedang dipilih. Produk tanpa `sample_available` → tidak
  tampil tombolnya.
- Sukses → pesan jujur ("Permintaan sample terkirim, kami hubungi via WA/email").
  Gagal → tampilkan pesan error server.

**B. Admin — halaman `/admin/sample`.**
- Endpoint baru: `GET /api/admin/samples` (adminOnly), `PATCH /api/admin/samples/:id`
  (ubah status).
- Halaman `admin-samples.html` + menu sidebar "Sample" di semua halaman admin.
- Kolom: tanggal · nama · kontak · produk · warna · qty · status · aksi ubah status.
- Status: `requested` → `contacted` → `sent` / `rejected`.

**C. Dashboard — KPI `samples` akhirnya tampil.**
- `loadAdminDashboard` tambah KPI ke-5 "Sample baru" = `dashboard.samples` (server sudah
  mengirim, tinggal dirender).

**D. Daftarkan halaman baru di 3 tempat** (pitfall wajib): `PAGES` di `server/index.js`,
`PAGES` di `vite.config.ts`, `build.rollupOptions.input`.

## File yang disentuh

- `server/index.js` — endpoint `GET/PATCH /api/admin/samples`, daftar `PAGES`.
- `store.js` — form sample di `initProduct`, KPI ke-5 di `loadAdminDashboard`.
- `admin-samples.html` — baru.
- `admin.html`, `admin-orders.html`, `admin-products.html` — menu sidebar "Sample".
- `vite.config.ts` — daftar halaman.
- Test baru: `tests/samples.test.sh`.

## Test (TDD, bukti GAGAL dulu)

- `samples.test.sh`
  1. `POST /api/samples` valid → 201 (sudah jalan, tapi dikunci sebagai regresi)
  2. `POST` body kosong → 400
  3. `GET /api/admin/samples` tanpa login → 401
  4. `GET /api/admin/samples` admin → 200 + berisi sample yang baru dibuat
  5. `PATCH /api/admin/samples/:id` ubah status → 200 + tersimpan
  6. status invalid → 400
  7. halaman `/admin/sample` dilayani (200)
  8. bundle store memuat form sample (`/samples`)
  9. dashboard merender KPI sample (markup `kpi`, bukan nama fungsi)
- **NC:** jalankan ke `HEAD` → test 3–9 GAGAL (endpoint & halaman belum ada).

## Acceptance (terukur)

1. `POST /api/samples` dari form storefront menghasilkan baris di `sample_requests` ✅
2. `GET /api/admin/samples` mengembalikan baris itu ✅
3. `/admin/sample` → 200, tampil di menu sidebar ✅
4. Dashboard punya KPI "Sample baru" (bukan 0 selalu karena diabaikan) ✅
5. Nol regresi (security/admin-orders/admin-ui/catalog) ✅
6. Nol dependency baru ✅

## Yang TIDAK diubah

- Skema `sample_requests` (sudah cukup).
- `POST /api/samples` (sudah benar).
- Notifikasi keluar (belum ada kanal — item terpisah).
- Pembayaran (sesuai keputusan user).
