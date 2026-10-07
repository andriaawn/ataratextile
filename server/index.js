import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import crypto from 'node:crypto';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { all, one, run, transaction } from './db.js';
import { ManualPaymentProvider, ManualShippingProvider, NotificationService } from './services.js';
import { MAX_UPLOAD_BYTES, listUploads, removeImage, saveImage } from './uploads.js';
import { clearSessionCookie, changePassword, createSession, currentUser, hashPassword, requireAuth, requireRole, seedAdmin, setSessionCookie, verifyPassword } from './auth.js';

const app = express();
const port = Number(process.env.PORT || 8787);
const here = path.dirname(fileURLToPath(import.meta.url));
const payment = new ManualPaymentProvider();
const shipping = new ManualShippingProvider();
const notifications = new NotificationService();
const configuredOrigins = (process.env.ALLOWED_ORIGINS || '').split(',').map((origin) => origin.trim()).filter(Boolean);
const allowedOrigins = process.env.NODE_ENV === 'production' ? configuredOrigins : [...new Set([...configuredOrigins, 'http://localhost:5173', 'http://127.0.0.1:5173'])];
app.use(cors({ origin: (origin, callback) => !origin || allowedOrigins.includes(origin) ? callback(null, true) : callback(new Error('Origin tidak diizinkan')), credentials: true }));
app.use(express.json({ limit: '1mb' }));
// Security headers. CSP mengizinkan 'unsafe-inline' karena halaman masih memakai
// <style>/<script> inline; tetap membatasi frame-ancestors, object-src, base-uri.
app.use((_req, res, next) => {
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('X-Frame-Options', 'DENY');
  res.setHeader('Referrer-Policy', 'strict-origin-when-cross-origin');
  res.setHeader('Permissions-Policy', 'geolocation=(), microphone=(), camera=()');
  res.setHeader('Content-Security-Policy', [
    "default-src 'self'",
    "img-src 'self' data: blob:",
    "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com",
    "font-src 'self' https://fonts.gstatic.com",
    "script-src 'self' 'unsafe-inline'",
    "connect-src 'self'",
    "frame-ancestors 'none'",
    "object-src 'none'",
    "base-uri 'self'",
    "form-action 'self'",
  ].join('; '));
  next();
});
const requestCounts = new Map();
app.use((req, res, next) => { const key = req.ip || 'unknown'; const now = Date.now(); const entry = requestCounts.get(key) || { started: now, count: 0 }; if (now - entry.started > 60_000) { entry.started = now; entry.count = 0; } entry.count += 1; requestCounts.set(key, entry); if (entry.count > 120) return res.status(429).json({ error: 'Terlalu banyak request' }); next(); });

seedAdmin();

const productSelect = `SELECT p.*, c.name AS category_name, c.slug AS category_slug, i.url AS image, MIN(v.price) AS min_price, COALESCE(SUM(inv.stock - inv.reserved_stock), 0) AS available_stock, MIN(inv.low_stock_threshold) AS low_stock_threshold FROM products p JOIN categories c ON c.id=p.category_id LEFT JOIN product_images i ON i.product_id=p.id AND i.sort_order=0 LEFT JOIN product_variants v ON v.product_id=p.id LEFT JOIN inventory inv ON inv.variant_id=v.id`;
function productWhere(query) { const clauses = ["p.status='active'"]; const params = []; if (query.q) { clauses.push('(LOWER(p.name) LIKE ? OR LOWER(p.sku) LIKE ? OR LOWER(p.material) LIKE ? OR LOWER(p.description) LIKE ?)'); const q = `%${String(query.q).toLowerCase()}%`; params.push(q, q, q, q); } if (query.category) { clauses.push('c.slug=?'); params.push(query.category); } if (query.gsm) { clauses.push('p.gsm BETWEEN ? AND ?'); params.push(Number(query.gsm) - 15, Number(query.gsm) + 15); } return { clause: clauses.join(' AND '), params }; }
// Nilai dari form HTML selalu string. Checkbox/select yang tidak dicentang bisa
// mengirim "0" — dan "0" itu TRUTHY di JS, jadi `featured ? 1 : 0` akan salah
// mengubahnya jadi 1. Semua flag wajib lewat sini.
function flagValue(value, fallback = 0) { if (value === undefined || value === null || value === '') return fallback; return value === true || value === 1 || value === '1' || value === 'true' || value === 'on' ? 1 : 0; }
function serializeProduct(product) { if (!product) return null; const available = Number(product.available_stock); const threshold = product.low_stock_threshold === null || product.low_stock_threshold === undefined ? null : Number(product.low_stock_threshold); return { ...product, featured: Boolean(product.featured), bestseller: Boolean(product.bestseller), sample_available: Boolean(product.sample_available), available_stock: available, min_price: product.min_price === null || product.min_price === undefined ? null : Number(product.min_price), low_stock_threshold: threshold, low_stock: threshold !== null && available <= threshold, image: product.image || '/img/fabric-hero.png' }; }
function getPricing(productId, quantity) { return one('SELECT * FROM price_tiers WHERE product_id=? AND min_quantity<=? AND (max_quantity IS NULL OR max_quantity>=?) ORDER BY min_quantity DESC LIMIT 1', [productId, quantity, quantity]); }

// Status order -> status pembayaran. SATU peta, satu tempat. Dipakai saat admin
// mengubah status order supaya `payments.status` tidak pernah tertinggal dari
// `orders.status` (kalau tertinggal, KPI "Menunggu bayar" menghitung order yang
// sudah refund/batal — angka dashboard jadi bohong).
function paymentStatusForOrderStatus(status) {
  if (status === 'pending_payment') return 'pending';
  if (status === 'cancelled' || status === 'refunded') return 'refunded';
  return 'paid';
}

// Hitung item order dari DB: validasi varian aktif + stok, lalu terapkan harga
// tier. Dipakai BERSAMA oleh `POST /api/orders` dan `POST /api/checkout/quote`
// supaya angka yang dilihat pelanggan MUSTAHIL beda dari yang ditagih. Ini akar
// bug lama: checkout menghitung sendiri (harga localStorage, ongkir flat 35rb).
function expandItems(items) {
  return (items || []).map((item) => {
    const variant = one('SELECT v.*, p.name AS product_name, c.name AS color, inv.stock, inv.reserved_stock FROM product_variants v JOIN products p ON p.id=v.product_id JOIN colors c ON c.id=v.color_id JOIN inventory inv ON inv.variant_id=v.id WHERE v.id=? AND v.active=1 AND p.status=?', [item.variant_id, 'active']);
    if (!variant) throw new Error('Variant tidak aktif');
    const quantity = Number(item.quantity);
    const available = variant.stock - variant.reserved_stock;
    if (!Number.isInteger(quantity) || quantity < 1 || available < quantity) throw new Error(`Stok ${variant.product_name} tidak mencukupi`);
    const tier = getPricing(variant.product_id, quantity);
    return { ...variant, quantity, unit_price: tier?.price || variant.price, variant_name: `${variant.product_name} — ${variant.color}` };
  });
}

