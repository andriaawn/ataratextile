# HANDOFF.md

> **Baca ini dulu.** Menjawab: ini apa, jalan di mana, kondisi sekarang, dan mulai dari
> mana. Ditulis untuk orang asing yang kompeten (manusia atau AI) yang belum tahu apa-apa
> soal proyek ini.
>
> **Jaga tetap akurat.** Handoff basi lebih buruk daripada tidak ada — dia aktif
> menyesatkan. Kalau ada perubahan yang bikin file ini salah, perbaiki di sesi yang sama.

**Last updated:** 2026-10-01

---

## 0. Ringkasan 60 detik

- **Produk:** Toko tekstil online — katalog kain (Double Pique), varian warna, keranjang,
  checkout, order, sample request, akun customer, dan admin.
- **Pengguna:** Atandra Textile Supply (bisnis tekstil) + calon pembeli B2B/B2C.
- **Status:** **LIVE** — tapi CMS admin belum dibangun (baru sebagian).
- **Live di:** https://txt.invesbot.my.id

## 1. Infrastruktur

| Bagian | Di mana / bagaimana | Catatan |
|---|---|---|
| Aplikasi | VPS (2 CPU, 3 GB RAM, **tanpa GPU**) | zona waktu UTC |
| Backend | Node/Express 5, port **8787** | `server/index.js` |
| Frontend | Static (Vite build → `dist/`) | dilayani Express yang sama |
| Database | SQLite `data/atandra.sqlite` | di-ignore git |
| Proxy / ingress | **Cloudflare Tunnel `invesbot-web`** | nol nginx, nol port publik |
| Service | systemd `atara-web` (user `dev`) | `enabled` — auto-start saat reboot |

**Port:** 8787 (app) · **80 dipakai `stockdash`** (jangan sentuh).

```
Internet → Cloudflare (DNS + HTTPS)
         → Tunnel "invesbot-web"
           → 127.0.0.1:8787
             → systemd "atara-web" → node server/index.js
```

## 2. Cara kerja

Lihat [`AGENTS.md`](AGENTS.md). Versi singkatnya: **plan → approve → implement → test →
log → commit**. Nol kode sebelum plan disetujui. Push butuh approval terpisah.

## 3. Kondisi sekarang

- **Roadmap:** [`plans/ROADMAP.md`](plans/ROADMAP.md)
- **Angka penting:** 11 produk · 44 varian · 1 kategori · 4 warna · **0 order** ·
  1 akun admin · **52 endpoint API**
- **Deploy terakhir:** 2026-10-01 — Fase 2D badge stok menipis (`plans/0006`) live
- **Commit terakhir:** lihat `git log --oneline -5`
- **Yang belum:** rapikan halaman Produk (2E),
  harga asli, editor konten, pelanggan, pembayaran
- **⚠️ Gambar upload TIDAK di-commit** (`public/uploads/` di-`.gitignore`). Backup lewat
  `bash scripts/backup-uploads.sh` (simpan 7 terbaru). Tanpa ini, gambar hilang kalau
  server rusak.

## 4. Risiko / blocker terbuka

| # | Isu | Tingkat | Butuh |
|---|---|---|---|
| 1 | ~~Belum ada halaman admin order~~ ✅ selesai 2026-09-30 | — | — |
| 2 | Harga masih placeholder (`825000 + gsm*1000`) | 🟠 sedang | daftar harga asli dari user |
| 3 | ~~Sidebar admin 2 link nyasar~~ ✅ selesai | — | — |
| 4 | ~~Nggak ada upload gambar — produk baru butuh URL manual~~ ✅ selesai 2026-10-01 (Fase 2A) | — | — |
| 5 | Pembayaran masih manual (belum ada gateway) | 🟡 rendah | kerja (paling akhir) |
| 6 | Repo **publik** + bisnis nyata — roadmap & backlog bisa dilihat orang | 🟡 rendah | keputusan user (sudah oke) |

## 5. Di mana semuanya berada

