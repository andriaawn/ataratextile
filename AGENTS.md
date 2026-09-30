# AGENTS.md

> Aturan kerja untuk agent AI di proyek ini. Baca file ini **pertama**, setiap sesi,
> sebelum menyentuh apa pun. Jaga tetap pendek dan padat — file ini dimuat di setiap
> sesi, jadi setiap baris memakan perhatian.

## Proyek sekilas

- **Apa ini:** Toko tekstil online (katalog kain, varian, checkout, order, admin).
- **Stack:** Node.js + Express 5, SQLite, frontend HTML/JS statis (Vite build).
- **Jalan di:** VPS 2 CPU / 3 GB RAM, systemd `atara-web`, port 8787, di balik
  Cloudflare Tunnel `invesbot-web`.
- **Kondisi sekarang:** lihat [`HANDOFF.md`](HANDOFF.md).

## Baca sebelum bekerja

1. File ini (`AGENTS.md`) — cara kita kerja.
2. [`HANDOFF.md`](HANDOFF.md) — posisi kita sekarang.
3. [`plans/ROADMAP.md`](plans/ROADMAP.md) — apa yang berikutnya.
4. File terbaru di `logs/` — apa yang baru terjadi.
5. Skill yang cocok dengan tugasmu.

**Lalu cek kondisi live** (`git status`, `git log --oneline -5`, health endpoint)
sebelum melakukan apa pun. Orientasi dulu.

## Alur kerja (tidak bisa ditawar)

```
PLAN → APPROVE → IMPLEMENT → TEST → LOG → COMMIT
```

1. **PLAN** — tulis plan ke `plans/<slug>.md` **sebelum kode apa pun**.
2. **APPROVE** — **STOP** dan tunggu "ya" eksplisit. Diam **bukan** approval. Pesan yang
   tidak nyambung **bukan** approval. Keyakinan sendiri **bukan** approval.
3. **IMPLEMENT** — kerja mandiri; commit dalam langkah kecil yang bisa direview.
4. **TEST** — jalankan test sebagai bagian dari kerja. **Buktikan test-nya bisa gagal.**
5. **LOG** — tulis `logs/YYYY-MM-DD_<slug>.md` dengan root cause + verifikasi.
6. **COMMIT** — stage **path spesifik** (jangan pernah `git add -A`). Push butuh
   approval terpisah.

## Aturan keras (constitution)

- **Jangan pernah commit secret.** Nol `.env`, token, key, kredensial.
- **Jangan pernah cetak nilai secret** di output, log, atau laporan — mask (`***`).
- **Jangan pernah mengetik password.** Pakai vault, atau minta user memasukkannya.
- **Jangan pernah jalankan perintah destruktif** (drop, hapus massal, migrasi) tanpa
  dry-run di salinan throwaway, dan tanpa approval eksplisit.
- **Jangan pernah menyampaikan self-report agent sebagai fakta** — verifikasi sendiri.
- **Kalau tidak nyambung, lepaskan** — jangan menyambungkan jalur mati agar terlihat selesai.
- **Jangan sentuh file di luar lingkup tugas.** Jangan menulis ulang layout/config yang
  tidak diminta.
- **Bukti, bukan keyakinan.** "Sudah dites" bukan bukti; tempel perintah + outputnya.
- **Ukur, jangan nebak.** Kalau bisa dihitung, hitung.
- **Jangan ubah parameter sampai angkanya bagus** — itu curve-fitting. Perbaikan harus
  beralasan dari mekanisme, bukan dari hasil.
- **Setelah melihat password admin** (`grep ADMIN_PASSWORD .env`), sarankan user
  menggantinya dengan yang dia hafal.

## Perintah penting