// Hitung subtotal (dengan tier) + ongkir + total dari item yang sudah di-expand.
// SATU-satunya tempat rumus uang pesanan hidup, dipakai `POST /api/orders` dan
// `POST /api/checkout/quote` — supaya angka yang dilihat pelanggan mustahil beda
// dari yang ditagih.
function quoteFromExpanded(expanded, city) {
  const subtotal = expanded.reduce((sum, item) => sum + item.unit_price * item.quantity, 0);
  const ship = shipping.quote({ quantity: expanded.reduce((sum, item) => sum + item.quantity, 0), city: city || '' });
  return { expanded, subtotal, ship, total: subtotal + ship.cost };
}

function quoteOrder(items, city) {
  const { expanded, subtotal, ship, total } = quoteFromExpanded(expandItems(items), city);
  return {
    items: expanded.map((item) => ({
      variant_id: item.id,
      product_name: item.product_name,
      variant_name: item.variant_name,
      sku: item.sku,
      quantity: item.quantity,
      unit_price: item.unit_price,
      subtotal: item.unit_price * item.quantity,
    })),
    subtotal,
    shipping: ship,
    total,
  };
}

app.get('/api/health', (_req, res) => res.json({ ok: true, service: 'atandra-commerce-api' }));
app.post('/api/auth/register', (req, res) => { const { name, email, password, phone = '', company_name = '' } = req.body || {}; if (!name || !email || !password || password.length < 8) return res.status(400).json({ error: 'Nama, email, dan password minimal 8 karakter wajib diisi' }); if (one('SELECT id FROM users WHERE email=?', [email.toLowerCase()])) return res.status(409).json({ error: 'Email sudah terdaftar' }); const customer = run('INSERT INTO customers (name,email,phone,company_name) VALUES (?,?,?,?)', [name.trim(), email.toLowerCase(), phone, company_name]); const user = run('INSERT INTO users (email,password_hash,role,customer_id) VALUES (?,?,?,?)', [email.toLowerCase(), hashPassword(password), 'customer', customer.id]); setSessionCookie(res, createSession(user.id)); res.status(201).json({ user: { id: user.id, email: email.toLowerCase(), role: 'customer' } }); });
const adminRegistrationAttempts = new Map();
app.post('/api/auth/admin-register', (req, res) => {
  const { name, email, password, invite_key: inviteKey } = req.body || {};
  const configured = process.env.ADMIN_INVITE_KEY;
  // Kunci harus benar-benar dikonfigurasi, bukan nilai contoh, dan cukup panjang.
  if (!configured || configured === 'change-this-invite-key' || configured === 'admin-registration-secret' || configured.length < 16) {
    return res.status(503).json({ error: 'Registrasi admin belum dikonfigurasi' });
  }
  const ip = req.ip || 'unknown';
  const now = Date.now();
  const entry = adminRegistrationAttempts.get(ip) || { started: now, count: 0 };
  if (now - entry.started > 60 * 60 * 1000) { entry.started = now; entry.count = 0; }
  entry.count += 1;
  adminRegistrationAttempts.set(ip, entry);
  if (entry.count > 5) return res.status(429).json({ error: 'Terlalu banyak percobaan registrasi admin' });
  // Bandingkan dalam waktu konstan supaya tidak bisa ditebak lewat timing.
  const provided = Buffer.from(String(inviteKey || ''));
  const expected = Buffer.from(configured);
  const keyOk = provided.length === expected.length && crypto.timingSafeEqual(provided, expected);
  if (!keyOk) return res.status(403).json({ error: 'Admin invite key tidak valid' });
  if (!name || !email || !password || password.length < 8) return res.status(400).json({ error: 'Nama, email, dan password minimal 8 karakter wajib diisi' });
  const normalizedEmail = email.toLowerCase();
  if (one('SELECT id FROM users WHERE email=?', [normalizedEmail])) return res.status(409).json({ error: 'Email sudah terdaftar' });
  const customer = run('INSERT INTO customers (name,email,company_name) VALUES (?,?,?)', [name.trim(), normalizedEmail, 'Atandra Textile Supply']);
  const user = run('INSERT INTO users (email,password_hash,role,customer_id) VALUES (?,?,?,?)', [normalizedEmail, hashPassword(password), 'admin', customer.id]);
  setSessionCookie(res, createSession(user.id));
  console.warn(`[security] admin baru didaftarkan: ${normalizedEmail} dari ${ip}`);
  res.status(201).json({ user: { id: user.id, email: normalizedEmail, role: 'admin' } });
});
app.post('/api/auth/login', (req, res) => { const { email, password } = req.body || {}; const user = one('SELECT * FROM users WHERE email=? AND active=1', [String(email || '').toLowerCase()]); if (!user || !verifyPassword(password, user.password_hash)) return res.status(401).json({ error: 'Email atau password salah' }); setSessionCookie(res, createSession(user.id)); res.json({ user: { id: user.id, email: user.email, role: user.role } }); });
app.post('/api/auth/logout', (req, res) => { const user = currentUser(req); if (user) { const token = req.headers.cookie?.split(';').find((item) => item.trim().startsWith('atandra_session='))?.split('=')[1]; if (token) run('DELETE FROM sessions WHERE token=?', [decodeURIComponent(token)]); } clearSessionCookie(res); res.status(204).end(); });
app.get('/api/auth/me', requireAuth, (req, res) => res.json({ user: req.user }));
// Ganti password sendiri. Rate limit terpisah (5 gagal / 15 menit per IP) supaya
// endpoint ini tidak jadi alat brute-force password sekarang dari sesi yang dicuri.
// Yang dihitung hanya percobaan GAGAL — request valid tidak menghukum user.
const passwordChangeFailures = new Map();
function notePasswordFailure(ip) {
  const now = Date.now();
  const entry = passwordChangeFailures.get(ip) || { started: now, count: 0 };
  if (now - entry.started > 15 * 60 * 1000) { entry.started = now; entry.count = 0; }
  entry.count += 1;
  passwordChangeFailures.set(ip, entry);
  return entry.count;
}
function passwordChangeBlocked(ip) {
  const entry = passwordChangeFailures.get(ip);
  if (!entry) return false;
  if (Date.now() - entry.started > 15 * 60 * 1000) { passwordChangeFailures.delete(ip); return false; }
  return entry.count >= 5;
}
app.post('/api/auth/change-password', requireAuth, (req, res) => {
  const ip = req.ip || 'unknown';
  if (passwordChangeBlocked(ip)) return res.status(429).json({ error: 'Terlalu banyak percobaan ganti password' });
  const { current_password: currentPassword, new_password: newPassword } = req.body || {};
  if (!currentPassword || !newPassword) return res.status(400).json({ error: 'Password sekarang dan password baru wajib diisi' });
  const result = changePassword(req.user.id, currentPassword, newPassword);
  if (!result.ok) {
    if (result.code === 401) notePasswordFailure(ip);
    return res.status(result.code).json({ error: result.error });
  }
  // Semua sesi sudah digugurkan di changePassword, termasuk yang sedang dipakai.
  clearSessionCookie(res);
  res.status(204).end();
});
app.get('/api/categories', (_req, res) => res.json(all('SELECT * FROM categories ORDER BY name')));
app.get('/api/products', (req, res) => { const { clause, params } = productWhere(req.query); const products = all(`${productSelect} WHERE ${clause} GROUP BY p.id ORDER BY p.featured DESC, p.created_at DESC`, params).map(serializeProduct); res.json({ products, total: products.length }); });
app.get('/api/products/:slug', (req, res) => { const product = one(`${productSelect} WHERE p.slug=? GROUP BY p.id`, [req.params.slug]); if (!product) return res.status(404).json({ error: 'Product tidak ditemukan' }); const variants = all('SELECT v.*, c.name AS color, c.code AS color_code, inv.stock, inv.reserved_stock, inv.stock-inv.reserved_stock AS available_stock FROM product_variants v JOIN colors c ON c.id=v.color_id JOIN inventory inv ON inv.variant_id=v.id WHERE v.product_id=? AND v.active=1 ORDER BY v.id', [product.id]); const tiers = all('SELECT * FROM price_tiers WHERE product_id=? ORDER BY min_quantity', [product.id]); const images = all('SELECT url, alt FROM product_images WHERE product_id=? ORDER BY sort_order', [product.id]); res.json({ product: { ...serializeProduct(product), variants, tiers, images } }); });
app.get('/api/shipping/quote', (req, res) => res.json(shipping.quote({ quantity: Number(req.query.quantity || 1), city: req.query.city || '' })));
// Quote pesanan dari SERVER: subtotal (dengan harga tier) + ongkir + total.
// Tanpa efek samping (tidak membuat order / menyentuh stok). Checkout memakai ini
// supaya angka yang dilihat pelanggan = angka yang ditagih.
app.post('/api/checkout/quote', (req, res) => {
  try {
    const { items = [], city = '' } = req.body || {};
    if (!Array.isArray(items) || !items.length) return res.status(400).json({ error: 'Item wajib diisi' });
    res.json(quoteOrder(items, city));
  } catch (error) { res.status(400).json({ error: error.message }); }
});

