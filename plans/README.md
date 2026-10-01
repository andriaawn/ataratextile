# Plans

Folder ini menyimpan **rencana** — apa yang *akan* dikerjakan dan kenapa.
Bedanya dengan `logs/` (folder lokal, tidak di-commit): log mencatat apa yang **sudah**
terjadi, plan mencatat apa yang **mau** dikerjakan.

## Aturan

1. **Satu plan per pekerjaan.** Nama file: `NNNN-<slug>.md` (contoh: `0001-adopt-framework.md`).
2. **Tulis plan SEBELUM kode.** Tidak ada implementasi sebelum plan disetujui.
3. **Stop dan tunggu approval.** Diam bukan berarti setuju. Pesan yang tidak nyambung
   bukan approval. Keyakinan sendiri bukan approval.
4. **Update status.** `⏳ awaiting approval` → `✅ approved <tanggal>` → `✅ done <tanggal>`.
5. **Brownfield: tulis delta-nya saja.** Karena proyek ini sudah jalan, plan cukup
   menulis *apa yang berubah* — bukan dokumen desain penuh dari nol.

## Template

Lihat [`../templates/plan.md.template`](https://github.com/andriaawn/agentic-vibe-framework/blob/main/templates/plan.md.template)
di framework, atau ikuti struktur plan yang sudah ada di folder ini:

- **Goal** — apa & kenapa sekarang
- **Decisions** — keputusan yang diambil, termasuk yang **ditolak** + alasannya
- **File / task breakdown** — file mana yang berubah
- **Acceptance criteria** — daftar yang bisa dicek benar/salah
- **Open questions** — yang butuh jawaban manusia sebelum mulai
- **Out of scope** — yang **tidak** dikerjakan di sini

## Daftar plan

| # | Plan | Status |
|---|---|---|
| 0001 | [Adopsi framework](0001-adopt-framework.md) | ✅ done 2026-09-30 |
| 0002 | [Roadmap CMS & Commerce](0002-cms-roadmap.md) | 🚧 berjalan — Fase 1 ✅, Fase 2 berikutnya |
| 0003 | [Fase 1: Admin Order + kontras](0003-fase1-admin-order.md) | ✅ done 2026-09-30 |
| 0004 | [URL bersih (hapus `.html`)](0004-clean-urls.md) | ✅ done 2026-09-30 |
| 0005 | [Rapikan UI/UX CMS admin](0005-ui-ux-rapi.md) | ✅ done 2026-10-01 |
| 0006 | [Fase 2: Product CMS](0006-fase2-product-cms.md) | 🚧 2A ✅ · 2B ✅ · 2C ✅ · 2D ✅ live · 2E belum |