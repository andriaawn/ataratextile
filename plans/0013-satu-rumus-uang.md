# 0013 — Satu rumus untuk uang: `payments.status` sinkron + ongkir & subtotal dari server

**Status:** MENUNGGU APPROVE
**Tanggal:** 2026-10-07
**Latar:** temuan `plans/0011-audit-cms.md` #1 & #2 (dua bug 🔴 ada bukti data produksi).
Sumber tambahan: research API ongkir 2026-10-07 (RajaOngkir/Biteship/KiriminAja).

> Prinsip yang dipakai: **"fakta yang sama dihitung SERVER, satu rumus"** (plan 2D).

---

## Masalah

### 🔴 A. `payments.status` tidak pernah disinkronkan → KPI dashboard bohong

Bukti dari DB produksi (dicek ulang 2026-10-07):

```
order #5  : orders.status = 'refunded'
            payments.status = 'pending'   ← TIDAK SINKRON
```

`PATCH /api/admin/orders/:id` meng-update **`orders`** + **`shipments`**, tapi **tidak**
`payments`. Padahal KPI dashboard:

```js
pendingPayments: COUNT(*) FROM payments WHERE status='pending'
```

→ order yang sudah `refunded`/`paid`/`cancelled` tetap terhitung **"Menunggu bayar"**.

### 🔴 B. Ongkir dua rumus → pelanggan lihat beda dari tagihan

| Tempat | Rumus |
|---|---|
| `store.js` (dilihat pelanggan) | `subtotal + 35000` — flat, hardcode |
| `server/services.js` (ditagih) | Jakarta 18000 / lain 35000, `+ (qty-1)×5000` |
| `checkout.html` | "Rp 35.000" mati |

Contoh: 3 roll ke Jakarta → pelanggan lihat +35.000, ditagih +28.000 (**beda Rp7.000**).
Endpoint `GET /api/shipping/quote` **sudah ada** tapi tidak dipanggil checkout.

### 🟠 C. (temuan baru) Subtotal juga bisa beda — harga tier tidak dihitung di checkout

`renderCart` menghitung `subtotal` dari `item.price` di **localStorage** (harga saat
ditambahkan). Server menghitung ulang dengan **`price_tiers`** (`getPricing`):

| Qty | Harga localStorage | Harga server (tier) | Beda |
|---|---|---|---|
| 1–4 roll | 990.000 | 990.000 | — |
| 5–19 roll | 990.000 | **940.000** | 50.000/roll |
| 20+ roll | 990.000 | **900.000** | 90.000/roll |

Jadi beli 5 roll: pelanggan lihat 5×990.000 = 4.950.000, ditagih 5×940.000 = 4.700.000
(**beda Rp250.000**). Sama akarnya dengan B: **angka yang dilihat ≠ angka yang ditagih**.

---

## Research API ongkir (untuk keputusan: sekarang vs nanti)

| Penyedia | Gratis? | Ekspedisi | Catatan |
|---|---|---|---|
| **RajaOngkir Starter** | ✅ **100 hit/hari, lifetime** | 17 domestik (JNE/SiCepat/J&T/…) | Pro Rp149rb/bln. Milik Komerce |
| Biteship | ⚠️ bayar Rp5/hit | 30 kurir | nol langganan |
| KiriminAja | ❌ | 19 kurir | PRO Rp2,16jt/thn |

**Kesimpulan:** integrasi API real (RajaOngkir) butuh 4 hal yang **belum ada**:
API key, alamat asal gudang, mapping kota→city-ID (checkout masih teks bebas), dan
berat gram/unit (`weight_per_yard` masih teks "237 g/yard").
→ **Plan terpisah (0014).** Plan 0013 ini **tidak** menyentuh API eksternal.

---

## Solusi

### Fix A — sinkronkan `payments.status`

`server/index.js`, `PATCH /api/admin/orders/:id`: setelah update `orders`, selaraskan
`payments.status` dengan status order via **satu peta**:

```
order status        → payments.status
pending_payment     → pending
paid/processing/packed/shipped/completed → paid
cancelled/refunded  → refunded
```

Set `paid_at` saat pertama kali jadi `paid` (kalau masih NULL). Bungkus dalam
`transaction()` supaya atomik. Catat juga: `POST /api/dev/pay/:id` (mock) sudah benar —
tidak diubah.