app.post('/api/orders', (req, res) => {
  try {
    const { customer = {}, address = {}, items = [], notes = '' } = req.body;
    if (!items.length || !customer.name || !customer.email || !address.address || !address.city) return res.status(400).json({ error: 'Data customer, alamat, dan item wajib diisi' });
    const result = transaction(() => {
      let customerRow = one('SELECT id FROM customers WHERE email=?', [customer.email]);
      if (!customerRow) customerRow = run('INSERT INTO customers (name,email,phone,company_name) VALUES (?,?,?,?)', [customer.name, customer.email, customer.phone || '', customer.company_name || '']);
      const addressRow = run('INSERT INTO addresses (customer_id,full_name,phone,address,province,city,district,postal_code) VALUES (?,?,?,?,?,?,?,?)', [customerRow.id, customer.name, customer.phone || '', address.address, address.province || '', address.city, address.district || '', address.postal_code || '']);
          const { expanded, subtotal, ship } = quoteFromExpanded(expandItems(items), address.city); const orderNumber = `AT-${new Date().toISOString().slice(0, 10).replaceAll('-', '')}-${String((one('SELECT COUNT(*) AS total FROM orders')?.total || 0) + 1).padStart(4, '0')}`; const order = run('INSERT INTO orders (order_number,customer_id,address_id,subtotal,shipping,total,notes) VALUES (?,?,?,?,?,?,?)', [orderNumber, customerRow.id, addressRow.id, subtotal, ship.cost, subtotal + ship.cost, notes]); expanded.forEach((item) => { run('INSERT INTO order_items (order_id,variant_id,product_name,variant_name,sku,quantity,unit_price,subtotal) VALUES (?,?,?,?,?,?,?,?)', [order.id, item.id, item.product_name, item.variant_name, item.sku, item.quantity, item.unit_price, item.unit_price * item.quantity]); run('UPDATE inventory SET reserved_stock=reserved_stock+? WHERE variant_id=?', [item.quantity, item.id]); }); const paymentData = payment.createPayment({ orderNumber, amount: subtotal + ship.cost }); run('INSERT INTO payments (order_id,provider,provider_reference,amount) VALUES (?,?,?,?)', [order.id, paymentData.provider, paymentData.reference, paymentData.amount]); run('INSERT INTO shipments (order_id,method,cost,estimated_days) VALUES (?,?,?,?)', [order.id, ship.method, ship.cost, ship.estimatedDays]); notifications.emit('new_order', { orderNumber, total: subtotal + ship.cost }); return { orderId: order.id, orderNumber, total: subtotal + ship.cost, payment: paymentData, shipping: ship };
    });
    res.status(201).json(result);
  } catch (error) { res.status(400).json({ error: error.message }); }
});
// Order detail. Guest boleh cek status pesanannya (tanpa data pribadi);
// detail lengkap (nama/email/telepon/alamat) hanya untuk pemilik atau admin.
app.get('/api/orders/:id', (req, res) => {
  const order = one('SELECT * FROM orders WHERE id=? OR order_number=?', [req.params.id, req.params.id]);
  if (!order) return res.status(404).json({ error: 'Order tidak ditemukan' });
  const items = all('SELECT product_name, variant_name, sku, quantity, unit_price, subtotal FROM order_items WHERE order_id=?', [order.id]);
  const user = currentUser(req);
  const isOwner = Boolean(user && order.customer_id && user.customer_id === order.customer_id);
  const isAdmin = Boolean(user && user.role === 'admin');
  const base = {
    order_number: order.order_number,
    status: order.status,
    subtotal: order.subtotal,
    discount: order.discount,
    shipping: order.shipping,
    total: order.total,
    tracking_number: order.tracking_number,
    created_at: order.created_at,
    updated_at: order.updated_at,
  };
  if (!isOwner && !isAdmin) return res.json({ order: base, items });
  const detail = one('SELECT o.*, c.name AS customer_name,c.email,c.phone,a.full_name,a.address,a.province,a.city,a.district,a.postal_code,p.status AS payment_status,p.provider_reference,s.method,s.estimated_days,s.tracking_number FROM orders o LEFT JOIN customers c ON c.id=o.customer_id LEFT JOIN addresses a ON a.id=o.address_id LEFT JOIN payments p ON p.order_id=o.id LEFT JOIN shipments s ON s.order_id=o.id WHERE o.id=?', [order.id]);
  res.json({ order: detail, items: all('SELECT * FROM order_items WHERE order_id=?', [order.id]) });
});
app.post('/api/orders/:id/mock-payment', (req, res) => {
  // Hanya untuk pengembangan lokal. Tolak kalau production, atau kalau
  // DEV_PAYMENT_KEY tidak di-set, masih nilai default, atau terlalu pendek.
  const key = process.env.DEV_PAYMENT_KEY;
  if (process.env.NODE_ENV === 'production' || !key || key === 'local-only' || key.length < 12) {
    return res.status(404).json({ error: 'Endpoint tidak tersedia' });
  }
  if (req.headers['x-dev-payment-key'] !== key) return res.status(404).json({ error: 'Endpoint tidak tersedia' });
  const order = one('SELECT * FROM orders WHERE id=? OR order_number=?', [req.params.id, req.params.id]);
  if (!order) return res.status(404).json({ error: 'Order tidak ditemukan' });
  transaction(() => { run("UPDATE payments SET status='paid',paid_at=CURRENT_TIMESTAMP WHERE order_id=?", [order.id]); run("UPDATE orders SET status='paid',updated_at=CURRENT_TIMESTAMP WHERE id=?", [order.id]); all('SELECT variant_id,quantity FROM order_items WHERE order_id=?', [order.id]).forEach((item) => run('UPDATE inventory SET stock=stock-?,reserved_stock=reserved_stock-? WHERE variant_id=?', [item.quantity, item.quantity, item.variant_id])); });
  notifications.emit('payment_received', { orderNumber: order.order_number });
  res.json({ ok: true, status: 'paid' });
});
app.get('/api/account/profile', requireAuth, (req, res) => { const customer = one('SELECT id,name,email,phone,company_name,created_at FROM customers WHERE id=?', [req.user.customer_id]); if (!customer) return res.status(404).json({ error: 'Profil customer tidak ditemukan' }); res.json({ customer }); });
app.patch('/api/account/profile', requireAuth, (req, res) => { const { name, phone = '', company_name = '' } = req.body || {}; if (!name?.trim()) return res.status(400).json({ error: 'Nama wajib diisi' }); run('UPDATE customers SET name=?,phone=?,company_name=? WHERE id=?', [name.trim(), phone.trim(), company_name.trim(), req.user.customer_id]); res.json({ customer: one('SELECT id,name,email,phone,company_name,created_at FROM customers WHERE id=?', [req.user.customer_id]) }); });
app.get('/api/account/addresses', requireAuth, (req, res) => res.json({ addresses: all('SELECT * FROM addresses WHERE customer_id=? ORDER BY id DESC', [req.user.customer_id]) }));
app.post('/api/account/addresses', requireAuth, (req, res) => { const { full_name, phone, address, province, city, district, postal_code } = req.body || {}; if (![full_name, phone, address, province, city, district, postal_code].every((value) => String(value || '').trim())) return res.status(400).json({ error: 'Alamat belum lengkap' }); const created = run('INSERT INTO addresses (customer_id,full_name,phone,address,province,city,district,postal_code) VALUES (?,?,?,?,?,?,?,?)', [req.user.customer_id, full_name.trim(), phone.trim(), address.trim(), province.trim(), city.trim(), district.trim(), postal_code.trim()]); res.status(201).json({ address: one('SELECT * FROM addresses WHERE id=?', [created.id]) }); });
app.patch('/api/account/addresses/:id', requireAuth, (req, res) => { const fields = ['full_name', 'phone', 'address', 'province', 'city', 'district', 'postal_code'].filter((field) => req.body?.[field] !== undefined); if (!fields.length) return res.status(400).json({ error: 'Tidak ada perubahan alamat' }); if (!one('SELECT id FROM addresses WHERE id=? AND customer_id=?', [req.params.id, req.user.customer_id])) return res.status(404).json({ error: 'Alamat tidak ditemukan' }); run(`UPDATE addresses SET ${fields.map((field) => `${field}=?`).join(',')} WHERE id=? AND customer_id=?`, [...fields.map((field) => req.body[field]), req.params.id, req.user.customer_id]); res.json({ address: one('SELECT * FROM addresses WHERE id=?', [req.params.id]) }); });
app.delete('/api/account/addresses/:id', requireAuth, (req, res) => { run('DELETE FROM addresses WHERE id=? AND customer_id=?', [req.params.id, req.user.customer_id]); res.status(204).end(); });
app.get('/api/account/orders', requireAuth, (req, res) => res.json({ orders: all('SELECT o.order_number,o.status,o.subtotal,o.shipping,o.total,o.tracking_number,o.created_at,p.status AS payment_status,s.status AS shipment_status FROM orders o LEFT JOIN payments p ON p.order_id=o.id LEFT JOIN shipments s ON s.order_id=o.id WHERE o.customer_id=? ORDER BY o.created_at DESC', [req.user.customer_id]) }));
app.get('/api/account/orders/:id', requireAuth, (req, res) => { const order = one('SELECT o.*,a.full_name,a.phone,a.address,a.province,a.city,a.district,a.postal_code,p.status AS payment_status,p.provider_reference,s.method,s.estimated_days,s.status AS shipment_status,s.tracking_number FROM orders o LEFT JOIN addresses a ON a.id=o.address_id LEFT JOIN payments p ON p.order_id=o.id LEFT JOIN shipments s ON s.order_id=o.id WHERE (o.id=? OR o.order_number=?) AND o.customer_id=?', [req.params.id, req.params.id, req.user.customer_id]); if (!order) return res.status(404).json({ error: 'Order tidak ditemukan' }); res.json({ order, items: all('SELECT * FROM order_items WHERE order_id=?', [order.id]) }); });
app.post('/api/account/orders/:id/reorder', requireAuth, (req, res) => { const order = one('SELECT id FROM orders WHERE (id=? OR order_number=?) AND customer_id=?', [req.params.id, req.params.id, req.user.customer_id]); if (!order) return res.status(404).json({ error: 'Order tidak ditemukan' }); const items = all('SELECT oi.variant_id,oi.quantity,v.active,v.price,c.name AS color,p.name AS product_name,i.url AS image,inv.stock,inv.reserved_stock FROM order_items oi JOIN product_variants v ON v.id=oi.variant_id JOIN products p ON p.id=v.product_id JOIN colors c ON c.id=v.color_id LEFT JOIN product_images i ON i.product_id=p.id AND i.sort_order=0 JOIN inventory inv ON inv.variant_id=v.id WHERE oi.order_id=?', [order.id]).map((item) => ({ variant_id: item.variant_id, quantity: Math.min(item.quantity, Math.max(0, item.stock - item.reserved_stock)), available: Boolean(item.active), product_name: item.product_name, variant_name: `${item.product_name} — ${item.color}`, price: item.price, image: item.image })); res.json({ items: items.filter((item) => item.available && item.quantity > 0) }); });
const adminOnly = [requireAuth, requireRole('admin')];
app.get('/api/admin/categories', ...adminOnly, (_req, res) => res.json({ categories: all('SELECT * FROM categories ORDER BY name') }));
app.get('/api/admin/colors', ...adminOnly, (_req, res) => res.json({ colors: all('SELECT * FROM colors ORDER BY name') }));
app.post('/api/admin/colors', ...adminOnly, (req, res) => { const { name, code } = req.body || {}; if (!name || !code) return res.status(400).json({ error: 'Nama dan kode warna wajib diisi' }); try { const color = run('INSERT INTO colors (name,code) VALUES (?,?)', [name.trim(), code.trim().toUpperCase()]); res.status(201).json({ color: one('SELECT * FROM colors WHERE id=?', [color.id]) }); } catch { res.status(409).json({ error: 'Kode warna sudah digunakan' }); } });
app.post('/api/admin/categories', ...adminOnly, (req, res) => { const { name, slug } = req.body || {}; if (!name || !slug) return res.status(400).json({ error: 'Nama dan slug kategori wajib diisi' }); try { const category = run('INSERT INTO categories (name,slug) VALUES (?,?)', [name.trim(), slug.trim().toLowerCase()]); res.status(201).json({ category: one('SELECT * FROM categories WHERE id=?', [category.id]) }); } catch (error) { res.status(409).json({ error: 'Slug kategori sudah digunakan' }); } });
app.patch('/api/admin/categories/:id', ...adminOnly, (req, res) => { const { name, slug } = req.body || {}; if (!name || !slug) return res.status(400).json({ error: 'Nama dan slug kategori wajib diisi' }); try { run('UPDATE categories SET name=?,slug=? WHERE id=?', [name.trim(), slug.trim().toLowerCase(), req.params.id]); res.json({ ok: true }); } catch { res.status(409).json({ error: 'Slug kategori sudah digunakan' }); } });

