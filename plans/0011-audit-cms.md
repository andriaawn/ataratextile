# 0011 — Audit CMS: apa yang masih kurang

Status: 📋 **LAPORAN AUDIT** (belum ada implementasi — tunggu pilihan user)
Tanggal: 2026-10-01
Permintaan user: "Audit dulu — cek apa lagi yang masih kurang di CMS"

Metode: **diukur, bukan ditebak.** Inventaris halaman/endpoint/tabel, bandingkan
yang tampil di storefront vs yang bisa dikelola CMS, cek data produksi langsung.

---

## Ringkasan

| Tingkat | Jumlah | Inti |
|---|---|---|
| 🚨 **Blocker** | 1 | **tambah produk baru SELALU GAGAL 400** — inti CMS rusak |
| 🔴 **Bug nyata** | 2 | data pembayaran tidak sinkron · ongkir 2 rumus (pelanggan lihat harga beda) |
| 🔴 **Jalur mati** | 2 | sample request hidup tapi tak ada pemanggil · 5 field produk mati |
| 🟠 **Kosong** | 3 | kelola pelanggan · export CSV · notifikasi |
| 🟡 **Basi** | 1 | ROADMAP masih tandai item yang sudah selesai |

Yang **sudah bagus** (jangan disentuh): varian+harga · gambar · kategori/warna ·
order · ganti password · responsif · tutup panel. **53 endpoint API**, **296/296 test**.

---

## 🚨 0. TEMUAN KRITIS: **tambah produk baru SELALU GAGAL** — inti CMS rusak

**Ini temuan terpenting, dan langsung menghancurkan tujuan yang user sebutkan**
("nanti kalau ada data produk beneran gw tinggal upload aja produknya").

`POST /api/admin/products` mewajibkan **11 field**, tapi form CMS hanya punya **10**:

| Field wajib | Ada di form? |
|---|---|
| category_id, name, slug, sku, description, material, construction, gsm, width, weight_per_yard | ✅ |
| **`recommended_usage`** | ❌ **TIDAK ADA DI MANA-MANA** — bukan di HTML, bukan di JS |

**Dibuktikan di throwaway (bukan teori):**

```
Submit persis field yang ada di form  → HTTP 400 {"error":"Field produk belum lengkap"}
Tambah recommended_usage              → HTTP 201, produk dibuat
```

**Akibat:** admin **tidak akan pernah bisa menambah produk** lewat CMS. Isi katalog
sekarang (11 produk) itu hasil **seed**, bukan input admin — makanya bug ini belum terlihat.

Begitu user punya data produk asli dan mau upload, **tombol "Buat produk" akan selalu gagal
400** — dan pesannya ("Field produk belum lengkap") **tidak menyebut field mana** yang kurang,
jadi user akan bingung.

**Effort perbaikan: XS** — tambah 1 field di form + pastikan terkirim. Tapi dampaknya
**memblokir seluruh alur kerja yang direncanakan user.**

**Catatan:** endpoint `PATCH` (edit) **tidak** mewajibkan field ini, jadi **edit produk lama
tetap jalan** — hanya **buat baru** yang rusak.

---

## 🔴 1. `payments.status` tidak pernah disinkronkan — KPI dashboard salah

**Bukti dari data produksi:**

```
orders.status   : (5, 'refunded')
payments.status : (5, 'pending')     ← TIDAK SINKRON
```

Endpoint `PATCH /api/admin/orders/:id` meng-update **`orders`** dan **`shipments`**,
tapi **tidak** `payments`. Padahal KPI dashboard menghitung:

```js
pendingPayments: COUNT(*) FROM payments WHERE status='pending'
```

**Akibat:** order yang sudah `refunded`/`paid`/`cancelled` **tetap dihitung** sebagai
"Menunggu bayar". Angka di dashboard **bohong** — dan itu angka yang dilihat pemilik toko
untuk memutuskan.

**Catatan:** ini melanggar prinsip yang sudah kita pegang — *"fakta yang sama dihitung
SERVER, satu rumus"* (plan 2D). Status bayar punya dua sumber, dan keduanya bisa berbeda.

---

## 🔴 2. Ongkir punya DUA rumus — pelanggan lihat harga beda dari yang ditagih

| Tempat | Rumus |
|---|---|
| `store.js` (yang **dilihat** pelanggan) | `subtotal + 35000` — flat, hardcode |
| `server/services.js` (yang **ditagih**) | `base + (qty-1) × 5000`, Jakarta 18000 / lain 35000 |
| `checkout.html` | menampilkan **"Rp 35.000"** mati |

**Contoh nyata:** beli **3 roll** kirim ke **Jakarta**
- Pelanggan lihat: subtotal + **Rp 35.000**
- Server tagih: subtotal + 18.000 + (3−1)×5.000 = subtotal + **Rp 28.000**
- **Beda Rp 7.000** — dan pelanggan sudah melihat angka yang salah sebelum menekan "Buat pesanan"

Server juga sudah punya endpoint `GET /api/shipping/quote` yang **tidak dipanggil** checkout.

**Akibat:** pelanggan bisa komplain (atau batal) karena total berubah dari yang dia lihat.

---

## 🔴 3. Sample request: endpoint hidup, tapi TIDAK ADA yang bisa memakainya

| Bagian | Status |
|---|---|
| Tabel `sample_requests` | ada |
| `POST /api/samples` | **hidup** (live: 400 kalau body kosong, bukan 404) |
| KPI `dashboard.samples` | server **mengirim** |
| Form di storefront | **⚠️ TIDAK ADA** — nol pemanggil `/api/samples` |
| Dashboard merender `samples` | **⚠️ TIDAK** — cuma 4 KPI, `samples` diabaikan |
| Halaman admin melihat sample | **⚠️ TIDAK ADA** |

