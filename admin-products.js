const api = async (path, options = {}) => { const response = await fetch(`/api${path}`, { credentials: 'include', ...options }); const data = await response.json(); if (!response.ok) throw new Error(data.error || 'Request gagal'); return data; };
// Escape teks sebelum masuk innerHTML (cegah XSS dari data produk/kategori/warna).
const esc = (value) => String(value ?? '').replace(/[&<>"']/g, (char) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[char]));
const message = (text, type = '') => { const node = document.querySelector('#products-message'); node.hidden = false; node.className = `notice ${type}`; node.textContent = text; };
// Status produk → label Indonesia + kelas badge (skema badge sama dengan halaman Pesanan).
const PRODUCT_STATUS = { active: 'Aktif', draft: 'Draf', archived: 'Diarsipkan', out_of_stock: 'Stok habis' };
const statusBadge = (status) => `<span class="badge badge--${esc(status)}">${esc(PRODUCT_STATUS[status] || status)}</span>`;

async function loadCatalog() {
  const [catalog, categories, colors] = await Promise.all([api('/admin/products'), api('/admin/categories'), api('/admin/colors')]);
  document.querySelector('#category-select').innerHTML = categories.categories.map((item) => `<option value="${Number(item.id)}">${esc(item.name)}</option>`).join('');
  document.querySelector('#color-select').innerHTML = colors.colors.map((item) => `<option value="${Number(item.id)}">${esc(item.name)} (${esc(item.code)})</option>`).join('');
  renderProducts(catalog.products);
}

function showWorkspace() {
  document.querySelector('#products-loading').hidden = true;
  document.querySelector('#products-auth').hidden = true;
  document.querySelector('#products-workspace').hidden = false;
}

// Dipanggil sekali setelah workspace tampil — kalau dipanggil dua kali
// (login ulang) listener form akan menumpuk, jadi kita jaga di sini.
let bound = false;
function bindAll() {
  if (bound) return;
  bound = true;
  bindProductForm();
  bindCatalogForms();
  bindImageUpload();
}

// ---- Upload gambar ----
// File dikirim sebagai body mentah (bukan multipart) supaya server tidak butuh
// dependency tambahan. Jenis file tetap divalidasi di server dari magic bytes.
function bindImageUpload() {
  const input = document.querySelector('#image-input');
  if (!input) return;
  input.addEventListener('change', async () => {
    const file = input.files?.[0];
    if (!file) return;
    const status = document.querySelector('#image-status');
    const preview = document.querySelector('#image-preview');
    const img = document.querySelector('#image-preview-img');

    // Pratinjau lokal duluan — pakai object URL supaya terasa instan.
    const localUrl = URL.createObjectURL(file);
    preview.hidden = false;
    img.src = localUrl;
    status.textContent = 'Mengunggah…';

    try {
      const response = await fetch('/api/admin/uploads', {
        method: 'POST',
        credentials: 'include',
        headers: { 'Content-Type': file.type || 'application/octet-stream' },
        body: file,
      });
      const data = await response.json();
      if (!response.ok) throw new Error(data.error || 'Upload gagal');

      document.querySelector('#image-url').value = data.url;
      img.src = data.url;                       // ganti ke versi server (sudah dikecilkan)
      URL.revokeObjectURL(localUrl);
      const saved = data.originalBytes > data.bytes ? ` · dikecilkan ${Math.round((1 - data.bytes / data.originalBytes) * 100)}%` : '';
      status.textContent = `Terunggah${saved}`;
      message('Gambar berhasil diunggah.', 'success');
    } catch (error) {
      // Gagal upload = jangan biarkan URL setengah jalan terpakai.
      document.querySelector('#image-url').value = '/img/fabric-hero.png';
      URL.revokeObjectURL(localUrl);
      preview.hidden = true;
      message(error.message, 'error');
    }
  });
}

async function enterWorkspace() {
  await loadCatalog();
  showWorkspace();
  bindAll();
}

async function initAdminProducts() {
  const authPanel = document.querySelector('#products-auth');
  const authMessage = document.querySelector('#products-auth-message');
  const loading = document.querySelector('#products-loading');

  // Tombol login harus hidup walau sesi belum ada — di-bind di luar try.
  document.querySelector('#admin-login').addEventListener('click', async () => {
    try {
      await api('/auth/login', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email: document.querySelector('#admin-email').value, password: document.querySelector('#admin-password').value }) });
      await enterWorkspace();
    } catch (error) {
      authMessage.hidden = false;
      authMessage.textContent = error.message;
    }
  });

  try {
    const me = await api('/auth/me');
    if (me.user.role !== 'admin') throw new Error('Akses admin diperlukan');
    await enterWorkspace();
    document.querySelector('#products-refresh').addEventListener('click', async () => {
      try { await loadCatalog(); message('Data produk dimuat ulang.', 'success'); } catch (error) { message(error.message, 'error'); }
    });
  } catch {
    loading.hidden = true;
    authPanel.hidden = false;
  }
}
function renderProducts(products) {
  const rows = document.querySelector('#product-rows');
  rows.innerHTML = products.map((product) => `<tr><td><b>${esc(product.name)}</b><span class="sub">${esc(product.category_name)}</span></td><td>${esc(product.sku)}</td><td>${statusBadge(product.status)}</td><td class="num">${esc(product.gsm)}</td><td class="num">${esc(product.available_stock)}</td><td><div class="row-actions"><button class="btn" data-edit="${Number(product.id)}">Varian</button> <button class="btn btn--danger" data-archive="${Number(product.id)}">Arsipkan</button></div></td></tr>`).join('') || '<tr><td colspan="6"><div class="empty-state"><b>Belum ada produk</b>Tambahkan produk pertama lewat formulir di atas.</div></td></tr>';
  rows.querySelectorAll('[data-edit]').forEach((button) => button.addEventListener('click', () => openVariants(Number(button.dataset.edit), products.find((product) => product.id === Number(button.dataset.edit)))));
  rows.querySelectorAll('[data-archive]').forEach((button) => button.addEventListener('click', async () => { if (!confirm('Arsipkan produk ini? Produk tidak akan tampil di toko.')) return; await api(`/admin/products/${button.dataset.archive}`, { method: 'DELETE' }); message('Produk berhasil diarsipkan.', 'success'); renderProducts((await api('/admin/products')).products); }));
}
function bindProductForm() { document.querySelector('#product-form').addEventListener('submit', async (event) => { event.preventDefault(); const data = Object.fromEntries(new FormData(event.currentTarget)); data.category_id = Number(data.category_id); data.gsm = Number(data.gsm); try { await api('/admin/products', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data) }); event.currentTarget.reset(); resetImagePreview(); message('Produk berhasil dibuat.', 'success'); renderProducts((await api('/admin/products')).products); } catch (error) { message(error.message, 'error'); } }); }