// ---- Kelola kategori & warna (plan 0006, fase 2C) ----
// Hapus DITOLAK kalau masih dipakai. Kategori dipakai products.category_id
// (NOT NULL, tanpa ON DELETE), warna dipakai product_variants.color_id. Hapus
// paksa akan meninggalkan produk/varian dengan rujukan yang tidak ada — lebih
// baik tolak dan beri tahu berapa yang memakai daripada data jadi yatim.
//
// Hitung pemakai dulu supaya pesan errornya berguna ("dipakai 11 produk"), dan
// supaya admin bisa memutuskan: pindahkan dulu, baru hapus.
app.get('/api/admin/catalog', ...adminOnly, (_req, res) => res.json({
  categories: all(`SELECT c.*, COUNT(p.id) AS usage_count FROM categories c LEFT JOIN products p ON p.category_id=c.id GROUP BY c.id ORDER BY c.name`),
  colors: all(`SELECT c.*, COUNT(v.id) AS usage_count FROM colors c LEFT JOIN product_variants v ON v.color_id=c.id GROUP BY c.id ORDER BY c.name`),
}));

app.patch('/api/admin/colors/:id', ...adminOnly, (req, res) => {
  const { name, code } = req.body || {};
  if (!name || !code) return res.status(400).json({ error: 'Nama dan kode warna wajib diisi' });
  if (!one('SELECT id FROM colors WHERE id=?', [req.params.id])) return res.status(404).json({ error: 'Warna tidak ditemukan' });
  try { run('UPDATE colors SET name=?,code=? WHERE id=?', [name.trim(), code.trim().toUpperCase(), req.params.id]); res.json({ ok: true }); }
  catch { res.status(409).json({ error: 'Kode warna sudah digunakan' }); }
});

