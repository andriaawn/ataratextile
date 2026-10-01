import crypto from 'node:crypto';
import { all, one, run } from './db.js';

const sessionCookie = 'atandra_session';
const sessionTtlMs = 1000 * 60 * 60 * 24 * 7;

export function hashPassword(password) {
  const salt = crypto.randomBytes(16).toString('hex');
  const hash = crypto.scryptSync(password, salt, 64).toString('hex');
  return `${salt}:${hash}`;
}

export function verifyPassword(password, stored) {
  const [salt, expected] = String(stored || '').split(':');
  if (!salt || !expected) return false;
  const actual = crypto.scryptSync(password, salt, 64).toString('hex');
  return crypto.timingSafeEqual(Buffer.from(actual, 'hex'), Buffer.from(expected, 'hex'));
}

function parseCookies(header = '') {
  return Object.fromEntries(header.split(';').filter(Boolean).map((part) => {
    const index = part.indexOf('=');
    return [part.slice(0, index).trim(), decodeURIComponent(part.slice(index + 1).trim())];
  }));
}

export function createSession(userId) {
  const token = crypto.randomBytes(32).toString('hex');
  run('INSERT INTO sessions (token,user_id,expires_at) VALUES (?,?,?)', [token, userId, new Date(Date.now() + sessionTtlMs).toISOString()]);
  return token;
}

export function currentUser(req) {
  const token = parseCookies(req.headers.cookie).atandra_session;
  if (!token) return null;
  const session = one('SELECT u.id,u.email,u.role,u.customer_id FROM sessions s JOIN users u ON u.id=s.user_id WHERE s.token=? AND s.expires_at>? AND u.active=1', [token, new Date().toISOString()]);
  return session || null;
}

export function setSessionCookie(res, token) {
  const secure = process.env.NODE_ENV === 'production' ? '; Secure' : '';
  res.setHeader('Set-Cookie', `${sessionCookie}=${encodeURIComponent(token)}; HttpOnly; SameSite=Lax; Path=/; Max-Age=${sessionTtlMs / 1000}${secure}`);
}

export function clearSessionCookie(res) {
  res.setHeader('Set-Cookie', `${sessionCookie}=; HttpOnly; SameSite=Lax; Path=/; Max-Age=0`);
}

export function requireAuth(req, res, next) {
  const user = currentUser(req);
  if (!user) return res.status(401).json({ error: 'Autentikasi diperlukan' });
  req.user = user;
  next();
}

export function requireRole(role) {
  return (req, res, next) => {
    if (!req.user || req.user.role !== role) return res.status(403).json({ error: 'Akses ditolak' });
    next();
  };
}

const WEAK_PASSWORDS = new Set([
  'password', 'password123', 'admin', 'admin123', 'change-this-password',
  'changeme', '12345678', '123456789', 'qwerty123', 'letmein123',
  'atandra', 'atandra123', 'admin12345', 'password1',
]);

export const MIN_ADMIN_PASSWORD_LENGTH = 12;

// Validasi password baru. Mengembalikan pesan error (Indonesia) atau null kalau lolos.
// Dipakai endpoint ganti-password DAN seedAdmin, supaya aturannya cuma ada di satu tempat.
export function validateNewPassword(next, current) {
  const value = String(next || '');
  if (value.length < MIN_ADMIN_PASSWORD_LENGTH) {
    return `Password baru minimal ${MIN_ADMIN_PASSWORD_LENGTH} karakter`;
  }
  if (WEAK_PASSWORDS.has(value.toLowerCase())) {
    return 'Password terlalu umum, pilih yang lain';
  }
  if (current !== undefined && value === String(current)) {
    return 'Password baru harus berbeda dari password sekarang';
  }
  return null;
}

// Ganti password user sendiri. Mengembalikan { ok:true } atau { ok:false, code, error }.
// Tidak pernah mengembalikan atau mencatat nilai password.
export function changePassword(userId, currentPassword, newPassword) {
  const user = one('SELECT id,password_hash FROM users WHERE id=? AND active=1', [userId]);
  if (!user) return { ok: false, code: 401, error: 'Autentikasi diperlukan' };
  // Wajib buktikan password sekarang. Tanpa ini, siapa pun yang memegang sesi
  // terbuka bisa mengunci pemilik akun dari akunnya sendiri.
  if (!verifyPassword(currentPassword, user.password_hash)) {
    return { ok: false, code: 401, error: 'Password sekarang salah' };
  }
  const invalid = validateNewPassword(newPassword, currentPassword);
  if (invalid) return { ok: false, code: 400, error: invalid };
  run('UPDATE users SET password_hash=? WHERE id=?', [hashPassword(newPassword), user.id]);
  // Gugurkan SEMUA sesi user ini — termasuk sesi yang sedang dipakai. Cookie lama
  // harus benar-benar mati, bukan cuma "tidak dipakai lagi".
  run('DELETE FROM sessions WHERE user_id=?', [user.id]);
  return { ok: true };
}

export function seedAdmin() {
  const email = process.env.ADMIN_EMAIL;
  const password = process.env.ADMIN_PASSWORD;
  if (!email || !password || password.length < 8) return;
  // Tolak password admin yang lemah/umum. Di production ini fatal (server tidak
  // boleh jalan dengan kredensial default); di development hanya peringatan.
  if (WEAK_PASSWORDS.has(password.toLowerCase())) {
    const message = `ADMIN_PASSWORD terlalu lemah/umum ("${password}"). Ganti dengan password acak minimal 12 karakter.`;
    if (process.env.NODE_ENV === 'production') {
      console.error(`[FATAL] ${message}`);
      process.exit(1);
    }
    console.warn(`[security] ${message}`);
  }
  const existing = one('SELECT id,role,password_hash FROM users WHERE email=?', [email.toLowerCase()]);
  if (existing) {
    // Jangan reset password admin yang sudah ada kecuali diminta eksplisit.
    if (existing.role === 'admin' && process.env.ADMIN_PASSWORD_RESET === 'true' && !verifyPassword(password, existing.password_hash)) {
      run('UPDATE users SET password_hash=?,active=1 WHERE id=?', [hashPassword(password), existing.id]);
      console.info(`Admin password reset for ${existing.id}.`);
    }
    return;
  }
  const customer = run('INSERT INTO customers (name,email,company_name) VALUES (?,?,?)', ['Atandra Admin', email.toLowerCase(), 'Atandra Textile Supply']);
  const user = run('INSERT INTO users (email,password_hash,role,customer_id) VALUES (?,?,?,?)', [email.toLowerCase(), hashPassword(password), 'admin', customer.id]);
  console.info(`Admin account seeded for ${user.id}.`);
}

export function listUsers() { return all('SELECT id,email,role,active FROM users ORDER BY id'); }