**Satu peta di satu tempat** (fungsi `paymentStatusForOrderStatus(status)`), bukan
`if` tersebar — biar tidak ada dua sumber lagi.

### Fix B — satu rumus uang: `POST /api/checkout/quote`

Tambah endpoint yang menghitung **subtotal (dengan tier) + ongkir + total** dari
**server**, lalu checkout memakainya. Ini menyelesaikan B **dan** C sekaligus.

```
POST /api/checkout/quote
body: { items: [{variant_id, quantity}], city }
resp: { items: [{variant_id, product_name, variant_name, quantity, unit_price, subtotal}],
        subtotal, shipping: {method, cost, estimatedDays}, total }
```

- **Tanpa** efek samping: tidak membuat order, tidak menyentuh stok, tidak butuh login.
- Logika item = **fungsi bersama** dengan `POST /api/orders` (ekstrak `expandItems()`),
  supaya quote & order **tidak mungkin beda** — itu inti bug ini.
- Frontend `store.js`: `renderCart` async memanggil quote (pakai kota yang diketik),
  lalu menampilkan subtotal/ongkir/total dari server. Nol angka hardcode.
- `checkout.html`: hapus "Rp 35.000" mati → placeholder "—" yang diisi JS.
- Kota berubah → hitung ulang (event `input`/`change` di field `city`, di-debounce).

**Kalau quote gagal** (mis. jaringan): tampilkan pesan "Ongkir belum bisa dihitung",
**jangan** tampilkan angka tebakan, dan tombol "Buat pesanan" tetap bisa ditekan
(server tetap hitung sendiri saat order dibuat — server yang menang).

---

## Test (TDD — bukti GAGAL dulu)

`tests/order-sync.test.sh` (BARU):
- A1. PATCH order → `paid` → `payments.status='paid'`, `paid_at` terisi
- A2. PATCH order → `refunded` → `payments.status='refunded'`
- A3. PATCH order → `cancelled` → `payments.status='refunded'`
- A4. KPI `pendingPayments` turun setelah order di-refund (bukti angka bohong hilang)
- A5. status tidak dikenal → tetap 400 (tak ada regresi)

`tests/checkout-quote.test.sh` (BARU):
- B1. quote 3 roll ke Jakarta → ongkir = 18.000 + 2×5.000 = **28.000**
- B2. quote 1 roll ke Bandung → ongkir = **35.000**
- B3. **quote.total == order.total** (3 roll Jakarta) → beda **0** (inti bug)
- B4. quote 5 roll → subtotal pakai harga **tier** (940.000), bukan 990.000
- B5. quote tanpa membuat order (COUNT orders tidak berubah)
- B6. quote tidak menyentuh reserved_stock
- B7. variant tidak aktif / qty > stok → 400

`tests/checkout-ui.test.sh` (BARU, cek HTML/JS statis):
- C1. `store.js` **tidak** mengandung `35000` hardcode di jalur checkout
- C2. `checkout.html` tidak ada "Rp 35.000" mati
- C3. `store.js` memanggil `/checkout/quote`

**Negative control:** jalankan test terhadap kode `HEAD` → A1–A5 & B1–B7 **GAGAL**
(atau endpoint 404). Simpan output sebagai bukti.

## Acceptance (terukur)

1. Full suite lama (13 suite, 296 test) tetap hijau + 3 suite baru hijau.
2. Bukti GAGAL di `HEAD` (negative control) tersimpan di log.
3. Data produksi diperbaiki: order #5 → `payments.status='refunded'`
   (setelah deploy, lewat PATCH yang sama — bukan edit DB manual).
4. Live: checkout 3 roll Jakarta → total di layar **=** total di order (selisih 0).
5. KPI "Menunggu bayar" di dashboard = jumlah order yang **benar-benar** belum bayar.

## Yang TIDAK diubah

- Rumus ongkir manual itu sendiri (`services.js`) — **tetap** satu-satunya rumus.
- `weight_per_yard`, tier pricing di DB, alur pembayaran manual.
- Tidak menambah dependency baru. Tidak menyentuh port 80 / tunnel.

## Setelah ini

- **0014** — integrasi RajaOngkir (butuh: API key, alamat asal, mapping kota, berat gram).
- Harga asli (placeholder `825000 + gsm*1000`) — nunggu data dari user.