app.delete('/api/admin/categories/:id', ...adminOnly, (req, res) => {
  if (!one('SELECT id FROM categories WHERE id=?', [req.params.id])) return res.status(404).json({ error: 'Kategori tidak ditemukan' });
  const used = one('SELECT COUNT(*) AS value FROM products WHERE category_id=?', [req.params.id]).value;
  if (used) return res.status(409).json({ error: `Kategori masih dipakai ${used} produk. Pindahkan produk itu dulu.`, usage_count: used });
  run('DELETE FROM categories WHERE id=?', [req.params.id]);
  res.json({ ok: true });
});

app.delete('/api/admin/colors/:id', ...adminOnly, (req, res) => {
  if (!one('SELECT id FROM colors WHERE id=?', [req.params.id])) return res.status(404).json({ error: 'Warna tidak ditemukan' });
  const used = one('SELECT COUNT(*) AS value FROM product_variants WHERE color_id=?', [req.params.id]).value;
  if (used) return res.status(409).json({ error: `Warna masih dipakai ${used} varian. Pindahkan varian itu dulu.`, usage_count: used });
  run('DELETE FROM colors WHERE id=?', [req.params.id]);
  res.json({ ok: true });
});
app.get('/api/admin/products', ...adminOnly, (_req, res) => res.json({ products: all(`${productSelect} GROUP BY p.id ORDER BY p.created_at DESC`).map(serializeProduct) }));
app.post('/api/admin/products', ...adminOnly, (req, res) => { const body = req.body || {}; const requiredFields = { category_id: 'Kategori', name: 'Nama', slug: 'Slug', sku: 'SKU', description: 'Deskripsi', material: 'Material', construction: 'Construction', gsm: 'GSM', width: 'Lebar', weight_per_yard: 'Berat/yard', recommended_usage: 'Rekomendasi pemakaian' }; const missing = Object.keys(requiredFields).filter((key) => !body[key]); if (missing.length) return res.status(400).json({ error: `Field belum lengkap: ${missing.map((key) => requiredFields[key]).join(', ')}`, missing }); const { category_id, name, slug, sku, description, material, construction, gsm, width, weight_per_yard, recommended_usage, status = 'draft', image = '/img/fabric-hero.png' } = body; const moq = Math.max(1, Number(body.moq) || 1); const sampleAvailable = flagValue(body.sample_available, 1); const featured = flagValue(body.featured, 0); const bestseller = flagValue(body.bestseller, 0); try { const product = run('INSERT INTO products (category_id,name,slug,sku,description,material,construction,gsm,width,weight_per_yard,recommended_usage,moq,sample_available,status,featured,bestseller) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)', [category_id, name.trim(), slug.trim(), sku.trim(), description, material, construction, gsm, width, weight_per_yard, recommended_usage, moq, sampleAvailable, status, featured, bestseller]); run('INSERT INTO product_images (product_id,url,alt,sort_order) VALUES (?,?,?,0)', [product.id, image, name]); res.status(201).json({ product: one('SELECT * FROM products WHERE id=?', [product.id]) }); } catch (error) { res.status(409).json({ error: 'Slug atau SKU produk sudah digunakan' }); } });
app.patch('/api/admin/products/:id', ...adminOnly, (req, res) => { const allowed = ['name', 'slug', 'sku', 'description', 'material', 'construction', 'gsm', 'width', 'weight_per_yard', 'recommended_usage', 'moq', 'sample_available', 'status', 'featured', 'bestseller', 'category_id']; const fields = allowed.filter((field) => req.body?.[field] !== undefined); if (!fields.length) return res.status(400).json({ error: 'Tidak ada field yang diubah' }); const values = fields.map((field) => req.body[field]); run(`UPDATE products SET ${fields.map((field) => `${field}=?`).join(',')},updated_at=CURRENT_TIMESTAMP WHERE id=?`, [...values, req.params.id]); res.json({ ok: true }); });
app.delete('/api/admin/products/:id', ...adminOnly, (req, res) => { run("UPDATE products SET status='archived',updated_at=CURRENT_TIMESTAMP WHERE id=?", [req.params.id]); res.json({ ok: true, status: 'archived' }); });
app.get('/api/admin/products/:id/variants', ...adminOnly, (req, res) => res.json({ variants: all('SELECT v.*,c.name AS color,c.code AS color_code,inv.stock,inv.reserved_stock,inv.stock-inv.reserved_stock AS available_stock,inv.low_stock_threshold,(inv.stock-inv.reserved_stock)<=inv.low_stock_threshold AS low_stock FROM product_variants v JOIN colors c ON c.id=v.color_id JOIN inventory inv ON inv.variant_id=v.id WHERE v.product_id=? ORDER BY v.id', [req.params.id]).map((variant) => ({ ...variant, low_stock: Boolean(variant.low_stock) })) }));
app.post('/api/admin/products/:id/variants', ...adminOnly, (req, res) => { const { color_id, sku, price, wholesale_price, stock = 0, low_stock_threshold = 5 } = req.body || {}; if (!color_id || !sku || price === undefined || wholesale_price === undefined) return res.status(400).json({ error: 'Variant belum lengkap' }); try { const variant = run('INSERT INTO product_variants (product_id,color_id,sku,price,wholesale_price) VALUES (?,?,?,?,?)', [req.params.id, color_id, sku, price, wholesale_price]); run('INSERT INTO inventory (variant_id,stock,low_stock_threshold) VALUES (?,?,?)', [variant.id, stock, low_stock_threshold]); res.status(201).json({ variant: one('SELECT * FROM product_variants WHERE id=?', [variant.id]) }); } catch { res.status(409).json({ error: 'SKU variant sudah digunakan' }); } });
app.patch('/api/admin/variants/:id', ...adminOnly, (req, res) => { const fields = ['sku', 'price', 'wholesale_price', 'active'].filter((field) => req.body?.[field] !== undefined); if (!fields.length) return res.status(400).json({ error: 'Tidak ada field variant yang diubah' }); run(`UPDATE product_variants SET ${fields.map((field) => `${field}=?`).join(',')} WHERE id=?`, [...fields.map((field) => req.body[field]), req.params.id]); res.json({ ok: true }); });
// Catatan: sql.js melempar kalau ada parameter `undefined`, jadi low_stock_threshold
// dinormalkan ke null dulu supaya COALESCE(?, low_stock_threshold) tetap jalan.
app.patch('/api/admin/inventory/:variantId', ...adminOnly, (req, res) => { const { stock, low_stock_threshold } = req.body || {}; if (stock === undefined || Number(stock) < 0) return res.status(400).json({ error: 'Stock harus berupa angka positif' }); const current = one('SELECT reserved_stock FROM inventory WHERE variant_id=?', [req.params.variantId]); if (!current || Number(stock) < current.reserved_stock) return res.status(400).json({ error: 'Stock tidak boleh lebih kecil dari reserved stock' }); const threshold = low_stock_threshold === undefined || low_stock_threshold === null || low_stock_threshold === '' ? null : Number(low_stock_threshold); if (threshold !== null && (!Number.isInteger(threshold) || threshold < 0)) return res.status(400).json({ error: 'Ambang stok menipis harus bilangan bulat >= 0' }); run('UPDATE inventory SET stock=?,low_stock_threshold=COALESCE(?,low_stock_threshold) WHERE variant_id=?', [Number(stock), threshold, req.params.variantId]); res.json({ ok: true }); });

