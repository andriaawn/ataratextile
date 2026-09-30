# Backlog — ditunda, dengan alasan

> Ide yang bagus tapi **belum sekarang**. Setiap item wajib punya alasan penundaan dan
> trigger konkret untuk mulai — kalau tidak, itu cuma kebisingan.

## Simpan gambar di Cloudinary / CDN

**Status:** ⏸ Ditunda

**Why deferred:** Upload ke server lokal (`public/uploads/`) sudah cukup untuk skala
sekarang. Cloudinary = akun tambahan, biaya, dan dependensi luar.

**Trigger to start:** kalau gambar > 500 MB atau ada keluhan lambat di daerah sinyal lemah.

**Recon already done:** Cloudinary free tier = 25 GB storage / 25 GB bandwidth per bulan.

---

## Pindah dari SQLite ke PostgreSQL

**Status:** ⏸ Ditunda

**Why deferred:** SQLite lebih dari cukup untuk 1 toko (katalog 11 produk, 44 varian).
Postgres = server tambahan, backup tambahan, kompleksitas tambahan.

**Trigger to start:** kalau butuh akses tulis bersamaan tinggi, atau >10.000 order, atau
butuh full-text search serius.

**Recon already done:** semua query sudah pakai prepared statement + parameter, jadi
migrasi relatif mudah kalau nanti dibutuhkan.

---

## Editor visual drag-and-drop (page builder)

**Status:** ⏸ Ditunda

**Why deferred:** Kompleks, rapuh, dan bikin HTML jadi susah dirawat. Untuk katalog
sederhana, form field sudah cukup.

**Trigger to start:** jangan — kecuali user eksplisit minta dan mau bayar tool jadi.

---

## Multi-bahasa (ID/EN)

**Status:** ⏸ Ditunda

**Why deferred:** Semua pelanggan saat ini orang Indonesia. Nambah bahasa = kerja dobel
di semua teks + perlu infrastruktur i18n.

**Trigger to start:** ada permintaan pembeli luar negeri.

---

## Program afiliasi / referral

**Status:** ⏸ Ditunda

**Why deferred:** Butuh pelacakan kode referral, perhitungan komisi, dan pembayaran
komisi. Terlalu dini — belum ada pembeli.

**Trigger to start:** >50 order selesai dan ada yang menawarkan diri jadi reseller.

---

## Integrasi marketplace (Tokopedia/Shopee)

**Status:** ⏸ Ditunda

**Why deferred:** API marketplace berubah-ubah, butuh approval seller, dan sinkronisasi
stok dua arah itu rumit (bisa oversell).

**Trigger to start:** kalau penjualan di website sudah stabil dan mau ekspansi channel.

---

## Ditolak / sengaja dikubur (jangan diajukan lagi tanpa alasan baru)

| Item | Alasan | Dicatat di |
|---|---|---|
| Pindah ke WordPress/WooCommerce | Buang kerja backend yang sudah bagus | `plans/ROADMAP.md` |
| Ganti ke Strapi/Directus | Harus ganti backend & DB | `plans/ROADMAP.md` |
| Ganti framework ke Spec Kit / BMAD | Overhead besar, proyek brownfield 1 developer | `plans/0001-adopt-framework.md` |
