// Admin order workspace — Fase 1
// Pola & helper mengikuti store.js / admin-products.js (api, esc, money).

const api = async (path, options = {}) => {
  const response = await fetch(`/api${path}`, { credentials: 'include', ...options });
  const data = response.status === 204 ? null : await response.json();
  if (!response.ok) throw new Error(data?.error || 'Request gagal');
  return data;
};

// Escape SEBELUM masuk innerHTML (data pelanggan datang dari input publik).
const esc = (value) => String(value ?? '').replace(/[&<>"']/g, (char) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[char]));

const money = (value) => new Intl.NumberFormat('id-ID', { style: 'currency', currency: 'IDR', maximumFractionDigits: 0 }).format(Number(value) || 0);

const dateId = (iso) => {
  if (!iso) return '—';
  const d = new Date(String(iso).includes('T') ? iso : `${iso}Z`);
  return Number.isNaN(d.getTime()) ? String(iso) : d.toLocaleDateString('id-ID', { day: '2-digit', month: 'short', year: 'numeric' });
};

// ---- Status: label + transisi yang SAH (server tetap memvalidasi) ----
const STATUS_LABEL = {
  pending_payment: 'Menunggu bayar',
  paid: 'Dibayar',
  processing: 'Diproses',
  packed: 'Dikemas',
  shipped: 'Dikirim',
  completed: 'Selesai',
  cancelled: 'Dibatalkan',
  refunded: 'Dikembalikan',
};
const TRANSITIONS = {
  pending_payment: ['paid', 'cancelled'],
  paid: ['processing', 'cancelled', 'refunded'],
  processing: ['packed', 'cancelled'],
  packed: ['shipped', 'cancelled'],
  shipped: ['completed'],
  completed: ['refunded'],
  cancelled: [],
  refunded: [],
};
const DESTRUCTIVE = new Set(['cancelled', 'refunded']);

// ---- Toast ----
function toast(text, type = '') {
  const node = document.createElement('div');
  node.className = `toast${type ? ` toast--${type}` : ''}`;
  node.textContent = text;
  document.querySelector('#toasts').appendChild(node);
  setTimeout(() => node.remove(), 4000);
}

// ---- Modal konfirmasi (Promise) ----
function confirmAction(title, text, confirmLabel = 'Ya, lanjutkan') {
  const backdrop = document.querySelector('#modal-backdrop');
  const confirmBtn = document.querySelector('#modal-confirm');
  const cancelBtn = document.querySelector('#modal-cancel');
  document.querySelector('#modal-title').textContent = title;
  document.querySelector('#modal-text').textContent = text;
  confirmBtn.textContent = confirmLabel;
  backdrop.classList.add('open');
  confirmBtn.focus();
  return new Promise((resolve) => {
    const done = (value) => {
      backdrop.classList.remove('open');
      confirmBtn.onclick = null;
      cancelBtn.onclick = null;
      backdrop.onclick = null;
      resolve(value);
    };
    confirmBtn.onclick = () => done(true);
    cancelBtn.onclick = () => done(false);
    backdrop.onclick = (event) => { if (event.target === backdrop) done(false); };
  });
}

// ---- State ----
let ORDERS = [];
let filterStatus = 'all';
let filterQuery = '';

const visibleOrders = () => ORDERS.filter((order) => {
  if (filterStatus !== 'all' && order.status !== filterStatus) return false;
  if (!filterQuery) return true;
  const hay = `${order.order_number} ${order.customer_name || ''} ${order.email || ''}`.toLowerCase();
  return hay.includes(filterQuery);
});

// ---- Render ----
function renderKpis() {
  const count = (statuses) => ORDERS.filter((o) => statuses.includes(o.status)).length;
  const kpis = [
    ['Menunggu bayar', count(['pending_payment']), 'belum dibayar'],
    ['Perlu dikemas', count(['paid', 'processing', 'packed']), 'siap diproses'],
    ['Dikirim', count(['shipped']), 'dalam perjalanan'],
    ['Selesai', count(['completed']), 'total'],
  ];
  document.querySelector('#order-kpis').innerHTML = kpis
    .map(([label, value, hint]) => `<div class="kpi"><small>${esc(label)}</small><strong>${esc(value)}</strong><span>${esc(hint)}</span></div>`)
    .join('');
}

function renderChips() {
  const all = ['all', ...Object.keys(STATUS_LABEL)];
  document.querySelector('#status-chips').innerHTML = all.map((status) => {
    const n = status === 'all' ? ORDERS.length : ORDERS.filter((o) => o.status === status).length;
    const label = status === 'all' ? 'Semua' : STATUS_LABEL[status];
    return `<button class="chip ${filterStatus === status ? 'active' : ''}" data-status="${esc(status)}">${esc(label)}<span class="count">${esc(n)}</span></button>`;
  }).join('');
  document.querySelectorAll('[data-status]').forEach((button) => {
    button.addEventListener('click', () => { filterStatus = button.dataset.status; renderChips(); renderRows(); });
  });
}

function renderRows() {
  const rows = document.querySelector('#order-rows');
  const list = visibleOrders();
  document.querySelector('#orders-count').textContent = list.length
    ? `Menampilkan ${list.length} dari ${ORDERS.length} pesanan.`
    : '';

  if (!list.length) {
    rows.innerHTML = `<tr><td colspan="7"><div class="empty-state"><b>${ORDERS.length ? 'Tidak ada pesanan yang cocok' : 'Belum ada pesanan'}</b>${ORDERS.length ? 'Coba ubah filter atau kata kunci.' : 'Pesanan yang masuk dari checkout akan muncul di sini.'}</div></td></tr>`;
    return;
  }

  rows.innerHTML = list.map((order) => {
    const next = TRANSITIONS[order.status] || [];
    const options = next.length
      ? `<select data-next="${Number(order.id)}" aria-label="Ubah status ${esc(order.order_number)}"><option value="">— pilih —</option>${next.map((s) => `<option value="${esc(s)}">${esc(STATUS_LABEL[s])}</option>`).join('')}</select>`
      : '<span class="sub" style="color:var(--muted)">—</span>';
    return `<tr>
      <td><b>${esc(order.order_number)}</b>${order.tracking_number ? `<span class="sub">Resi: ${esc(order.tracking_number)}</span>` : ''}</td>
      <td>${esc(dateId(order.created_at))}</td>
      <td>${esc(order.customer_name || '—')}<span class="sub">${esc(order.email || '')}</span></td>
      <td><span class="badge badge--${esc(order.status)}">${esc(STATUS_LABEL[order.status] || order.status)}</span></td>
      <td class="num">${esc(money(order.total))}</td>
      <td>${options}</td>
      <td><button class="btn" data-detail="${Number(order.id)}">Detail</button></td>
    </tr>`;
  }).join('');

  rows.querySelectorAll('[data-detail]').forEach((button) => {
    button.addEventListener('click', () => openDrawer(Number(button.dataset.detail)));
  });
  rows.querySelectorAll('[data-next]').forEach((select) => {
    select.addEventListener('change', async () => {
      const status = select.value;
      const id = Number(select.dataset.next);
      if (!status) return;
      const order = ORDERS.find((o) => o.id === id);
      if (DESTRUCTIVE.has(status)) {
        const ok = await confirmAction(
          `Ubah status ke "${STATUS_LABEL[status]}"?`,
          `Pesanan ${order?.order_number || id} akan ditandai "${STATUS_LABEL[status]}". Tindakan ini tercatat dan sulit dibatalkan.`,
          `Ya, ${STATUS_LABEL[status].toLowerCase()}`,
        );
        if (!ok) { select.value = ''; return; }
      }
      await changeStatus(id, status);
    });
  });
}

// ---- Aksi ----
async function changeStatus(id, status, tracking) {
  const body = { status };
  if (tracking) body.tracking_number = tracking;
  try {
    await api(`/admin/orders/${id}`, { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
    const order = ORDERS.find((o) => o.id === id);
    if (order) {
      order.status = status;
      if (tracking) order.tracking_number = tracking;
    }
    renderKpis(); renderChips(); renderRows();
    if (drawerOrderId === id) renderDrawer(order || await fetchOrder(id));
    toast(`Pesanan ${order?.order_number || id} → ${STATUS_LABEL[status]} ✅`, 'success');
  } catch (error) {
    toast(error.message, 'error');
    renderRows();
  }
}

async function fetchOrder(id) {
  const { order, items } = await api(`/orders/${id}`);
  return { ...order, items: items || [] };
}

// ---- Drawer ----
let drawerOrderId = null;

function renderDrawer(order) {
  document.querySelector('#drawer-title').textContent = `Pesanan ${order.order_number}`;
  const items = order.items || [];
  const rows = items.map((item) => `<tr>
      <td>${esc(item.variant_name)}<span class="sub">${esc(item.sku)}</span></td>
      <td class="num">${esc(item.quantity)}×</td>
      <td class="num">${esc(money(item.subtotal))}</td>
    </tr>`).join('') || '<tr><td colspan="3">Tidak ada item.</td></tr>';

  document.querySelector('#drawer-body').innerHTML = `
    <div style="margin-bottom:16px"><span class="badge badge--${esc(order.status)}">${esc(STATUS_LABEL[order.status] || order.status)}</span></div>
    <dl class="dl">
      <dt>Pelanggan</dt><dd>${esc(order.customer_name || '—')}<br><span style="color:var(--muted)">${esc(order.email || '')}</span></dd>
      <dt>Telepon</dt><dd>${esc(order.phone || '—')}</dd>
      <dt>Alamat kirim</dt><dd>${esc(order.full_name || order.customer_name || '—')}<br>${esc(order.address || '—')}<br>${esc([order.district, order.city, order.province, order.postal_code].filter(Boolean).join(', ') || '')}</dd>
      <dt>Dibuat</dt><dd>${esc(dateId(order.created_at))}</dd>
      <dt>Pembayaran</dt><dd>${esc(order.payment_status || '—')}</dd>
      <dt>Pengiriman</dt><dd>${esc(order.method || '—')}${order.estimated_days ? ` · ${esc(order.estimated_days)}` : ''}</dd>
      <dt>Catatan</dt><dd>${esc(order.notes || '—')}</dd>
    </dl>
    <table class="line-items">
      <thead><tr><th>Item</th><th class="num">Qty</th><th class="num">Subtotal</th></tr></thead>
      <tbody>${rows}</tbody>
    </table>
    <div class="totals">
      <div><span>Subtotal</span><span>${esc(money(order.subtotal))}</span></div>
      <div><span>Pengiriman</span><span>${esc(money(order.shipping))}</span></div>
      ${Number(order.discount) ? `<div><span>Diskon</span><span>−${esc(money(order.discount))}</span></div>` : ''}
      <div class="grand"><span>Total</span><span>${esc(money(order.total))}</span></div>
    </div>`;

  const next = TRANSITIONS[order.status] || [];
  document.querySelector('#drawer-foot').innerHTML = `
    <div class="field-inline">
      <label for="drawer-tracking">Nomor resi</label>
      <input id="drawer-tracking" value="${esc(order.tracking_number || '')}" placeholder="mis. JNE123456789">
    </div>
    ${next.length ? `<div class="field-inline">
      <label for="drawer-status">Ubah status</label>
      <select id="drawer-status"><option value="">— pilih —</option>${next.map((s) => `<option value="${esc(s)}">${esc(STATUS_LABEL[s])}</option>`).join('')}</select>
    </div>` : ''}
    <button class="btn btn--primary" id="drawer-save">Simpan</button>`;

  document.querySelector('#drawer-save').addEventListener('click', async () => {
    const tracking = document.querySelector('#drawer-tracking').value.trim();
    const select = document.querySelector('#drawer-status');
    const status = select ? select.value : '';
    if (!status && !tracking) { toast('Tidak ada perubahan.', 'error'); return; }
    if (status && DESTRUCTIVE.has(status)) {
      const ok = await confirmAction(`Ubah status ke "${STATUS_LABEL[status]}"?`, `Pesanan ${order.order_number} akan ditandai "${STATUS_LABEL[status]}".`, `Ya, ${STATUS_LABEL[status].toLowerCase()}`);
      if (!ok) return;
    }
    await changeStatus(order.id, status || order.status, tracking);
    toast('Perubahan tersimpan ✅', 'success');
  });
}

async function openDrawer(id) {
  drawerOrderId = id;
  const drawer = document.querySelector('#drawer');
  document.querySelector('#drawer-body').innerHTML = '<div class="skeleton" style="width:60%;margin-bottom:12px"></div><div class="skeleton" style="width:90%;margin-bottom:12px"></div><div class="skeleton" style="width:75%"></div>';
  document.querySelector('#drawer-foot').innerHTML = '';
  drawer.classList.add('open');
  drawer.setAttribute('aria-hidden', 'false');
  document.querySelector('#drawer-backdrop').classList.add('open');
  try {
    renderDrawer(await fetchOrder(id));
    document.querySelector('#drawer-close').focus();
  } catch (error) {
    document.querySelector('#drawer-body').innerHTML = `<div class="empty-state"><b>Gagal memuat detail</b>${esc(error.message)}</div>`;
  }
}

function closeDrawer() {
  drawerOrderId = null;
  document.querySelector('#drawer').classList.remove('open');
  document.querySelector('#drawer').setAttribute('aria-hidden', 'true');
  document.querySelector('#drawer-backdrop').classList.remove('open');
}

// ---- Init ----
async function loadOrders() {
  const { orders } = await api('/admin/orders');
  ORDERS = orders;
  renderKpis(); renderChips(); renderRows();
}

async function initAdminOrders() {
  const authPanel = document.querySelector('#orders-auth');
  const workspace = document.querySelector('#orders-workspace');
  const authMessage = document.querySelector('#orders-auth-message');

  const showWorkspace = async () => {
    authPanel.hidden = true;
    workspace.hidden = false;
    await loadOrders();
    const wanted = new URLSearchParams(location.search).get('id');
    if (wanted) openDrawer(Number(wanted));
  };

  document.querySelector('#admin-login').addEventListener('click', async () => {
    try {
      await api('/auth/login', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email: document.querySelector('#admin-email').value, password: document.querySelector('#admin-password').value }),
      });
      await showWorkspace();
    } catch (error) {
      authMessage.hidden = false;
      authMessage.textContent = error.message;
    }
  });

  document.querySelector('#orders-refresh').addEventListener('click', async () => {
    try { await loadOrders(); toast('Data dimuat ulang ✅', 'success'); } catch (error) { toast(error.message, 'error'); }
  });
  document.querySelector('#order-search').addEventListener('input', (event) => { filterQuery = event.target.value.trim().toLowerCase(); renderRows(); });
  document.querySelector('#drawer-close').addEventListener('click', closeDrawer);
  document.querySelector('#drawer-backdrop').addEventListener('click', closeDrawer);
  document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') {
      if (document.querySelector('#modal-backdrop').classList.contains('open')) return;
      closeDrawer();
    }
  });

  try {
    const me = await api('/auth/me');
    if (me.user.role !== 'admin') throw new Error('Akses admin diperlukan');
    await showWorkspace();
  } catch {
    authPanel.hidden = false;
    workspace.hidden = true;
  }
}

initAdminOrders();