// ---- Bulk ubah harga ----
// Satu request untuk banyak varian. Dipakai saat harga kain naik/turun; mengubah
// 44 varian satu per satu bukan pilihan.
//
// mode:  set → value | percent → lama x (1+value/100) | amount → lama + value
// field: price | wholesale_price | both
//
// Semua dihitung DULU; kalau ada satu saja yang jadi <= 0, tidak ada yang berubah
// (400). Setengah jalan lebih buruk daripada tidak jalan sama sekali.
app.post('/api/admin/variants/bulk-price', ...adminOnly, (req, res) => {
  const { variant_ids: variantIds, mode, value, field = 'price' } = req.body || {};
  if (!Array.isArray(variantIds) || !variantIds.length) return res.status(400).json({ error: 'Pilih minimal satu varian' });
  if (!['set', 'percent', 'amount'].includes(mode)) return res.status(400).json({ error: 'Mode harus set, percent, atau amount' });
  if (!['price', 'wholesale_price', 'both'].includes(field)) return res.status(400).json({ error: 'Field harga tidak valid' });
  const amount = Number(value);
  if (!Number.isFinite(amount)) return res.status(400).json({ error: 'Nilai harus berupa angka' });
  if (mode === 'set' && amount <= 0) return res.status(400).json({ error: 'Harga harus lebih dari 0' });
  if (mode === 'percent' && amount <= -100) return res.status(400).json({ error: 'Persentase tidak boleh -100% atau kurang' });

  const ids = [...new Set(variantIds.map(Number).filter((id) => Number.isInteger(id) && id > 0))];
  if (!ids.length) return res.status(400).json({ error: 'ID varian tidak valid' });
  const rows = all(`SELECT id, price, wholesale_price FROM product_variants WHERE id IN (${ids.map(() => '?').join(',')})`, ids);
  if (!rows.length) return res.status(404).json({ error: 'Varian tidak ditemukan' });

  const columns = field === 'both' ? ['price', 'wholesale_price'] : [field];
  const next = (old) => mode === 'set' ? amount : mode === 'percent' ? Math.round(old * (1 + amount / 100)) : Math.round(old + amount);

  const changes = [];
  for (const row of rows) {
    const change = { id: row.id, before: {}, after: {} };
    for (const column of columns) {
      const before = Number(row[column]);
      const after = next(before);
      if (!Number.isFinite(after) || after <= 0) return res.status(400).json({ error: `Harga varian #${row.id} jadi ${after} - dibatalkan, tidak ada yang diubah` });
      change.before[column] = before;
      change.after[column] = after;
    }
    changes.push(change);
  }

  if (req.body?.dry_run) return res.json({ updated: changes.length, field, mode, changes, dry_run: true });

  transaction(() => changes.forEach((change) => {
    run(`UPDATE product_variants SET ${columns.map((column) => `${column}=?`).join(',')} WHERE id=?`, [...columns.map((column) => change.after[column]), change.id]);
  }));
  res.json({ updated: changes.length, field, mode, changes });
});
app.put('/api/admin/products/:id/pricing', ...adminOnly, (req, res) => { const tiers = Array.isArray(req.body?.tiers) ? req.body.tiers : []; if (!tiers.length || tiers.some((tier) => Number(tier.min_quantity) < 1 || Number(tier.price) < 0)) return res.status(400).json({ error: 'Pricing tier tidak valid' }); transaction(() => { run('DELETE FROM price_tiers WHERE product_id=?', [req.params.id]); tiers.forEach((tier) => run('INSERT INTO price_tiers (product_id,min_quantity,max_quantity,price,label) VALUES (?,?,?,?,?)', [req.params.id, tier.min_quantity, tier.max_quantity || null, tier.price, tier.label || `${tier.min_quantity}+ roll`])); }); res.json({ tiers: all('SELECT * FROM price_tiers WHERE product_id=? ORDER BY min_quantity', [req.params.id]) }); });
app.patch('/api/admin/orders/:id', ...adminOnly, (req, res) => { const statuses = ['pending_payment', 'paid', 'processing', 'packed', 'shipped', 'completed', 'cancelled', 'refunded']; const { status, tracking_number } = req.body || {}; if (!statuses.includes(status)) return res.status(400).json({ error: 'Status order tidak valid' }); transaction(() => { run('UPDATE orders SET status=?,tracking_number=COALESCE(?,tracking_number),updated_at=CURRENT_TIMESTAMP WHERE id=?', [status, tracking_number || null, req.params.id]); run('UPDATE shipments SET status=?,tracking_number=COALESCE(?,tracking_number) WHERE order_id=?', [status === 'shipped' ? 'shipped' : status, tracking_number || null, req.params.id]); // Sinkronkan payments.status dengan status order (satu peta). Tanpa ini, KPI
    // 'Menunggu bayar' menghitung order yang sudah refund/batal — angka bohong.
    const payStatus = paymentStatusForOrderStatus(status); run("UPDATE payments SET status=?,paid_at=CASE WHEN ?='paid' AND paid_at IS NULL THEN CURRENT_TIMESTAMP ELSE paid_at END WHERE order_id=?", [payStatus, payStatus, req.params.id]); }); notifications.emit('order_status_changed', { orderId: req.params.id, status }); res.json({ ok: true }); });

