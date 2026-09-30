import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import initSqlJs from 'sql.js';

const require = createRequire(import.meta.url);
const here = path.dirname(fileURLToPath(import.meta.url));
const dataDir = path.join(here, '..', 'data');
const databaseFile = path.join(dataDir, 'atandra.sqlite');
const schemaFile = path.join(here, 'schema.sql');
const SQL = await initSqlJs({ locateFile: (file) => path.join(path.dirname(require.resolve('sql.js')), file) });
fs.mkdirSync(dataDir, { recursive: true });
export const db = fs.existsSync(databaseFile) ? new SQL.Database(fs.readFileSync(databaseFile)) : new SQL.Database();
db.run(fs.readFileSync(schemaFile, 'utf8'));
let inTransaction = false;

export function saveDatabase() { fs.writeFileSync(databaseFile, Buffer.from(db.export())); }
export function all(sql, params = []) { const statement = db.prepare(sql); statement.bind(params); const rows = []; while (statement.step()) rows.push(statement.getAsObject()); statement.free(); return rows; }
export function one(sql, params = []) { return all(sql, params)[0] ?? null; }
export function run(sql, params = []) { db.run(sql, params); const result = db.exec('SELECT last_insert_rowid() AS id'); const id = result[0]?.values[0]?.[0]; if (!inTransaction) saveDatabase(); return { id }; }
export function transaction(callback) { db.run('BEGIN'); inTransaction = true; try { const result = callback(); db.run('COMMIT'); inTransaction = false; saveDatabase(); return result; } catch (error) { inTransaction = false; try { db.run('ROLLBACK'); } catch { /* SQLite may already have rolled back the failed statement. */ } throw error; } }

