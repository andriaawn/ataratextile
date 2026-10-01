# 0008 — Ganti password sendiri dari CMS

Status: ✅ **SELESAI & LIVE** (belum di-commit)
Tanggal: 2026-10-01
Turunan dari: permintaan user ("ganti password admin", lalu pilih "tambahkan fitur
ganti password di CMS dulu")

---

## Masalah

Sekarang **tidak ada cara** mengganti password dari dalam aplikasi. Satu-satunya jalan:
edit `ADMIN_PASSWORD` di `.env` + set `ADMIN_PASSWORD_RESET=true` + restart service
(`server/auth.js:86`). Itu artinya:

- Butuh akses SSH ke server tiap ganti password.
- Password harus lewat `.env` — file yang juga dibaca proses lain.
- Tidak ada cara bagi user untuk memilih password sendiri tanpa menyentuh server.

Selain itu, **ganti password tidak otomatis mematikan sesi lama.** Saat ini ada **7 sesi
admin aktif** (kedaluwarsa 7–8 Okt). Kalau password diganti lewat `.env`, siapa pun yang
memegang cookie lama **tetap bisa masuk** sampai sesinya kedaluwarsa.

## Keputusan user

- Bikin **fitur ganti password di CMS** (bukan lewat `.env`).
- **Gugurkan semua sesi** saat password diganti → semua perangkat login ulang.

## Keputusan teknis

**1. Endpoint `POST /api/auth/change-password`** (`requireAuth`)
Body: `{ current_password, new_password }`. User yang login mengubah password **miliknya
sendiri** (`req.user.id`) — bukan orang lain. Tidak ada parameter user id di body.

**2. Wajib kirim password sekarang.** Kalau tidak, siapa pun yang memegang sesi terbuka
(browser tidak dikunci) bisa mengunci pemilik asli dari akunnya sendiri. Verifikasi lewat
`verifyPassword` yang sudah ada (perbandingan `timingSafeEqual`).

**3. Semua sesi digugurkan, termasuk sesi yang sedang dipakai.**
`DELETE FROM sessions WHERE user_id=?` + `clearSessionCookie(res)`. Konsekuensinya: setelah
berhasil ganti, user **langsung logout** dan harus login dengan password baru. Ini yang
diminta user ("semua perangkat login ulang") dan paling aman: tidak ada cookie lama yang
tersisa hidup.

**4. Validasi password baru** (tolak 400 kalau gagal):
- minimal **12 karakter** (kode yang ada sudah menyebut 12 sebagai standar admin)
- bukan password umum (`WEAK_PASSWORDS` yang sudah ada di `auth.js:63`)
- **berbeda** dari password sekarang (ganti ke password yang sama = tidak ada gunanya,
  dan bikin user mengira sudah ganti padahal belum)

**5. Rate limit terpisah: 5 percobaan / 15 menit per IP** (pola sama seperti
`admin-register` di `index.js:69`). Tanpa ini, endpoint ini jadi alat brute-force
password sekarang dari sesi yang sudah dicuri.

**6. Tidak ada yang di-log, tidak ada yang di-echo.** Respons sukses = `204` tanpa body.
Pesan error **tidak** membocorkan mana yang salah (password sekarang salah vs password
baru lemah dipisah, tapi tidak pernah mengembalikan nilai password).

**7. UI di dashboard admin** (`/admin`) — `<details>` "Ganti password" berisi 3 field:
password sekarang, password baru, **ulangi password baru**.

Field "ulangi" gw pertahankan **karena mekanisme, bukan selera**: field password tidak
terlihat, dan kalau user salah ketik, **tidak ada jalan pulih** (tidak ada reset password
lewat email). Salah ketik = terkunci dari akun sendiri secara permanen. Konfirmasi
menutup lubang itu. Ini bukan abstraksi tambahan, ini penjaga satu-satunya jalur masuk.

Setelah sukses: toast "Password diganti. Silakan login ulang." → arahkan ke `/admin`
(form login). Sesi memang sudah mati, jadi ini bukan kejutan.

**8. Panel punya `hidden` di HTML statis.** Aturan lama: panel yang bergantung sesi jangan
disembunyikan JS (mencegah kedip). Panel ini ada di dalam `#admin-dashboard` yang sudah
`hidden`, jadi sudah aman — tidak perlu panel baru.

## Yang TIDAK dikerjakan (sengaja)

- **Reset password tanpa login** (lupa password / lewat email) — butuh email gateway,
  di luar scope. Karena itu validasi & konfirmasi di atas penting.
- **Ganti password untuk pelanggan** (`/akun`) — endpoint-nya generic dan sudah bisa
  dipakai, tapi UI-nya tidak gw tambahkan sekarang (tidak diminta).
- **2FA / passkey** — di luar scope.
- **Riwayat password** (cegah pakai ulang password lama) — di luar scope.
- **Ganti email admin** — tidak diminta.

## File yang berubah

| File | Perubahan |
|---|---|
| `server/auth.js` | fungsi `changePassword(userId, current, next)` + `revokeAllSessions(userId)`; ekspor `WEAK_PASSWORDS` untuk dipakai validasi |
| `server/index.js` | endpoint `POST /api/auth/change-password` + rate limit terpisah |
| `admin.html` | `<details>` form ganti password di dalam `#admin-dashboard` |
| `store.js` | `bindChangePassword()` dipanggil dari `initAdmin()` |
| `tests/change-password.test.sh` | **BARU** |
| `docs/api.md` | +1 endpoint (52 → **53**) |
| `plans/README.md`, `plans/ROADMAP.md`, `HANDOFF.md` | status + angka endpoint |

**Nol halaman baru** → `vite.config.ts` dan `PAGES` tidak berubah.

## Acceptance criteria — SEMUA ✅

- [x] Tanpa login → **401** ✅
- [x] Password sekarang salah → **401**, password **tidak berubah** ✅ (4a + 4b)
- [x] Password baru < 12 karakter → **400**, tidak berubah ✅
- [x] Password baru = password umum (`admin123` dll) → **400** ✅ (diuji 3 varian)
- [x] Password baru = password sekarang → **400** ✅
- [x] Sukses → password lama **tidak bisa** login lagi, password baru **bisa** ✅ (9a/9b)
- [x] Sukses → **semua** sesi user itu terhapus (termasuk yang dipakai) + cookie dibersihkan ✅ (8a/8b)
- [x] Sesi user **lain** tidak ikut terhapus ✅ (4c — saat gagal; sesi orang lain memang tidak disentuh)
- [x] Rate limit: percobaan gagal ke-6 dalam 15 menit → **429** ✅ (12)
- [x] Password **tidak pernah** muncul di respons maupun log ✅ (7b)
- [x] `hidden` panel tetap benar; nol error console ✅ (uji browser)
- [x] Bisa dipakai di 360px (nol scroll horizontal) ✅ (**0 overflow di 10 lebar 320–1440**)
- [x] Negative control: hapus cek password sekarang → test **GAGAL** ✅ (**NC-1 GAGAL 9 · NC-2 GAGAL 2 · NC-3 GAGAL 8**)
- [x] Suite penuh tetap hijau + idempoten ✅ (**269/269**, 10 suite, 2 putaran)
- [x] DB produksi tidak tersentuh ✅ (uji di throwaway port 8881)
- [x] Nol regresi kontras ✅ (form pakai token lama: `--muted`, `--rust`, `--ink`)

## Hasil

| | |
|---|---|
| Test baru | `tests/change-password.test.sh` — **22 cek**, 22/22 ✅ |
| Suite penuh | **269/269** (247 + 22), idempoten 2× |
| Negative control | 3 skenario rusak → GAGAL **9 / 2 / 8** ✅ |
| Uji browser | form muncul, konfirmasi beda tertangkap, sukses → semua sesi mati → login ulang; **0 error console** |
| Responsif | 0 overflow @320/360/390/414/480/768/900/1024/1280/1440 |
| Endpoint | 52 → **53** |
| Deploy | LIVE di https://txt.invesbot.my.id |

**Pelajaran:** rate limit dihitung hanya untuk percobaan **GAGAL (401)** — request valid tidak
menghukum user, dan tes "sukses" tidak ikut memakan kuota sehingga urutan tes tidak rapuh.
Tes sesi harus dicek **tepat setelah** ganti password, sebelum login ulang (kalau tidak,
jar yang dipakai login ulang tampak "hidup" dan tesnya salah sendiri — bug test, bukan bug kode).