```bash
# jalan lokal
npm run api                    # API + serve dist/ + public/ di :8787
npm run dev                    # Vite dev server (:5173, proxy /api → :8787)

# build (WAJIB setelah ubah frontend, karena backend serve dist/)
npm run build

# test
bash tests/security.test.sh    # 10 cek: IDOR, admin takeover, mock-payment, XSS, headers
bash tests/admin-orders.test.sh # 12 cek: halaman order, ubah status, resi, kontras
# ⚠️ jalankan test di DB throwaway (bukan data/atandra.sqlite) — lihat pitfalls

# health
curl -s https://txt.invesbot.my.id/api/health

# deploy ulang setelah ubah kode
npm run build && docker run --rm --privileged --pid=host alpine \
  nsenter -t 1 -m -u -i -n -p systemctl restart atara-web

# log service
tail -f logs/service.log
```

## Konvensi

- **Bahasa:** chat pakai Bahasa Indonesia informal ("bro"); kode & commit message
  pakai Bahasa Inggris.
- **Commit style:** conventional commits — `feat:`, `fix:`, `docs:`, `chore:`, `security:`.
- **Branching:** kerja di `main`, commit kecil.
- **Identity commit:** `andriaawn <84422308+andriaawn@users.noreply.github.com>`.
- **Commit message dengan `&`:** tulis ke file dulu + `git commit -F`, karena heredoc
  memicu false-positive.
- **Harga:** masih placeholder `825000 + gsm*1000` (ditunda atas permintaan user).

## Kapan harus berhenti dan bertanya

- Sebelum tindakan destruktif atau tak bisa dibalik (rewrite history, force push, hapus DB).
- Ketika keputusan menyentuh arsitektur atau requirement di luar plan yang disetujui.
- Ketika terhalang kredensial, akses, atau pilihan yang hanya bisa diambil user.
- Sebelum push ke repo publik (repo ini **publik** — bisnis nyata).

## Pitfalls (pelajaran mahal)

- **Deploy = Cloudflare Tunnel, bukan nginx.** Port 80 dipakai `stockdash` — jangan
  sentuh. Tunnel `invesbot-web` → `127.0.0.1:8787`.
- **Restart service butuh `nsenter`** — nol sudo. Pakai `docker run --privileged --pid=host`.
- **Config tunnel dipakai bersama** (invesbot/router/workflow/bio) — **backup dulu**.
- **`NODE_ENV=production`** → mock-payment mati + cookie `Secure` + CSP aktif.
- **Backend tidak bind-mounted** — ubah kode → `npm run build` → restart.
- **`pkill -f "node server/index.js"` bunuh diri sendiri** (pattern ada di command line).
- **Halaman baru WAJIB didaftarkan di `vite.config.ts`** — server serve `dist/`, jadi file di
  root akan 404 tanpa `vite build` yang mendaftarkannya.
- **Server tulis DB dari memory** — **stop service dulu** sebelum edit `data/atandra.sqlite`
  langsung, kalau tidak perubahan ketimpa saat shutdown.
- **`GET /api/orders/:id` balikin `{order, items}` terpisah** — bukan `order.items`.
- **`reserved_stock` wajib dikembalikan** saat hapus order; kalau tidak, stok "bocor".
- **Test destruktif wajib di DB throwaway** — symlink `dist`/`public`/`node_modules` ke
  `/tmp/atara_test*`, `cp -r server`, lalu hapus setelah selesai.
- **Data di git history tetap terbaca** meski dihapus di commit baru (`git show <sha>:<path>`).
- **`logs/`, `data/`, `dist/`, `.env` di-ignore git** — jangan pernah commit paksa.
- **`write_file` ke file bernama persis `AGENTS.md`/`CLAUDE.md` itu di-guard** — butuh
  approval user (ini disengaja, bukan error).

## Struktur

```
AGENTS.md          file ini — aturan kerja
HANDOFF.md         kondisi terkini (baca setelah file ini)
BACKLOG.md         ide ditunda + alasan + trigger
plans/             rencana sebelum kerja (ROADMAP.md, 0001-*, 0002-*)
logs/              catatan kerja setelah selesai (TIDAK di-commit)
docs/              arsitektur + referensi API
server/            backend Express (index.js, auth.js, db.js, schema.sql, services.js)
public/            aset statis (gambar)
tests/             test keamanan
data/  dist/  .env di-ignore git
```
