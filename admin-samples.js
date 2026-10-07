// Admin sample workspace — permintaan sample kain dari storefront.
// Pola & helper mengikuti admin-orders.js (api, esc, dateId).

const api = async (path, options = {}) => {
  const response = await fetch(`/api${path}`, { credentials: 'include', ...options });
  const data = response.status === 204 ? null : await response.json();
  if (!response.ok) throw new Error(data?.error || 'Request gagal');
  return data;
};

// Escape SEBELUM masuk innerHTML (data datang dari input publik).
const esc = (value) => String(value ?? '').replace(/[&<>"']/g, (char) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[char]));

const dateId = (iso) => {
  if (!iso) return '—';
  const d = new Date(String(iso).includes('T') ? iso : `${iso}Z`);
  return Number.isNaN(d.getTime()) ? String(iso) : d.toLocaleDateString('id-ID', { day: '2-digit', month: 'short', year: 'numeric' });
};

const STATUS_LABEL = { requested: 'Baru', contacted: 'Dihubungi', sent: 'Terkirim', rejected: 'Ditolak' };
const NEXT_STATUS = {
  requested: ['contacted', 'sent', 'rejected'],
  contacted: ['sent', 'rejected'],
  sent: [],
  rejected: ['contacted'],
};

function toast(text, type = '') {
  const node = document.createElement('div');
  node.className = `toast${type ? ` toast--${type}` : ''}`;
  node.textContent = text;
  document.querySelector('#toasts').appendChild(node);
  setTimeout(() => node.remove(), 4000);
}

let SAMPLES = [];
let filterStatus = 'all';

const visible = () => (filterStatus === 'all' ? SAMPLES : SAMPLES.filter((s) => s.status === filterStatus));

function renderKpis() {
  const count = (statuses) => SAMPLES.filter((s) => statuses.includes(s.status)).length;
  const kpis = [
    ['Baru', count(['requested']), 'belum dihubungi'],
    ['Dihubungi', count(['contacted']), 'sedang ditindak'],
    ['Terkirim', count(['sent']), 'sample keluar'],
    ['Total', SAMPLES.length, 'semua permintaan'],
  ];
  document.querySelector('#sample-kpis').innerHTML = kpis
    .map(([label, value, hint]) => `<div class="kpi"><small>${esc(label)}</small><strong>${esc(value)}</strong><span>${esc(hint)}</span></div>`)
    .join('');
}

function renderChips() {
  const all = ['all', ...Object.keys(STATUS_LABEL)];
  document.querySelector('#status-chips').innerHTML = all.map((status) => {
    const n = status === 'all' ? SAMPLES.length : SAMPLES.filter((s) => s.status === status).length;
    const label = status === 'all' ? 'Semua' : STATUS_LABEL[status];
    return `<button class="chip ${filterStatus === status ? 'active' : ''}" data-status="${esc(status)}">${esc(label)}<span class="count">${esc(n)}</span></button>`;
  }).join('');
  document.querySelectorAll('#status-chips [data-status]').forEach((button) => {
    button.addEventListener('click', () => { filterStatus = button.dataset.status; renderChips(); renderRows(); });
  });
}

function renderRows() {
  const rows = document.querySelector('#sample-rows');
  const list = visible();
  document.querySelector('#samples-count').textContent = list.length ? `Menampilkan ${list.length} dari ${SAMPLES.length} permintaan.` : '';

  if (!list.length) {
    rows.innerHTML = `<tr><td colspan="8"><div class="empty-state"><b>${SAMPLES.length ? 'Tidak ada yang cocok' : 'Belum ada permintaan sample'}</b>${SAMPLES.length ? 'Coba ubah filter.' : 'Permintaan dari form di halaman produk akan muncul di sini.'}</div></td></tr>`;
    return;
  }

  rows.innerHTML = list.map((s) => {
    const next = NEXT_STATUS[s.status] || [];
    const options = next.length
      ? `<select data-next="${Number(s.id)}" aria-label="Ubah status"><option value="">— pilih —</option>${next.map((st) => `<option value="${esc(st)}">${esc(STATUS_LABEL[st])}</option>`).join('')}</select>`
      : '<span class="sub" style="color:var(--muted)">—</span>';
    return `<tr>
      <td>${esc(dateId(s.created_at))}</td>
      <td><b>${esc(s.customer_name || '—')}</b></td>
      <td>${esc(s.email || '—')}<span class="sub">${esc(s.phone || '')}</span></td>
      <td>${esc(s.product_name || '—')}</td>
      <td>${esc(s.color || '—')}</td>
      <td class="num">${esc(s.quantity)}</td>
      <td><span class="badge badge--${esc(s.status)}">${esc(STATUS_LABEL[s.status] || s.status)}</span></td>
      <td>${options}</td>
    </tr>`;
  }).join('');

  rows.querySelectorAll('[data-next]').forEach((select) => {
    select.addEventListener('change', async () => {
      const status = select.value;
      if (!status) return;
      await changeStatus(Number(select.dataset.next), status);
    });
  });
}

async function changeStatus(id, status) {
  try {
    await api(`/admin/samples/${id}`, { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ status }) });
    const s = SAMPLES.find((x) => x.id === id);
    if (s) s.status = status;
    renderKpis(); renderChips(); renderRows();
    toast(`Sample ${s?.customer_name || id} → ${STATUS_LABEL[status]} ✅`, 'success');
  } catch (error) {
    toast(error.message, 'error');
    renderRows();
  }
}

async function loadSamples() {
  const { samples } = await api('/admin/samples');
  SAMPLES = samples;
  renderKpis(); renderChips(); renderRows();
}

async function initAdminSamples() {
  const authPanel = document.querySelector('#samples-auth');
  const workspace = document.querySelector('#samples-workspace');
  const authMessage = document.querySelector('#samples-auth-message');
  const loading = document.querySelector('#samples-loading');

  const showWorkspace = async () => {
    loading.hidden = true;
    authPanel.hidden = true;
    workspace.hidden = false;
    await loadSamples();
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

  document.querySelector('#samples-refresh').addEventListener('click', async () => {
    try { await loadSamples(); toast('Data dimuat ulang ✅', 'success'); } catch (error) { toast(error.message, 'error'); }
  });

  try {
    const me = await api('/auth/me');
    if (me.user.role !== 'admin') throw new Error('Akses admin diperlukan');
    await showWorkspace();
  } catch {
    loading.hidden = true;
    authPanel.hidden = false;
    workspace.hidden = true;
  }
}

window.initAdminSamples = initAdminSamples;