// Setelah form di-reset, pratinjau harus ikut hilang — kalau tidak, admin
// mengira gambar masih terpasang padahal URL sudah kembali ke default.
function resetImagePreview() {
  const preview = document.querySelector('#image-preview');
  const input = document.querySelector('#image-input');
  if (preview) preview.hidden = true;
  if (input) input.value = '';
}
function bindCatalogForms() { document.querySelector('#category-form').addEventListener('submit', async (event) => { event.preventDefault(); try { await api('/admin/categories', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(Object.fromEntries(new FormData(event.currentTarget))) }); message('Kategori berhasil ditambahkan.', 'success'); } catch (error) { message(error.message, 'error'); } }); document.querySelector('#color-form').addEventListener('submit', async (event) => { event.preventDefault(); try { await api('/admin/colors', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(Object.fromEntries(new FormData(event.currentTarget))) }); message('Warna berhasil ditambahkan.', 'success'); } catch (error) { message(error.message, 'error'); } }); }
async function openVariants(productId, product) { const panel = document.querySelector('#variant-panel'); panel.hidden = false; document.querySelector('#variant-title').textContent = `Varian · ${product.name}`; const draw = async () => { const data = await api(`/admin/products/${productId}/variants`); document.querySelector('#variant-rows').innerHTML = data.variants.map((variant) => `<div class="variant-row"><span><b>${esc(variant.color)}</b><small>${esc(variant.sku)}</small></span><input data-price="${Number(variant.id)}" value="${esc(variant.price)}" type="number"><input data-wholesale="${Number(variant.id)}" value="${esc(variant.wholesale_price)}" type="number"><input data-stock="${Number(variant.id)}" value="${esc(variant.stock)}" type="number"><button class="btn" data-save-variant="${Number(variant.id)}">Simpan</button></div>`).join('') || '<div class="empty-state"><b>Belum ada varian</b>Tambahkan varian pertama lewat formulir di atas.</div>'; document.querySelectorAll('[data-save-variant]').forEach((button) => button.addEventListener('click', async () => { const id = button.dataset.saveVariant; await api(`/admin/variants/${id}`, { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ price: Number(document.querySelector(`[data-price="${id}"]`).value), wholesale_price: Number(document.querySelector(`[data-wholesale="${id}"]`).value) }) }); await api(`/admin/inventory/${id}`, { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ stock: Number(document.querySelector(`[data-stock="${id}"]`).value) }) }); message('Varian dan stok tersimpan.', 'success'); })); }; await draw(); document.querySelector('#variant-form').onsubmit = async (event) => { event.preventDefault(); const data = Object.fromEntries(new FormData(event.currentTarget)); data.color_id = Number(data.color_id); data.price = Number(data.price); data.wholesale_price = Number(data.wholesale_price); data.stock = Number(data.stock); await api(`/admin/products/${productId}/variants`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data) }); event.currentTarget.reset(); await draw(); }; document.querySelector('#pricing-form').onsubmit = async (event) => { event.preventDefault(); const data = Object.fromEntries(new FormData(event.currentTarget)); const current = await api(`/products/${product.slug}`); current.product.tiers.push({ min_quantity: Number(data.min_quantity), max_quantity: data.max_quantity ? Number(data.max_quantity) : null, price: Number(data.price), label: `${data.min_quantity}+ roll` }); await api(`/admin/products/${productId}/pricing`, { method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ tiers: current.product.tiers }) }); message('Pricing tier tersimpan.', 'success'); };
 bindGallery(productId, draw);
 }

 // ---- Galeri gambar per produk ----
 // Server menolak URL di luar /uploads/ dan /img/, jadi markup di sini aman
 // selama url di-escape (esc) — tetap dipakai supaya konsisten.
 function bindGallery(productId, redrawVariants) {
 const grid = document.querySelector('#gallery-grid');
 const drop = document.querySelector('#gallery-drop');
 const pick = document.querySelector('#gallery-pick');
 const input = document.querySelector('#gallery-input');

 const drawGallery = async () => {
   const { images } = await api(`/admin/products/${productId}/images`);
   grid.innerHTML = images.map((image, index) => `<div class="gallery-item ${index === 0 ? 'is-primary' : ''}">
     <img src="${esc(image.url)}" alt="${esc(image.alt)}" loading="lazy">
     <div class="gallery-meta"><span>${index === 0 ? 'Utama' : `#${index + 1}`}</span><small>${esc(image.alt || '')}</small></div>
     <div class="gallery-actions">
       ${index === 0 ? '' : `<button class="btn" data-primary="${Number(image.id)}">Jadikan utama</button>`}
       <button class="btn btn--danger" data-del-image="${Number(image.id)}">Hapus</button>
     </div>
   </div>`).join('') || '<div class="empty-state"><b>Belum ada gambar</b>Tarik gambar ke area di bawah.</div>';

   grid.querySelectorAll('[data-primary]').forEach((button) => button.addEventListener('click', async () => {
     try {
       await api(`/admin/products/${productId}/images/${button.dataset.primary}/primary`, { method: 'PATCH' });
       message('Gambar utama diperbarui.', 'success');
       await drawGallery();
       await redrawVariants();
     } catch (error) { message(error.message, 'error'); }
   }));

   grid.querySelectorAll('[data-del-image]').forEach((button) => button.addEventListener('click', async () => {
     if (!confirm('Hapus gambar ini dari produk? File-nya juga dihapus kalau tidak dipakai produk lain.')) return;
     try {
       await api(`/admin/products/${productId}/images/${button.dataset.delImage}`, { method: 'DELETE' });
       message('Gambar dihapus.', 'success');
       await drawGallery();
     } catch (error) { message(error.message, 'error'); }
   }));
 };

 const uploadFiles = async (files) => {
   for (const file of files) {
     try {
       const response = await fetch('/api/admin/uploads', { method: 'POST', credentials: 'include', headers: { 'Content-Type': file.type || 'application/octet-stream' }, body: file });
       const data = await response.json();
       if (!response.ok) throw new Error(data.error || 'Upload gagal');
       await api(`/admin/products/${productId}/images`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ url: data.url, alt: file.name.replace(/\.[^.]+$/, '') }) });
     } catch (error) {
       message(`${file.name}: ${error.message}`, 'error');
       return;
     }
   }
   message('Gambar ditambahkan ke galeri.', 'success');
   await drawGallery();
 };

 // Elemen galeri ada di HTML statis (bukan dibuat ulang), jadi listener hanya
 // boleh dipasang SEKALI. Tanpa penjaga ini, tiap klik "Varian" menambah
 // listener baru → satu file terunggah berkali-kali.
 if (!grid.dataset.bound) {
   grid.dataset.bound = '1';
   pick.addEventListener('click', () => input.click());
   input.addEventListener('change', async () => { await uploadFiles([...input.files]); input.value = ''; });
   ['dragenter', 'dragover'].forEach((type) => drop.addEventListener(type, (event) => { event.preventDefault(); drop.classList.add('dragover'); }));
   ['dragleave', 'drop'].forEach((type) => drop.addEventListener(type, (event) => { event.preventDefault(); drop.classList.remove('dragover'); }));
   drop.addEventListener('drop', async (event) => { if (event.dataTransfer?.files?.length) await uploadFiles([...event.dataTransfer.files]); });
 }

 drawGallery();
}
window.initAdminProducts = initAdminProducts;