function seed() {
  if (one('SELECT id FROM products LIMIT 1')) return;
  const existingCategory = one('SELECT id FROM categories WHERE slug=?', ['double-pique']);
  const category = existingCategory?.id || run('INSERT INTO categories (name, slug) VALUES (?, ?)', ['Double Pique', 'double-pique']).id;
  const colors = ['Hitam', 'Putih', 'Navy', 'Maroon'];
  colors.forEach((name, index) => run('INSERT OR IGNORE INTO colors (name, code) VALUES (?, ?)', [name, `CLR-${String(index + 1).padStart(2, '0')}`]));
  const colorRows = all('SELECT id FROM colors ORDER BY id');
  const products = [
    ['Double Pique 165 — Blend DTY', 'double-pique-165-blend-dty', 'TS.421124.165.62.P2', 'Polo perusahaan, seragam kerja, baju komunitas, dan atasan olahraga berstruktur.', 'DTY-100-96-1 (56%) + DTY-75-72 (44%)', 'Double Pique', 165, '157 cm / 62″', '237 g/yard', 'double-pique-165-blend.jpg', 1, 1],
    ['Double Pique 120 — DTY', 'double-pique-120-dty', 'TS.4221089.120.60.P2', 'Jersey latihan, polo cuaca panas, kaos olahraga ringan, dan apparel aktivitas.', 'DTY-75-72-1-SDC DH SIM (100%)', 'Double Pique', 120, '152 cm / 60″', '167 g/yard', 'double-pique-120.jpg', 1, 1],
    ['Double Pique 165 — Polyester', 'double-pique-165-polyester', 'TS.431072.165.61.P2', 'Polo promosi, seragam event, jersey polo, dan produksi massal dengan bidang kain lebar.', 'Polyester 100%', 'Double Pique', 165, '170 cm / 67″', '257 g/yard', 'double-pique-165-polyester.jpg', 1, 1],
    ['Double Pique 135 — DTY', 'double-pique-135-dty', 'TS.421109.135.62.P2', 'Polo harian, seragam lapangan, kaos event, dan sportswear ringan.', 'DTY-75-72-1-SDC DH SIM (100%)', 'Double Pique', 135, '157 cm / 62″', '194 g/yard', 'double-pique-135.jpg', 1, 1],
    ['Double Pique 150 — Soft', 'double-pique-150-soft', 'TS.421048.150.61.P2', 'Polo premium, pakaian kasual, seragam indoor, dan produk yang mengutamakan sentuhan lebih lembut.', 'DTY-75-72-1-SDC DH SIM (100%)', 'Double Pique', 150, '155 cm / 61″', '212 g/yard', 'double-pique-150-soft.jpg', 1, 0],
    ['Double Pique 170 — DTY', 'double-pique-170-dty', 'TS.421123.170.64.P2', 'Polo premium, seragam kerja, outer ringan, dan produk yang membutuhkan badan kain lebih kokoh.', 'DTY-100-96-1-SDC DH SIM (100%)', 'Double Pique', 170, '163 cm / 64″', '253 g/yard', 'double-pique-170.jpg', 1, 1],
    ['Double Pique 110 — Blend DTY', 'double-pique-110-blend-dty', 'TS.421126.110.62.P2', 'Jersey training, kaos aktivitas, polo sangat ringan, dan apparel untuk cuaca panas.', 'DTY-75-72-1-POLYFIN + DTY-50-36-1-SDC DH SIM', 'Double Pique', 110, '157 cm / 62″', '158 g/yard', 'double-pique-110.jpg', 1, 0],
    ['Double Pique 165 — Blend DTY Varian B', 'double-pique-165-blend-dty-varian-b', 'TS.421124.165.62.P2-B', 'Polo perusahaan, seragam kerja, baju komunitas, dan atasan olahraga berstruktur.', 'DTY-100-96-1 (56%) + DTY-75-72 (44%)', 'Double Pique', 165, '157 cm / 62″', '237 g/yard', 'double-pique-165-varian-b.jpg', 1, 0],
    ['Double Pique 150 — NIM/SIM', 'double-pique-150-nim-sim', 'TS.421153.150.64.P1', 'Polo komunitas, seragam kantor, sports casual, dan produksi yang memerlukan lebar 163 cm.', 'DTY-75-36-NIM + DTY-75-72-SIM', 'Double Pique', 150, '163 cm / 64″', '223 g/yard', 'double-pique-150-blend.jpg', 1, 0],
    ['Double Pique 150 — Polyfin', 'double-pique-150-polyfin', 'TS.421150.150.61.P2', 'Polo promosi, seragam event, kaos komunitas, dan produksi reguler berbobot medium.', 'DTY-75-72-1-POLYFIN (100%)', 'Double Pique', 150, '155 cm / 61″', '212 g/yard', 'double-pique-150-polyfin.jpg', 1, 0],
    ['Double Pique 160 — Polyester', 'double-pique-160-polyester', 'TS.421149.160.P1', 'Polo korporat, seragam sekolah, seragam lapangan, dan atasan olahraga dengan struktur medium.', 'Polyester 100%', 'Double Pique', 160, '155 cm / 61″', '227 g/yard', 'double-pique-160-polyester.jpg', 1, 0],
  ];
  transaction(() => products.forEach(([name, slug, sku, usage, material, construction, gsm, width, weight, image, featured, bestseller], index) => {
    const product = run('INSERT INTO products (category_id,name,slug,sku,description,material,construction,gsm,width,weight_per_yard,recommended_usage,featured,bestseller) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)', [category, name, slug, sku, usage, material, construction, gsm, width, weight, usage, featured, bestseller]);
    run('INSERT INTO product_images (product_id,url,alt,sort_order) VALUES (?,?,?,?)', [product.id, `/img/${image}`, name, 0]);
    colorRows.forEach((color, colorIndex) => {
      const variant = run('INSERT INTO product_variants (product_id,color_id,sku,price,wholesale_price) VALUES (?,?,?,?,?)', [product.id, color.id, `${sku}-${colorIndex + 1}`, 825000 + gsm * 1000, 775000 + gsm * 1000]);
      run('INSERT INTO inventory (variant_id,stock,reserved_stock,low_stock_threshold) VALUES (?,?,?,?)', [variant.id, 20 - Math.min(index, 8), 0, 5]);
    });
    [[1, 4, 825000 + gsm * 1000, 'Retail 1–4 roll'], [5, 19, 775000 + gsm * 1000, 'Wholesale 5–19 roll'], [20, 49, 735000 + gsm * 1000, 'Wholesale 20–49 roll'], [50, null, 695000 + gsm * 1000, 'Wholesale 50+ roll']].forEach((tier) => run('INSERT INTO price_tiers (product_id,min_quantity,max_quantity,price,label) VALUES (?,?,?,?,?)', [product.id, ...tier]));
  }));
}
seed(); saveDatabase();