```
/home/dev/projects/ataratextile/
  AGENTS.md            aturan kerja (baca pertama)
  HANDOFF.md           file ini
  BACKLOG.md           ide yang ditunda + alasan
  README.md            pintu depan repo
  plans/               rencana (0001 adopsi framework, 0002 CMS, ROADMAP.md)
  logs/                catatan pekerjaan (TIDAK di-commit)
  docs/                arsitektur + API reference
  server/              backend: index.js (176 baris), auth.js, db.js, schema.sql, services.js
  public/img/          12 gambar produk
  tests/security.test.sh  test 5 kerentanan + security headers
  data/atandra.sqlite  database (di-ignore git)
  dist/                hasil build (di-ignore git)
  .env                 konfigurasi (mode 600, di-ignore git)
```

## 6. Secret (nama saja — nilainya di luar repo)

- `ADMIN_EMAIL` / `ADMIN_PASSWORD` → `.env`, mode 600 (password acak, tak pernah ditampilkan)
- `ADMIN_INVITE_KEY` → `.env` (registrasi admin via web)
- `DEV_PAYMENT_KEY` → `.env` (mati otomatis di production)
- `ALLOWED_ORIGINS` → `.env` = `https://txt.invesbot.my.id`
- Tunnel credentials → `/root/.cloudflared/` (root-only)

**Lihat password admin:** `grep ADMIN_PASSWORD /home/dev/projects/ataratextile/.env`

## 7. Langkah pertama sesi baru

1. Baca `HANDOFF.md` (file ini) → `AGENTS.md` → `plans/ROADMAP.md`.
2. Cek masih hidup:
   ```bash
   curl -s https://txt.invesbot.my.id/api/health
   cd /home/dev/projects/ataratextile && git log --oneline -5 && git status
   ```
3. Muat skill yang relevan (`ecommerce-admin-cms`, `cloudflare-tunnel-deployment`, dll).
4. Baca file terbaru di `logs/`.
5. Review blocker terbuka (bagian 4).
6. **JANGAN langsung ngoding.** Tanya mau kerja apa, tulis plan, tunggu approval.

## 8. Pitfalls (belajar dari kejadian nyata)

- **Deploy = tunnel, bukan nginx.** Port 80 dipakai `stockdash` — jangan sentuh. Tunnel
  `invesbot-web` mengarah ke `127.0.0.1:8787`.
- **Restart service butuh `nsenter`.** Nol sudo. Pakai:
  `docker run --rm --privileged --pid=host alpine nsenter -t 1 -m -u -i -n -p systemctl restart atara-web`
- **Config tunnel itu dipakai bersama** (`invesbot-web.yml` melayani invesbot/router/
  workflow/bio juga) — **backup dulu** sebelum edit.
- **`NODE_ENV=production`** → mock-payment mati otomatis + cookie `Secure` + CSP aktif.
- **Backend bukan bind-mounted** — ubah kode → `npm run build` → restart service.
- **`pkill -f "node server/index.js"` bunuh diri sendiri** (pattern-nya ada di command
  line). Pakai `ps aux | grep ... | awk '{print $2}'` lalu `kill`.
- **Panel yang bergantung sesi wajib punya `hidden` di HTML**, jangan disembunyikan lewat
  JS saja — kalau tidak, form login berkedip sebelum JS selesai memeriksa sesi.
- **Cincin fokus harus dua warna** (kuning `#ffd166` + halo `var(--ink)`). Satu warna saja
  hilang di salah satu permukaan: kuning lenyap di kertas terang, gelap lenyap di header.
- **Beranda `index.html` punya CSS inline sendiri** — dia **tidak** memakai `store.css`,
  jadi perubahan token di `store.css` tidak menyentuhnya (dan sebaliknya).
- **File yang sudah masuk git history tetap bisa dibaca** meski dihapus di commit baru
  (`git show <sha>:<path>`). Hapus data sensitif = rewrite history, bukan sekadar commit.
- **`docker run ... cp /dev/stdin` gagal** (container non-root tak bisa baca stdin) —
  pakai `nsenter` via `docker run --privileged --pid=host`.
