# Design System — Admin CMS Atandra

**Terakhir diperbarui:** 2026-09-30
**Status:** kontrak desain — dipakai untuk SEMUA halaman admin
**Basis:** design language toko yang sudah ada, diukur ulang terhadap WCAG

> Dokumen ini adalah **kontrak**. Kalau sebuah halaman admin menyimpang dari sini, itu
> bug desain — bukan variasi. Tujuannya: halaman baru langsung konsisten tanpa menebak.

---

## 1. Prinsip

Admin ini masuk kategori **operational dashboard** (bukan analytical, bukan client-facing).
Bedanya penting:

| | Operational (ini) | Analytical | Client-facing |
|---|---|---|---|
| Pengguna | operator yang **bekerja** di dalamnya | pembaca laporan | pelanggan |
| Densitas | **padat itu fitur** | sedang | rendah |
| Ukuran sukses | **waktu sampai aksi pertama** | "paham tanpa nanya" | "paham dalam 3 detik" |

**Konsekuensinya, 5 prinsip:**

1. **Satu layar, satu jawaban.** Setiap halaman menjawab satu pertanyaan ("order mana yang
   perlu gw kerjakan hari ini?"). Bukan menampilkan 12 angka.
2. **Bikin aksi itu murah.** Kalau operator melakukan sesuatu 40× sehari, jangan sampai
   butuh 3 klik. Ubah status harus 2 klik, bukan buka halaman detail dulu.
3. **Warna hanya untuk makna.** Nol warna dekoratif. Warna = status, peringatan, atau aksi.
4. **Bukti > keyakinan.** Setiap aksi memberi umpan balik eksplisit ("Order #AT-20260930-0001
   → Dikirim ✅"), bukan diam.
5. **Hirarki dari tipografi & spasi, bukan dari kotak.** Kurangi border/shadow; pakai
   ukuran huruf, bobot, dan jarak untuk memisahkan.

**Yang sengaja TIDAK kita lakukan:**
- ❌ Editor visual drag-and-drop — rapuh, bikin HTML tak terawat
- ❌ "Wall of charts" — grafik cuma kalau menjawab pertanyaan
- ❌ Chrome dekoratif (gradien, animasi hiasan) yang bersaing dengan data
- ❌ Dark mode di iterasi pertama (ditunda — lihat §9)

---

## 2. Layout

**Pola: classic sidebar** (paling terbukti untuk navigasi dalam — dipakai hampir semua admin
panel; pengguna sudah tahu cara pakainya).

```
┌────────────┬─────────────────────────────────────────────────┐
│            │  Topbar: breadcrumb · search · user menu        │
│  Sidebar   ├─────────────────────────────────────────────────┤
│  240px     │  Page header: judul + aksi utama               │
│            ├─────────────────────────────────────────────────┤
│  Dashboard │  Filter bar                                     │
│  Pesanan ① │  ┌───────────────────────────────────────────┐  │
│  Produk    │  │  Tabel (surface utama)                    │  │
│  Pelanggan │  │                                           │  │
│  Konten    │  └───────────────────────────────────────────┘  │
│  Pengaturan│  Paginasi                                       │
└────────────┴─────────────────────────────────────────────────┘
```

| Breakpoint | Sidebar | Tabel |
|---|---|---|
| > 1024px | tetap 240px | kolom penuh |
| 768–1024px | ciut jadi ikon (56px) | scroll horizontal |
| < 768px | drawer (tombol menu) | kartu, bukan tabel |

**Maksimal 7 item menu.** Lebih dari itu → bingung. Sekarang: Dashboard · Pesanan ·
Produk · Pelanggan · Konten · Pengaturan (6).

**Pola tabel-first** untuk Pesanan & Produk (pola Stripe): tabel adalah pahlawan halaman;
KPI cuma ringkasan di atasnya, bukan acara utama.

---

## 3. Tipografi

**Pertahankan font yang sudah dipakai toko** — konsistensi lintas permukaan lebih penting
daripada ganti font. Ini juga sudah bagus: sans humanis (DM Sans) + display tegas (Manrope)
+ mono (DM Mono) untuk angka & label.

```css
--font-display: 'Manrope', system-ui, sans-serif;   /* judul, angka KPI */
--font-body:    'DM Sans', system-ui, sans-serif;   /* teks isi, tabel */
--font-mono:    'DM Mono', ui-monospace, monospace; /* label, SKU, angka tabular */
```

### Skala (basis 4px)

| Peran | Ukuran | Bobot | Font | Catatan |
|---|---|---|---|---|
| Judul halaman | 28px | 800 | Manrope | satu per halaman |
| Judul seksi | 18px | 700 | Manrope | |
| Judul kartu | 15px | 700 | Manrope | |
| Teks isi | 14px | 400 | DM Sans | ukuran default admin |
| Teks tabel | 13px | 400 | DM Sans | padat tapi terbaca |
| Label / meta | 10px | 500 | DM Mono | HURUF BESAR, letter-spacing .08em |
| Angka KPI | 30px | 700 | Manrope | `font-variant-numeric: tabular-nums` |

**Aturan angka:** semua uang, kuantitas, tanggal, dan nomor order pakai
**`font-variant-numeric: tabular-nums`** supaya kolom rata & gampang dibandingkan.
Harga pakai `DM Mono` di tabel.

**Baris tabel: 36px** (padat — operator scan, bukan membaca). Sel tabel 12px vertikal,
16px horizontal.

---

## 4. Warna

Palet brand dipertahankan, **2 warna diperbaiki karena gagal kontras** (diukur, bukan
dikira). **Sudah diterapkan di `store.css`** — satu titik ubah via token:

| Token | Sebelum | Sesudah | Kenapa |
|---|---|---|---|
| `--rust` | `#b9653b` | **`#a8562f`** ✅ diterapkan | 4.14 → **5.12** di paper; 3.71 → **4.59** di cream. Sekarang lolos AA untuk teks normal |
| `--muted` | `#687777` | **`#5c6a6a`** ✅ diterapkan | 4.12 → **4.97** di cream. Lolos AA di dua surface |

Sisanya sudah bagus dan dipertahankan (`ink` 14.8:1, `gold` di `ink` 7.3:1).

### Token semantik

```css
:root{
  /* surface */
  --bg:            #f7f8f6;   /* kanvas admin (bukan cream — lebih netral untuk kerja) */
  --surface:       #fffdf9;   /* kartu, tabel */
  --surface-raised:#ffffff;   /* modal, dropdown */
  --surface-sunken:#eef1ee;   /* header tabel, area tertekan */

  /* garis */
  --border:        #dfe3dc;
  --border-strong: #c6ccc4;

  /* teks */
  --text:           #132a2b;  /* 14.1:1 di --bg */
  --text-secondary: #5c6a6a;  /*  5.3:1 di --bg */
  --text-muted:     #63716f;  /*  5.01:1 di paper — placeholder/non-kritis (dulu #8a9694 = 3.01 ❌) */

  /* brand */
  --brand-deep: #0d3132;      /* sidebar, header gelap */
  --brand-ink:  #132a2b;
  --brand-gold: #e6a76d;      /* aksi utama di permukaan gelap */
  --accent:     #a8562f;      /* aksen teks, link, aktif */

  /* status (semua sudah diukur ≥4.5:1 dengan teks putih) */
  --status-pending:  #8a6d1f;  /* menunggu bayar — 4.90 */
  --status-paid:     #1f6b4a;  /* dibayar — 6.44 */
  --status-process:  #2c5f8a;  /* diproses — 6.75 */
  --status-packed:   #4a5578;  /* dikemas — 7.34 */
  --status-shipped:  #3d6b8a;  /* dikirim — 5.72 */
  --status-done:     #2f6b3f;  /* selesai — 6.37 */
  --status-cancel:   #7a4a4a;  /* dibatalkan — 7.23 */
  --status-refund:   #6b4a6b;  /* dikembalikan — 7.45 */

  --danger:  #a33a2f;   /* hapus, error */
  --success: #2f6b3f;
  --warning: #8a6d1f;
  --info:    #2c5f8a;
}
```

### Aturan warna

1. **Warna hanya untuk makna** — status, peringatan, aksi. Nol dekorasi.
2. **Jangan pakai warna sebagai satu-satunya penanda.** Badge status selalu ada teksnya
   ("Dikirim"), bukan cuma titik hijau. (Buta warna itu 8% populasi pria.)
3. **`--text-muted` jangan untuk teks penting** — cuma placeholder/ikon non-kritis.
   Sekarang `#63716f` (5.01:1) supaya kalau kepakai di luar niat pun tetap lolos AA.
4. **Kontras minimum: 4.5:1** untuk teks normal, 3:1 untuk teks besar/ikon.

### Badge status

Dua kelompok, satu kelas dasar `.badge` (teks putih, huruf kapital, monospace):

| Kelompok | Nilai | Kelas |
|---|---|---|
| Order | `pending_payment` `paid` `processing` `packed` `shipped` `completed` `cancelled` `refunded` | `.badge--<status>` |
| Produk | `active` `draft` `archived` `out_of_stock` | `.badge--<status>` |

Semua sudah diukur ≥4.5:1 dengan teks putih (§4). Status baru **wajib** ditambahkan ke
kelompok yang sesuai dan diukur kontrasnya sebelum dipakai.

```html
<span class="badge badge--shipped">Dikirim</span>
```
```css
.badge{display:inline-flex;align-items:center;gap:6px;padding:3px 9px;
       font:500 10px var(--font-mono);letter-spacing:.06em;text-transform:uppercase;
       color:#fff}
.badge--shipped{background:var(--status-shipped)}
```

---

## 5. Spasi

Basis **4px**. Skala: `4 · 8 · 12 · 16 · 20 · 24 · 32 · 40 · 56`.

| Konteks | Spasi |
|---|---|
| Padding sel tabel | 12px × 16px |
| Padding kartu | 20px |
| Jarak antar kartu | 16px |
| Padding halaman | 24px (desktop) / 16px (mobile) |
| Jarak sidebar item | 2px antar, 10px × 12px di dalam |
| Tinggi kontrol (input/tombol) | 36px |

**Radius: 0.** Konsisten dengan toko (kesan editorial/tekstil tegas). Modal & dropdown boleh
2px. **Nol shadow** kecuali modal/dropdown (1 lapis lembut).

---

## 6. Komponen

| Komponen | Aturan |
|---|---|
| **Sidebar** | 240px, bg `--brand-deep`, teks putih. Item aktif = bg `--surface` + teks `--brand-ink`. Badge angka untuk yang butuh perhatian (mis. Pesanan 3) |
| **Topbar** | 56px, bg `--surface`, border bawah. Breadcrumb kiri, search tengah, user kanan |
| **Page header** | Judul + deskripsi satu baris + **aksi utama di kanan** (mis. "Produk baru") |
| **KPI card** | Label mono kecil + angka besar tabular + delta opsional. **Selalu ada pembanding** ("+12% dari minggu lalu") — angka telanjang tanpa baseline itu hiasan |
| **Tabel** | Header `--surface-sunken`, teks mono kecil HURUF BESAR. Baris 36px, hover `--surface-sunken`. Kolom angka rata kanan. Sortable (indikator panah). Aksi baris = tombol teks, bukan ikon misterius |
| **Filter bar** | Baris kontrol di atas tabel: search, dropdown status, rentang tanggal, tombol reset. Filter aktif ditampilkan sebagai chip yang bisa dihapus |
| **Bulk action bar** | Muncul dari bawah begitu ada baris dicentang: "3 dipilih · Ubah status · Ekspor" |
| **Badge** | Lihat §4. Selalu ada teks |
| **Modal** | Hanya untuk konfirmasi destruktif & form pendek. **Selalu** ada tombol batal. Fokus terkunci di dalam |
| **Toast** | Muncul kanan bawah, hilang 4 detik. Sukses = hijau, error = merah. **Setiap aksi wajib ada toast** |
| **Empty state** | Ilustrasi/ikon + kalimat penjelas + **tombol aksi**. "Belum ada pesanan. Pesanan yang masuk akan muncul di sini." — bukan tabel kosong |
| **Form** | Label di atas input (bukan placeholder sebagai label). Error di bawah field, warna `--danger`. Field wajib ditandai |
| **Skeleton** | Saat memuat, pakai blok abu berdenyut — **bukan spinner**. Cegah lompatan layout |

---

## 7. Status order — alur & warna

```
pending_payment ──> paid ──> processing ──> packed ──> shipped ──> completed
   (menunggu)      (dibayar)  (diproses)   (dikemas)   (dikirim)   (selesai)
        │              │           │            │           │
        └──────────────┴───────────┴────────────┴───────────┴──> cancelled (dibatalkan)
                                                             └──> refunded (dikembalikan)
```

**Transisi divalidasi di server** (`PATCH /api/admin/orders/:id`). Di UI, dropdown status
hanya menampilkan transisi yang sah dari status sekarang — jangan biarkan operator memilih
lompatan yang akan ditolak server.

| Status | Label ID | Warna | Aksi berikutnya yang wajar |
|---|---|---|---|
| `pending_payment` | Menunggu bayar | `--status-pending` | Tandai dibayar / Batalkan |
| `paid` | Dibayar | `--status-paid` | Mulai proses |
| `processing` | Diproses | `--status-process` | Tandai dikemas |
| `packed` | Dikemas | `--status-packed` | Kirim (+ isi resi) |
| `shipped` | Dikirim | `--status-shipped` | Tandai selesai |
| `completed` | Selesai | `--status-done` | — |
| `cancelled` | Dibatalkan | `--status-cancel` | — |
| `refunded` | Dikembalikan | `--status-refund` | — |

---

## 8. Aksesibilitas

- **Kontras:** 4.5:1 teks normal, 3:1 teks besar & ikon (semua token di §4 sudah lolos).
- **Fokus terlihat:** cincin **dua warna** — `outline: 2px solid #ffd166` + `box-shadow: 0 0 0 4px var(--ink)`.
  Satu warna saja tidak cukup: kuning terbaca di header gelap (9.69:1) tapi hilang di kertas
  terang (1.42:1); halo gelap kebalikannya (14.83:1 di kertas, 1.08:1 di gelap). Dipasang di
  `:focus-visible` (bukan `:focus`) supaya klik mouse tidak memunculkan cincin.
  **Jangan pernah hapus outline tanpa pengganti.**
- **Keyboard:** semua aksi bisa dicapai tanpa mouse. Urutan tab logis. `Esc` menutup modal.
- **HTML semantik dulu**, ARIA hanya kalau semantik kurang (`<button>`, bukan `<div onclick>`).
- **Jangan sembunyikan aksi penting di hover** — di layar sentuh hover tidak ada.
- **Umumkan perubahan status** ke screen reader (`aria-live="polite"` untuk toast).
- **Form:** setiap input punya `<label for>`. Error dihubungkan via `aria-describedby`.

---

## 9. Dark mode (ditunda)

**Keputusan:** tunda. Alasan: (a) belum dibutuhkan, (b) mode gelap bukan sekadar membalik
warna — butuh aturan elevasi & kontras sendiri, (c) dua tema yang setengah jadi lebih buruk
daripada satu tema yang bagus.

Kalau nanti dibutuhkan, aturannya: pakai `prefers-color-scheme` + toggle manual, dan
**token di §4 sudah siap** — cukup didefinisikan ulang di bawah `[data-theme="dark"]`.

---

## 10. Yang harus dicek sebelum sebuah halaman admin dianggap selesai

- [ ] Kontras teks ≥ 4.5:1 (cek yang baru, jangan asumsi)
- [ ] **Panel yang bergantung sesi punya `hidden` di HTML** — bukan disembunyikan JS (mencegah kedip)
- [ ] Ada **empty state** (bukan tabel kosong)
- [ ] Ada **loading state** (skeleton, bukan spinner)
- [ ] Ada **error state** dengan jalan keluar
- [ ] Setiap aksi destruktif punya modal konfirmasi
- [ ] Setiap aksi sukses/gagal memunculkan toast
- [ ] Bisa dipakai **tanpa mouse** (Tab sampai habis, cincin fokus kelihatan di gelap & terang)
- [ ] Bisa dipakai di **layar 360px** (nol scroll horizontal)
- [ ] Angka uang/kuantitas pakai `tabular-nums`
- [ ] Badge status selalu ada teks, bukan cuma warna
- [ ] Kalau panel dipisah jadi **tab**: panel tetap ada di HTML (cuma `hidden`), tab bisa
      dijangkau keyboard, dan `.panel[hidden]{display:none}` ada setelah aturan grid
- [ ] Kalau ada grid kolom (`1fr 1fr`): pakai **`minmax(0,1fr)`**, jangan `1fr` — input punya
      lebar intrinsik dan akan memaksa halaman melebar di 360px
- [ ] **Bahasa Indonesia** konsisten — judul tab, header tabel, tombol, eyebrow
- [ ] Judul tab berpola `… — Admin Atandra`