// ---- Upload gambar produk ----
// Body mentah (bukan multipart) supaya tidak perlu dependency baru; satu request
// = satu file. Jenis file ditentukan dari magic bytes di server/uploads.js,
// bukan dari Content-Type yang bisa dipalsukan klien.
const imageBody = express.raw({ type: () => true, limit: MAX_UPLOAD_BYTES });
app.post('/api/admin/uploads', ...adminOnly, imageBody, async (req, res) => {
  const buffer = req.body;
  if (!Buffer.isBuffer(buffer) || !buffer.length) return res.status(400).json({ error: 'Tidak ada file yang dikirim.' });
  const result = await saveImage(buffer, here);
  if (result.error) return res.status(400).json({ error: result.error });
  res.status(201).json(result);
});
app.get('/api/admin/uploads', ...adminOnly, (_req, res) => res.json({ files: listUploads(here) }));
app.delete('/api/admin/uploads/:name', ...adminOnly, (req, res) => { const result = removeImage(req.params.name, here); if (result.error) return res.status(result.status || 400).json({ error: result.error }); res.json({ ok: true }); });

// Galeri: satu produk boleh punya banyak gambar, urut sort_order.
app.get('/api/admin/products/:id/images', ...adminOnly, (req, res) => res.json({ images: all('SELECT id,url,alt,sort_order FROM product_images WHERE product_id=? ORDER BY sort_order,id', [req.params.id]) }));
app.post('/api/admin/products/:id/images', ...adminOnly, (req, res) => {
  const { url, alt = '' } = req.body || {};
  if (!one('SELECT id FROM products WHERE id=?', [req.params.id])) return res.status(404).json({ error: 'Produk tidak ditemukan' });
  if (typeof url !== 'string' || !url.trim()) return res.status(400).json({ error: 'URL gambar wajib diisi' });
  // Hanya izinkan gambar yang kita layani sendiri atau sudah ada di galeri.
  if (!/^\/uploads\/[a-f0-9]{16,64}\.(jpg|png|webp)$/.test(url.trim()) && !/^\/img\/[\w.-]+$/.test(url.trim())) return res.status(400).json({ error: 'URL gambar tidak valid' });
  const next = one('SELECT COALESCE(MAX(sort_order),-1)+1 AS v FROM product_images WHERE product_id=?', [req.params.id]).v;
  const row = run('INSERT INTO product_images (product_id,url,alt,sort_order) VALUES (?,?,?,?)', [req.params.id, url.trim(), String(alt), next]);
  res.status(201).json({ id: row.id, url: url.trim(), alt: String(alt), sort_order: next });
});
app.delete('/api/admin/products/:id/images/:imageId', ...adminOnly, (req, res) => {
  const image = one('SELECT * FROM product_images WHERE id=? AND product_id=?', [req.params.imageId, req.params.id]);
  if (!image) return res.status(404).json({ error: 'Gambar tidak ditemukan' });
  run('DELETE FROM product_images WHERE id=?', [req.params.imageId]);
  // File fisik ikut dihapus hanya kalau tidak dipakai produk lain.
  if (String(image.url).startsWith('/uploads/')) {
    const stillUsed = one('SELECT id FROM product_images WHERE url=? LIMIT 1', [image.url]);
    if (!stillUsed) removeImage(String(image.url).replace('/uploads/', ''), here);
  }
  res.json({ ok: true });
});
// Jadikan gambar utama = sort_order 0, sisanya digeser.
app.patch('/api/admin/products/:id/images/:imageId/primary', ...adminOnly, (req, res) => {
  const image = one('SELECT * FROM product_images WHERE id=? AND product_id=?', [req.params.imageId, req.params.id]);
  if (!image) return res.status(404).json({ error: 'Gambar tidak ditemukan' });
  transaction(() => {
    run('UPDATE product_images SET sort_order=sort_order+1 WHERE product_id=?', [req.params.id]);
    run('UPDATE product_images SET sort_order=0 WHERE id=?', [req.params.imageId]);
  });
  res.json({ ok: true, primary: image.url });
});

