# Plan 0001 — Adopsi `agentic-vibe-framework` di ataratextile

**Tanggal:** 2026-09-30
**Status:** ✅ approved & done 2026-09-30
**Owner:** andriaawn
**Repo:** `andriaawn/ataratextile` (publik) · Live: https://txt.invesbot.my.id

---

## 1. Goal

Terapkan struktur + disiplin dari framework yang kita bikin sendiri
(`andriaawn/agentic-vibe-framework`) ke repo ataratextile, supaya:

1. Sesi baru (agent atau manusia) langsung nyambung tanpa nebak-nebak.
2. Plan & log punya rumah yang benar (`plans/` vs `logs/`).
3. Keputusan (yang diambil DAN yang ditolak) terekam — tidak hilang di chat.
4. "Apa yang belum dikerjakan" punya satu sumber kebenaran (`ROADMAP.md`).

Sekaligus: cek apakah ada framework luar yang lebih bagus, dan **curi ide terbaiknya**.

---

## 2. Research — framework apa yang dipakai orang luar (2026)

| Framework | Bintang | Model | Cocok untuk | Biaya |
|---|---|---|---|---|
| **GitHub Spec Kit** | ~111k | `constitution` → specify → plan → tasks → implement | Tim menengah, standardisasi kualitas | Setup ~30 mnt; **overhead ~9×** untuk task kecil |
| **BMAD-METHOD** | ~49k | 12 agent persona (Analyst→PM→Architect→Dev→QA) | Greenfield kompleks, regulated | Berat — ~31k token/run, **$2k/dev/bulan** |
| **OpenSpec** | ~52k | **Delta spec** (cuma yang berubah) → propose → apply → archive | **Brownfield / legacy**, solo dev | Ringan, setup ~5 mnt |
| **GSD / Superpowers** | kecil | 2 prompt (planning + building loop) | Solo, requirement cair | Paling ringan |
| **AWS Kiro** | — | IDE penuh, spec-first | AWS-native | Vendor lock-in |

**Kesimpulan research:**

- **ataratextile itu BROWNFIELD** (app sudah jalan, 34 endpoint, live). → Framework
  greenfield berat (BMAD, Spec Kit) **overkill**. Kalau ikut luar, jawabannya **OpenSpec**.
- Tapi **framework kita sendiri sudah setara OpenSpec/GSD** (ringan, plan→log→commit),
  dan sudah **disesuaikan** dengan workflow nyata kita. Ganti = buang kerja.
- **Yang kita serap (ide terbaik dari luar):**
  1. **Constitution** (Spec Kit) → `AGENTS.md` kita = constitution. Tambah bagian
     "prinsip yang tidak boleh dilanggar".
  2. **Delta spec** (OpenSpec) → untuk kerja brownfield, plan cukup tulis **yang berubah**,
     bukan dokumen penuh. Sudah kita lakukan; jadikan aturan eksplisit.
  3. **Adversarial review** (BMAD: "zero findings itu mencurigakan") → kita sudah punya
     "verifikasi sendiri, jangan percaya self-report". Perkuat.
  4. **6 area AGENTS.md** (analisis GitHub atas 2.500+ repo) → pastikan `AGENTS.md` kita
     mencakup: overview, perintah, konvensi, batasan, aturan, kapan berhenti.

**Keputusan: pakai framework sendiri + serap 4 ide di atas. TIDAK pindah ke Spec Kit/BMAD.**

---

## 3. Decisions

- **Pakai `agentic-vibe-framework`** — bukan Spec Kit/BMAD/OpenSpec. Alasan: brownfield,
  tim = 1 orang, tool = Hermes (bukan Claude Code/Cursor yang jadi asumsi framework luar).