**Akibat:** fitur "minta sample kain" (penting untuk B2B tekstil — pembeli biasanya minta
contoh dulu sebelum order roll) **tidak bisa dipakai sama sekali**. Backend sudah siap;
tinggal UI-nya.

Ini persis prinsip yang kita pegang: *"kalau tidak nyambung, lepaskan — jangan menyambungkan
jalur mati agar terlihat selesai."* Sekarang jalur ini **setengah hidup** dan lebih buruk
daripada tidak ada: ada KPI yang selalu 0, ada endpoint yang tak terjangkau.

---

## 🔴 4. Lima field produk ada di DB + API, tapi tidak bisa dikelola & tidak dipakai

| Field | Di DB | Bisa di-PATCH API | Ada di form CMS | Dipakai frontend |
|---|---|---|---|---|
| `featured` | ✅ | ✅ | ❌ | ❌ |
| `bestseller` | ✅ | ✅ | ❌ | ❌ |
| `sample_available` | ✅ | ✅ | ❌ | ❌ |
| `recommended_usage` | ✅ | ✅ | ❌ | ❌ |
| `moq` | ✅ | ✅ | ❌ | ❌ |

**Akibat:** admin tidak bisa menandai produk unggulan/bestseller, tidak bisa mengatur
"bisa minta sample", tidak bisa menulis rekomendasi pemakaian, tidak bisa set MOQ —
padahal kolomnya ada dan API-nya menerima. Beranda punya section "Lihat Koleksi" yang
mestinya bisa diisi produk unggulan.

---

## 🟠 5. Tidak ada halaman kelola pelanggan

- Tabel `customers`: **2 baris** di produksi · `addresses`: 1
- Endpoint admin: **0**
- Halaman: **0**

Admin tidak bisa melihat daftar pelanggan, riwayat pesanan mereka, atau siapa yang
pernah order. Untuk toko B2B, "siapa pelanggan saya" itu informasi dasar.

---

## 🟠 6. Tidak ada export CSV

- `grep -ci csv server/index.js` → **0**

Rekap pesanan untuk pembukuan harus disalin manual dari tabel. Trigger di roadmap:
"saat pembukuan bulanan" — dan itu akan datang.

---

## 🟠 7. Tidak ada notifikasi keluar

`NotificationService.emit('new_order' | 'sample_request', …)` dipanggil di 2 tempat,
tapi **tidak ada penerima** — nol email, nol WA. Kalau ada order masuk, admin tidak
diberi tahu kecuali membuka dashboard.

Catatan: nomor WA bisnis **sengaja dihapus** dari frontend (keputusan lama). Jadi
notifikasi harus lewat kanal lain (email/Telegram), bukan WA publik.

---

## 🟡 8. Roadmap basi

`plans/ROADMAP.md` masih menandai sebagai TODO:
- "Upload gambar produk" → **SELESAI** (Fase 2A)
- "Kelola kategori & warna" → **SELESAI** (Fase 2C)

Ini menyesatkan sesi berikutnya. Perbaikan 2 menit.

---

## Usulan prioritas (DIREVISI setelah tahu konteks user)

Konteks user: *"data produk dari gw belom ada. jadi emang sengaja gw mulai dulu CMS
belakang biar nanti kalo ada data produk beneran gw tinggal upload aja produknya."*

Artinya yang paling penting bukan fitur tambahan, tapi: **CMS harus benar-benar siap
menerima data produk.**

| # | Kerjaan | Effort | Kenapa duluan |
|---|---|---|---|
| **0** | **🚨 Betulkan tombol "Buat produk"** (tambah `recommended_usage`) | **XS** | **Tanpa ini, upload produk MUSTAHIL.** Blocker. |
| **E** | **5 field produk** (featured/bestseller/sample/MOQ/rekomendasi) | S | Biar upload produk **sekali jadi**, nggak perlu revisi |
| **A** | Sinkronkan `payments.status` + betulkan KPI | S | Angka dashboard bohong (ada bukti data rusak) |
| **B** | Ongkir satu rumus | S | Pelanggan lihat harga beda dari tagihan |
| **C** | Harga asli | S | ⚠️ butuh data dari user |
| **D** | Sample request nyambung | M | Fitur B2B sudah 80% |
| **F** | Kelola pelanggan | S | Info dasar |
| **G** | Export CSV | S | Pembukuan |
| **H** | Notifikasi order masuk | M | Perlu pilih kanal |
| **I** | Rapikan roadmap | XS | 2 menit |

### 💡 Saran gw: **0 + E dulu** (satu plan: "CMS siap terima produk")

Alasannya langsung dari konteks user:
- **0** = blocker mutlak — tanpa ini upload produk tidak mungkin
- **E** = kalau nanti user upload 20 produk lalu baru sadar "oh nggak ada field MOQ /
  unggulan", dia harus **edit 20 produk satu-satu**. Jauh lebih murah membereskan
  **sebelum** data masuk.

Setelah itu **A + B** (bug nyata, ada bukti), lalu C/D.

**Kenapa A+B tidak nomor satu:** keduanya menyentuh order & pembayaran — dan **belum ada
transaksi nyata** (1 order uji). Sementara 0 memblokir hal yang user **sedang** persiapkan.

---

## Yang TIDAK diusulkan (sudah benar / sudah ditolak)

- Pindah framework/CMS — sudah ditolak di `ROADMAP.md`, alasan masih sah
- Editor drag-and-drop — ditolak
- SQLite → Postgres, Cloudinary — ditunda dengan trigger jelas (`BACKLOG.md`)
- Multi-bahasa, afiliasi, marketplace — ditunda

## Out of scope audit ini

Audit **tidak** mengubah kode apa pun. Semua temuan di atas **belum diperbaiki**.
