// Upload gambar — nol dependency baru.
//
// Kenapa express.raw, bukan multer: Express sudah bisa menerima body mentah, dan
// kita hanya perlu satu file per request (bukan form multipart penuh). Menambah
// dependency untuk itu tidak sepadan.
//
// Prinsip keamanan:
//  1. Jenis file ditentukan dari MAGIC BYTES, bukan ekstensi atau Content-Type.
//     Dua yang terakhir datang dari klien dan bisa dipalsukan.
//  2. SVG DILARANG — SVG bisa memuat <script> dan CSP kita mengizinkan img-src 'self'.
//  3. Nama file = hash isi, bukan nama dari klien → path traversal mustahil.
//  4. Ukuran dibatasi di dua lapis: Content-Length di route, dan cek panjang buffer di sini.

import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

const execFileAsync = promisify(execFile);

export const MAX_UPLOAD_BYTES = 8 * 1024 * 1024;
export const MAX_DIMENSION = 1600;

// Nama file yang kita hasilkan sendiri: hex + ekstensi dari daftar putih.
// Dipakai untuk memvalidasi parameter :name saat hapus — jangan pernah pakai
// nama dari klien secara langsung.
export const SAFE_NAME = /^[a-f0-9]{16,64}\.(jpg|png|webp)$/;

export function uploadsDir(here) {
  const dir = path.join(here, '..', 'public', 'uploads');
  fs.mkdirSync(dir, { recursive: true });
  return dir;
}

// Magic bytes → ekstensi. Sengaja tidak menerima SVG/GIF/BMP/AVIF:
// yang tidak diuji, tidak diizinkan.
export function sniffImage(buffer) {
  if (!Buffer.isBuffer(buffer) || buffer.length < 12) return null;
  if (buffer[0] === 0xff && buffer[1] === 0xd8 && buffer[2] === 0xff) return 'jpg';
  if (buffer.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) return 'png';
  if (buffer.subarray(0, 4).toString('latin1') === 'RIFF' && buffer.subarray(8, 12).toString('latin1') === 'WEBP') return 'webp';
  return null;
}

export function contentHash(buffer) {
  return crypto.createHash('sha256').update(buffer).digest('hex').slice(0, 32);
}

// Resize supaya sisi terpanjang ≤ MAX_DIMENSION, sekaligus buang metadata
// (EXIF bisa memuat lokasi GPS). Kalau ffmpeg gagal, file asli tetap dipakai —
// upload tidak boleh gagal hanya karena alat bantunya bermasalah.
export async function normalise(sourceBuffer, ext, targetPath) {
  const tmpIn = `${targetPath}.src`;
  fs.writeFileSync(tmpIn, sourceBuffer);
  // landscape: batasi lebar, tinggi otomatis (genap). portrait: kebalikannya.
  const filter = "scale='if(gt(iw,ih),min(1600,iw),-2)':'if(gt(iw,ih),-2,min(1600,ih))'";
  const quality = ext === 'jpg' ? ['-q:v', '3'] : ext === 'webp' ? ['-quality', '82'] : ['-compression_level', '6'];
  try {
    await execFileAsync('ffmpeg', [
      '-y', '-hide_banner', '-loglevel', 'error',
      '-i', tmpIn,
      '-vf', filter,
      '-map_metadata', '-1',      // buang EXIF/GPS
      ...quality,
      '-frames:v', '1',
      targetPath,
    ], { timeout: 30_000 });
    if (!fs.existsSync(targetPath) || fs.statSync(targetPath).size === 0) throw new Error('output kosong');
    return { resized: true };
  } catch {
    fs.copyFileSync(tmpIn, targetPath); // simpan apa adanya, jangan gagalkan upload
    return { resized: false };
  } finally {
    fs.rmSync(tmpIn, { force: true });
  }
}

// Simpan buffer → public/uploads. Idempoten: isi sama = nama sama, jadi upload
// ulang tidak menumpuk file kembar.
export async function saveImage(buffer, here) {
  const ext = sniffImage(buffer);
  if (!ext) return { error: 'File bukan gambar JPEG, PNG, atau WebP.' };
  if (buffer.length > MAX_UPLOAD_BYTES) return { error: 'Ukuran gambar melebihi 8 MB.' };

  const dir = uploadsDir(here);
  const name = `${contentHash(buffer)}.${ext}`;
  const target = path.join(dir, name);

  if (!fs.existsSync(target)) {
    const { resized } = await normalise(buffer, ext, target);
    if (!resized) console.warn(`[upload] ffmpeg gagal, file disimpan apa adanya: ${name}`);
  }

  return {
    name,
    url: `/uploads/${name}`,
    bytes: fs.statSync(target).size,
    originalBytes: buffer.length,
  };
}

export function removeImage(name, here) {
  if (!SAFE_NAME.test(String(name || ''))) return { error: 'Nama file tidak valid.' };
  const target = path.join(uploadsDir(here), name);
  if (!fs.existsSync(target)) return { error: 'File tidak ditemukan.', status: 404 };
  fs.rmSync(target, { force: true });
  return { ok: true };
}

// Dipakai test & perawatan: daftar isi folder upload.
export function listUploads(here) {
  return fs.readdirSync(uploadsDir(here)).filter((name) => SAFE_NAME.test(name));
}