- **Rejected:** BMAD (12 agent, $2k/bln) — overhead gila untuk 1 developer.
- **Rejected:** Spec Kit (9× overhead) — setup 30 menit + ceremony per task kecil.
- **Rejected:** OpenSpec — bagus, tapi kita sudah punya versi sendiri yang lebih pas.
- **`plans/` DI-COMMIT** (roadmap & plan = dokumentasi berguna, tidak sensitif).
- **`logs/` — perlu keputusan lu** (lihat Open Questions #1).
- **`AGENTS.md` butuh approval lu** — file ini di-guard Hermes.

---

## 4. File / task breakdown

**A. Struktur baru (adopsi inti)**

- `AGENTS.md` — working agreement: stack, perintah, konvensi, **hard rules**, pitfalls ataratextile
- `HANDOFF.md` — posisi sekarang: live, admin jadi, fase CMS belum mulai, infra
- `plans/README.md` — cara pakai folder plans
- `plans/ROADMAP.md` — 5 fase CMS + pembayaran terakhir (dari plan CMS tadi)
- `BACKLOG.md` — bug B1–B10 + ide yang ditunda (dengan alasan + trigger)
- `CLAUDE.md` — pointer ke AGENTS.md (biar Claude Code/Cursor juga nyambung)
- `docs/` — (opsional) arsitektur + API reference

**B. Rapikan yang sudah ada**

- Pindah `logs/2026-09-30_plan-cms.md` → `plans/0002-cms-roadmap.md`
  (plan ≠ log; plan di `plans/`, log di `logs/`)
- `logs/` — tambah `logs/README.md` konvensi nama file

**C. Sesuaikan dengan proyek**

- `AGENTS.md`: isi pitfalls nyata ataratextile —
  - Deploy via Cloudflare Tunnel `invesbot-web` → `127.0.0.1:8787`
  - systemd `atara-web`; restart butuh `nsenter` via `docker run --privileged --pid=host`
  - Port 80 dipakai `stockdash` (jangan sentuh)
  - `NODE_ENV=production` → mock-payment mati otomatis
  - Harga masih placeholder `825000 + gsm*1000`
  - `.env`, `data/`, `dist/`, `logs/` di-ignore git
- `plans/ROADMAP.md`: isi 5 fase + "Refused / don't re-propose" (mis. "pindah ke WordPress")

---

## 5. Acceptance criteria

- [ ] `AGENTS.md` ada, berisi stack + perintah + hard rules + pitfalls ataratextile
- [ ] `HANDOFF.md` ada, akurat dengan kondisi live saat ini (diverifikasi ulang, bukan dari ingatan)
- [ ] `plans/ROADMAP.md` ada, memuat 5 fase + pembayaran terakhir
- [ ] `BACKLOG.md` ada, memuat B1–B10 dengan alasan + trigger
- [ ] `CLAUDE.md` ada, cuma pointer (tidak duplikat isi AGENTS.md)
- [ ] `plan-cms.md` sudah pindah dari `logs/` → `plans/`
- [ ] Semua link internal di dokumen resolve (tidak ada link mati)
- [ ] Nol secret/PII di file yang di-commit
- [ ] `git status` bersih; commit pakai path spesifik (bukan `git add -A`)
- [ ] **Push = approval terpisah**

---

## 6. Open questions

1. **`logs/` mau di-commit atau tetap di-ignore?**
   Repo ini **PUBLIK** dan ini bisnis nyata. Log deploy memuat detail server
   (path, port, nama tunnel). Pilihan gw:
   - **(A) Commit `plans/` + `docs/`, tetap ignore `logs/`** ← rekomendasi gw (aman)
   - (B) Commit `plans/` + `logs/` juga, tapi log wajib di-sanitize dulu
   - (C) Commit semua apa adanya (paling berisiko)
2. **Mau `docs/` (arsitektur + API reference) sekalian?** Atau tunda?
3. **Repo ataratextile tetap publik?** Bisnis nyata — repo publik = orang bisa lihat
   kode + roadmap + backlog. Tidak ada secret (sudah diverifikasi), tapi ini keputusan lu.
4. **`AGENTS.md` di-guard Hermes** — pas gw tulis, lu bakal dapat prompt approval. OK?

---

## 7. Out of scope

- **Tidak** ganti framework ke Spec Kit / BMAD / OpenSpec.
- **Tidak** sentuh kode aplikasi (ini murni dokumentasi + struktur).
- **Tidak** mulai Fase 1 CMS (admin order) — itu plan terpisah (`plans/0002`).
- **Tidak** push ke GitHub tanpa approval terpisah.

---

<!--
Kalau approve: ubah Status jadi "✅ approved <tanggal>" dan kerjakan.
Selesai: tulis log di logs/YYYY-MM-DD_adopt-framework.md
-->