app.get('/api/admin/dashboard', requireAuth, requireRole('admin'), (_req, res) => res.json({ sales: one("SELECT COALESCE(SUM(total),0) AS value FROM orders WHERE status NOT IN ('cancelled','pending_payment')").value, orders: one('SELECT COUNT(*) AS value FROM orders').value, pendingPayments: one("SELECT COUNT(*) AS value FROM payments WHERE status='pending'").value, lowStock: all('SELECT v.sku,p.name,c.name AS color,inv.stock-inv.reserved_stock AS available_stock FROM inventory inv JOIN product_variants v ON v.id=inv.variant_id JOIN products p ON p.id=v.product_id JOIN colors c ON c.id=v.color_id WHERE inv.stock-inv.reserved_stock<=inv.low_stock_threshold').length, samples: one("SELECT COUNT(*) AS value FROM sample_requests WHERE status='requested'").value }));
app.get('/api/admin/orders', requireAuth, requireRole('admin'), (_req, res) => res.json({ orders: all('SELECT o.*,c.name AS customer_name,c.email,p.status AS payment_status FROM orders o LEFT JOIN customers c ON c.id=o.customer_id LEFT JOIN payments p ON p.order_id=o.id ORDER BY o.created_at DESC') }));
app.post('/api/samples', (req, res) => { const { customer_name, email, phone, product_id, color, quantity = 1, address } = req.body; if (!customer_name || !email || !phone || !product_id || !color || !address) return res.status(400).json({ error: 'Data sample belum lengkap' }); const sample = run('INSERT INTO sample_requests (customer_name,email,phone,product_id,color,quantity,address) VALUES (?,?,?,?,?,?,?)', [customer_name, email, phone, product_id, color, quantity, address]); notifications.emit('sample_request', { id: sample.id, email }); res.status(201).json({ id: sample.id, status: 'requested' }); });

// ---- URL bersih: tabel route tipis ----
// Server tidak punya router halaman; ini satu-satunya tempat yang memetakan URL publik
// ke file di dist/. URL lama (.html) di-301 supaya bookmark lama tetap hidup.
// Detail di docs/architecture.md §"URL". Plan: plans/0004-clean-urls.md.
const PAGES = {
  '/': 'index.html',
  '/katalog': 'shop.html',
  '/produk': 'product.html',
  '/keranjang': 'checkout.html',
  '/akun': 'account.html',
  '/akun/pesanan': 'account-orders.html',
  '/akun/pesanan/lihat': 'account-order.html',
  '/admin': 'admin.html',
  '/admin/pesanan': 'admin-orders.html',
  '/admin/produk': 'admin-products.html',
};
const LEGACY = Object.fromEntries(Object.entries(PAGES).map(([clean, file]) => [`/${file}`, clean]));

// /index.html dan /index → / (perlakuan khusus, bukan di tabel)
app.get('/index.html', (req, res) => res.redirect(301, '/'));
app.get('/index', (req, res) => res.redirect(301, '/'));

// URL .html lama → URL bersih, query string dipertahankan
for (const [legacy, clean] of Object.entries(LEGACY)) {
  if (legacy === '/index.html') continue;
  app.get(legacy, (req, res) => {
    const query = req.originalUrl.includes('?') ? req.originalUrl.slice(req.originalUrl.indexOf('?')) : '';
    res.redirect(301, `${clean}${query}`);
  });
}

// URL bersih → kirim file dari dist/
const distDir = path.join(here, '..', 'dist');
for (const [clean, file] of Object.entries(PAGES)) {
  if (clean === '/') continue;
  app.get(clean, (_req, res) => res.sendFile(path.join(distDir, file)));
}

app.use(express.static(distDir));
app.use(express.static(path.join(here, '..', 'public')));
app.use((error, _req, res, _next) => { console.error(error); const status = error.status || error.statusCode || 500; const message = status === 413 ? 'File terlalu besar (maksimal 8 MB).' : 'Terjadi kesalahan pada server'; res.status(status).json({ error: message }); });
app.listen(port, () => console.log(`Atandra commerce running at http://localhost:${port}`));
