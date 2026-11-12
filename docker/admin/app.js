// DriveRent admin site. Plain JavaScript, no build step. All server text is put on the page with
// textContent (never as HTML), so a name or note typed by a user can never run as code.

const API = '/api/v1';
const PAGE_SIZE = 25;
const app = document.getElementById('app');

// ------------------------------------------------------------------ small helpers

function h(tag, attrs, ...children) {
  const el = document.createElement(tag);
  for (const [key, value] of Object.entries(attrs || {})) {
    if (value === undefined || value === null || value === false) continue;
    if (key === 'class') el.className = value;
    else if (key.startsWith('on')) el.addEventListener(key.slice(2), value);
    else el.setAttribute(key, value === true ? '' : value);
  }
  for (const child of children.flat()) {
    if (child === undefined || child === null || child === false) continue;
    el.append(child.nodeType ? child : document.createTextNode(String(child)));
  }
  return el;
}

const fmtDate = (iso) =>
  iso ? new Date(iso).toLocaleString('en-IN', { dateStyle: 'medium', timeStyle: 'short' }) : '-';

const rupees = (amount) => `₹${amount}`;
const fmtSize = (bytes) => (bytes < 1024 ? `${bytes} B` : `${(bytes / 1024).toFixed(1)} KB`);

function pill(text, kind) {
  return h('span', { class: `pill ${kind || ''}` }, text);
}

const STATUS_KIND = { APPROVED: 'ok', PENDING: 'warn', REJECTED: 'bad', AVAILABLE: 'ok', SUSPENDED: 'bad', OFFLINE: 'off', ON_TRIP: 'warn', RESERVED: 'warn', BOOKED: 'warn' };
const statusPill = (status) => pill(status.replace('_', ' ').toLowerCase().replace(/^./, (c) => c.toUpperCase()), STATUS_KIND[status]);

let toastTimer;
function toast(message, bad = false) {
  document.querySelector('.toast')?.remove();
  const el = h('div', { class: `toast${bad ? ' bad' : ''}`, role: bad ? 'alert' : 'status' }, message);
  document.body.append(el);
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => el.remove(), 4500);
}

// ------------------------------------------------------------------ session and API

class ApiError extends Error {
  constructor(message, status) {
    super(message);
    this.status = status;
  }
}

const session = {
  get access() { return sessionStorage.getItem('admin_access'); },
  get refresh() { return sessionStorage.getItem('admin_refresh'); },
  get phone() { return sessionStorage.getItem('admin_phone'); },
  set(tokens, phone) {
    sessionStorage.setItem('admin_access', tokens.access_token);
    sessionStorage.setItem('admin_refresh', tokens.refresh_token);
    if (phone) sessionStorage.setItem('admin_phone', phone);
  },
  clear() { sessionStorage.clear(); },
};

function detailOf(body, status) {
  const d = body && body.detail;
  if (typeof d === 'string') return d;
  if (Array.isArray(d) && d[0] && d[0].msg) return String(d[0].msg).replace('Value error, ', '');
  return `Something went wrong (error ${status}).`;
}

let refreshing = null;
let loginNotice = null; // shown once on the login form, e.g. after the session ended
function refreshTokens() {
  if (!session.refresh) return Promise.resolve(false);
  // One refresh at a time, so several requests failing together do not each spend the refresh token.
  refreshing ??= (async () => {
    try {
      const r = await fetch(`${API}/auth/refresh`, {
        method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ refresh_token: session.refresh }),
      });
      if (!r.ok) return false;
      session.set(await r.json());
      return true;
    } catch { return false; } finally { refreshing = null; }
  })();
  return refreshing;
}

async function api(path, { method = 'GET', body, blob = false } = {}) {
  const send = () => fetch(API + path, {
    method,
    headers: { ...(session.access ? { authorization: `Bearer ${session.access}` } : {}), ...(body ? { 'content-type': 'application/json' } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  let r;
  try { r = await send(); } catch { throw new ApiError('Cannot reach the server. Check the connection and try again.', 0); }
  if (r.status === 401 && (await refreshTokens())) r = await send();
  if (r.status === 401) {
    session.clear();
    loginNotice = 'Your session ended. Log in again.';
    if (location.hash) location.hash = '';
    else render();
    throw new ApiError('Session expired', 401);
  }
  if (!r.ok) throw new ApiError(detailOf(await r.json().catch(() => null), r.status), r.status);
  return blob ? r.blob() : r.json();
}

// ------------------------------------------------------------------ dialogs

function openDialog(build) {
  return new Promise((resolve) => {
    const dialog = h('dialog');
    const close = (value) => { dialog.close(); dialog.remove(); resolve(value); };
    build(dialog, close);
    dialog.addEventListener('cancel', () => close(null));
    document.body.append(dialog);
    dialog.showModal();
  });
}

const confirmBox = (title, text, okLabel) => openDialog((dialog, close) => {
  dialog.append(
    h('h2', {}, title), h('p', { class: 'muted' }, text),
    h('div', { class: 'foot' },
      h('button', { class: 'btn secondary', onclick: () => close(false) }, 'Cancel'),
      h('button', { class: 'btn danger', onclick: () => close(true) }, okLabel)),
  );
});

const askNote = (title, text, okLabel) => openDialog((dialog, close) => {
  const note = h('textarea', { maxlength: '500', 'aria-label': 'Note for the driver', placeholder: 'Reason (shown to the driver)' });
  dialog.append(
    h('h2', {}, title), h('p', { class: 'muted' }, text), note,
    h('div', { class: 'foot' },
      h('button', { class: 'btn secondary', onclick: () => close(null) }, 'Cancel'),
      h('button', { class: 'btn danger', onclick: () => close(note.value.trim()) }, okLabel)),
  );
});

async function viewDocument(doc) {
  let url;
  let closed = false;
  const done = openDialog((dialog, close) => {
    const body = h('div', { class: 'viewer' }, h('div', { class: 'loading' }, 'Loading document…'));
    dialog.append(
      h('h2', {}, doc.doc_type.replace('_', ' ')), body,
      h('div', { class: 'foot' }, h('button', { class: 'btn', onclick: () => close() }, 'Close')),
    );
    api(`/admin/documents/${doc.id}/file`, { blob: true }).then((blob) => {
      if (closed) return; // closed before it arrived: nothing to show, nothing to free
      url = URL.createObjectURL(blob);
      body.replaceChildren(
        blob.type.startsWith('image/')
          ? h('img', { src: url, alt: `${doc.doc_type} uploaded by the driver` })
          : h('a', { class: 'btn', href: url, target: '_blank', rel: 'noopener' }, 'Open PDF in a new tab'),
      );
    }).catch((e) => body.replaceChildren(h('div', { class: 'error' }, e.message)));
  });
  await done;
  closed = true;
  if (url) URL.revokeObjectURL(url);
}

// ------------------------------------------------------------------ pages

function pager(state, total, reload) {
  const move = (delta) => (e) => { e.currentTarget.disabled = true; state.offset += delta; reload(); };
  const from = total === 0 ? 0 : state.offset + 1;
  const to = Math.min(state.offset + PAGE_SIZE, total);
  return h('div', { class: 'pager' },
    h('span', {}, `${from}–${to} of ${total}`),
    h('button', { class: 'btn secondary small', disabled: state.offset === 0, onclick: move(-PAGE_SIZE) }, 'Previous'),
    h('button', { class: 'btn secondary small', disabled: to >= total, onclick: move(PAGE_SIZE) }, 'Next'));
}

function debounce(fn, ms) {
  let t;
  return (...args) => { clearTimeout(t); t = setTimeout(() => fn(...args), ms); };
}

async function dashboardPage() {
  const s = await api('/admin/stats');
  const card = (num, label, href, hot) => h('a', { class: `stat rise${hot ? ' hot' : ''}`, href }, h('div', { class: 'num' }, num), h('div', { class: 'label' }, label));
  return h('div', {},
    h('div', { class: 'page-head' }, h('h1', {}, 'Dashboard')),
    h('div', { class: 'stats' },
      card(s.drivers.PENDING, 'Drivers waiting for approval', '#/drivers?verification=PENDING', s.drivers.PENDING > 0),
      card(s.pending_documents, 'Documents to review', '#/drivers?verification=PENDING', s.pending_documents > 0),
      card(s.drivers.APPROVED, 'Approved drivers', '#/drivers?verification=APPROVED'),
      card(s.drivers.REJECTED, 'Rejected drivers', '#/drivers?verification=REJECTED'),
      card(s.drivers.total, 'All drivers', '#/drivers'),
      card(s.customers, 'Customers', '#/users?role=customer'),
      card(s.admins, 'Admins', '#/users?role=admin')));
}

async function driversPage(params) {
  const state = { offset: 0, q: '', verification: params.get('verification') || '' };
  const results = h('div');
  const search = h('input', { type: 'search', placeholder: 'Search by name or phone', 'aria-label': 'Search drivers' });
  const filter = h('select', { 'aria-label': 'Filter by approval' },
    ...[['', 'All drivers'], ['PENDING', 'Waiting for approval'], ['APPROVED', 'Approved'], ['REJECTED', 'Rejected']]
      .map(([v, l]) => h('option', { value: v, selected: v === state.verification }, l)));

  let latest = 0;
  async function load() {
    const mine = ++latest; // an older, slower answer must not replace a newer one
    try {
      const q = new URLSearchParams({ limit: PAGE_SIZE, offset: state.offset });
      if (state.verification) q.set('verification', state.verification);
      if (state.q) q.set('q', state.q);
      const data = await api(`/admin/drivers?${q}`);
      if (mine !== latest) return;
      results.replaceChildren(
        data.items.length === 0
          ? h('div', { class: 'card empty' }, 'No drivers match.')
          : h('div', { class: 'table-wrap' }, h('table', {},
            h('thead', {}, h('tr', {}, ...['Driver', 'Phone', 'Approval', 'Availability', 'Rating', 'Rate / hr', 'Account', 'Joined'].map((t) => h('th', {}, t)))),
            h('tbody', {}, data.items.map((d) => h('tr', { class: 'link', tabindex: '0', onclick: () => { location.hash = `#/drivers/${d.id}`; }, onkeydown: (e) => { if (e.key === 'Enter') location.hash = `#/drivers/${d.id}`; } },
              h('td', { class: 'name' }, d.full_name), h('td', {}, d.phone), h('td', {}, statusPill(d.verification_status)),
              h('td', {}, statusPill(d.availability_status)), h('td', {}, d.rating === '0.00' ? '-' : d.rating), h('td', {}, rupees(d.hourly_rate)),
              h('td', {}, d.is_active ? pill('Active', 'ok') : pill('Deactivated', 'off')), h('td', {}, fmtDate(d.created_at))))))),
        pager(state, data.total, load));
    } catch (e) { if (e.status !== 401) results.replaceChildren(h('div', { class: 'error' }, e.message)); }
  }

  search.addEventListener('input', debounce(() => { state.q = search.value.trim(); state.offset = 0; load(); }, 300));
  filter.addEventListener('change', () => { state.verification = filter.value; state.offset = 0; load(); });
  load();
  return h('div', {}, h('div', { class: 'page-head' }, h('h1', {}, 'Drivers')), h('div', { class: 'toolbar' }, search, filter), results);
}

async function driverPage(id) {
  const d = await api(`/admin/drivers/${encodeURIComponent(id)}`);
  const reload = () => render();

  async function run(label, request) {
    try { await request(); toast(label); reload(); } catch (e) { if (e.status !== 401) toast(e.message, true); }
  }

  const decideDoc = async (doc, status) => {
    let note = null;
    if (status === 'REJECTED') {
      note = await askNote('Reject this document?', 'Tell the driver what is wrong so they can upload a better one.', 'Reject document');
      if (note === null) return;
    }
    run(status === 'APPROVED' ? 'Document approved' : 'Document rejected', () => api(`/admin/documents/${doc.id}`, { method: 'PATCH', body: { status, note: note || null } }));
  };

  const docCard = (doc) => h('div', { class: 'doc' },
    h('div', { class: 'row' }, h('strong', {}, doc.doc_type.replace('_', ' ')), statusPill(doc.status)),
    h('div', { class: 'muted' }, `${doc.content_type} · ${fmtSize(doc.size_bytes)} · ${fmtDate(doc.updated_at)}`),
    doc.review_note ? h('div', { class: 'note' }, `Note: ${doc.review_note}`) : null,
    h('div', { class: 'actions' },
      h('button', { class: 'btn secondary small', onclick: () => viewDocument(doc) }, 'View'),
      doc.status !== 'APPROVED' ? h('button', { class: 'btn small', onclick: () => decideDoc(doc, 'APPROVED') }, 'Approve') : null,
      doc.status !== 'REJECTED' ? h('button', { class: 'btn danger small', onclick: () => decideDoc(doc, 'REJECTED') }, 'Reject') : null));

  const fact = (k, v) => h('div', { class: 'fact' }, h('div', { class: 'k' }, k), h('div', { class: 'v' }, v));
  const suspended = d.availability_status === 'SUSPENDED';

  const actions = h('div', { class: 'actions' },
    d.verification_status !== 'APPROVED' ? h('button', { class: 'btn', onclick: () => run('Driver approved', () => api(`/admin/drivers/${d.id}/verification`, { method: 'PATCH', body: { status: 'APPROVED' } })) }, 'Approve driver') : null,
    d.verification_status !== 'REJECTED' ? h('button', { class: 'btn danger', onclick: async () => {
      const note = await askNote('Reject this driver?', 'The driver goes offline and cannot take bookings until approved again.', 'Reject driver');
      if (note !== null) run('Driver rejected', () => api(`/admin/drivers/${d.id}/verification`, { method: 'PATCH', body: { status: 'REJECTED', note: note || null } }));
    } }, 'Reject driver') : null,
    h('button', { class: 'btn secondary', onclick: async () => {
      if (!suspended && !(await confirmBox('Suspend this driver?', 'They go offline and cannot be booked until reinstated.', 'Suspend'))) return;
      run(suspended ? 'Driver reinstated' : 'Driver suspended', () => api(`/admin/drivers/${d.id}/suspension`, { method: 'PATCH', body: { suspended: !suspended } }));
    } }, suspended ? 'Reinstate' : 'Suspend'),
    h('button', { class: 'btn secondary', onclick: async () => {
      if (d.is_active && !(await confirmBox('Deactivate this account?', 'The driver is logged out everywhere and cannot log in until you activate it again.', 'Deactivate'))) return;
      run(d.is_active ? 'Account deactivated' : 'Account activated', () => api(`/admin/users/${d.user_id}/active`, { method: 'PATCH', body: { active: !d.is_active } }));
    } }, d.is_active ? 'Deactivate account' : 'Activate account'));

  return h('div', {},
    h('div', { class: 'page-head' }, h('div', {}, h('a', { class: 'back', href: '#/drivers' }, '← All drivers'), h('h1', {}, d.full_name))),
    h('div', { class: 'card rise' },
      h('div', { class: 'actions' }, statusPill(d.verification_status), statusPill(d.availability_status), d.is_active ? pill('Account active', 'ok') : pill('Account deactivated', 'off')),
      h('div', { class: 'facts' },
        fact('Phone', d.phone), fact('Email', d.email || '-'), fact('Licence number', d.licence_number), fact('Experience', `${d.experience_years} years`),
        fact('Hourly rate', rupees(d.hourly_rate)), fact('Rating', d.rating === '0.00' ? 'Not rated yet' : d.rating), fact('Completed trips', d.completed_trips), fact('Joined', fmtDate(d.created_at))),
      actions),
    h('div', { class: 'card rise' }, h('h2', {}, 'Documents'),
      d.documents.length === 0 ? h('p', { class: 'muted' }, 'This driver has not uploaded any documents yet.') : h('div', { class: 'docs' }, d.documents.map(docCard))));
}

async function usersPage(params) {
  const state = { offset: 0, q: '', role: params.get('role') || '' };
  const results = h('div');
  const search = h('input', { type: 'search', placeholder: 'Search by name or phone', 'aria-label': 'Search users' });
  const role = h('select', { 'aria-label': 'Filter by account type' },
    ...[['', 'Everyone'], ['customer', 'Customers'], ['driver', 'Drivers'], ['admin', 'Admins']].map(([v, l]) => h('option', { value: v, selected: v === state.role }, l)));

  async function toggle(u) {
    if (u.is_active && !(await confirmBox('Deactivate this account?', `${u.full_name} is logged out everywhere and cannot log in until you activate the account again.`, 'Deactivate'))) return;
    try {
      await api(`/admin/users/${u.id}/active`, { method: 'PATCH', body: { active: !u.is_active } });
      toast(u.is_active ? 'Account deactivated' : 'Account activated');
      load();
    } catch (e) { if (e.status !== 401) toast(e.message, true); }
  }

  let latest = 0;
  async function load() {
    const mine = ++latest;
    try {
      const q = new URLSearchParams({ limit: PAGE_SIZE, offset: state.offset });
      if (state.role) q.set('role', state.role);
      if (state.q) q.set('q', state.q);
      const data = await api(`/admin/users?${q}`);
      if (mine !== latest) return;
      results.replaceChildren(
        data.items.length === 0
          ? h('div', { class: 'card empty' }, 'No users match.')
          : h('div', { class: 'table-wrap' }, h('table', {},
            h('thead', {}, h('tr', {}, ...['Name', 'Phone', 'Type', 'Account', 'Joined', ''].map((t) => h('th', {}, t)))),
            h('tbody', {}, data.items.map((u) => h('tr', {},
              h('td', { class: 'name' }, u.full_name), h('td', {}, u.phone), h('td', {}, pill(u.role.replace(/^./, (c) => c.toUpperCase()))),
              h('td', {}, u.is_active ? pill('Active', 'ok') : pill('Deactivated', 'off')), h('td', {}, fmtDate(u.created_at)),
              h('td', {}, u.role === 'admin' ? null : h('button', { class: 'btn secondary small', onclick: () => toggle(u) }, u.is_active ? 'Deactivate' : 'Activate'))))))),
        pager(state, data.total, load));
    } catch (e) { if (e.status !== 401) results.replaceChildren(h('div', { class: 'error' }, e.message)); }
  }

  search.addEventListener('input', debounce(() => { state.q = search.value.trim(); state.offset = 0; load(); }, 300));
  role.addEventListener('change', () => { state.role = role.value; state.offset = 0; load(); });
  load();
  return h('div', {}, h('div', { class: 'page-head' }, h('h1', {}, 'Users')), h('div', { class: 'toolbar' }, search, role), results);
}

// ------------------------------------------------------------------ shell, login and routing

function showLogin(message = loginNotice) {
  loginNotice = null;
  const phone = h('input', { type: 'tel', autocomplete: 'username', required: true, placeholder: '98765 43210' });
  const password = h('input', { type: 'password', autocomplete: 'current-password', required: true });
  const error = h('div', { class: 'error', role: 'alert', hidden: !message }, message || '');
  const submit = h('button', { class: 'btn block', type: 'submit' }, 'Log in');
  const form = h('form', { class: 'login-card rise' },
    h('div', { class: 'brand' }, h('div', { class: 'brand-mark' }, 'DR'), h('div', {}, h('div', { class: 'brand-name' }, 'DriveRent'), h('div', { class: 'muted' }, 'Admin'))),
    h('h1', {}, 'Welcome back'), h('p', { class: 'muted' }, 'Log in with your admin account.'),
    h('label', { class: 'field' }, h('span', {}, 'Phone number'), phone),
    h('label', { class: 'field' }, h('span', {}, 'Password'), password), error, submit);
  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    submit.disabled = true;
    error.hidden = true;
    try {
      const r = await fetch(`${API}/auth/admin/login`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ phone: phone.value.trim(), password: password.value }) });
      if (!r.ok) throw new ApiError(r.status === 401 ? 'Invalid phone or password' : detailOf(await r.json().catch(() => null), r.status), r.status);
      session.set(await r.json(), phone.value.trim());
      location.hash = '#/dashboard';
      render();
    } catch (err) {
      error.textContent = err instanceof ApiError ? err.message : 'Cannot reach the server. Check the connection and try again.';
      error.hidden = false;
      submit.disabled = false;
    }
  });
  app.replaceChildren(h('div', { class: 'login-wrap' }, form));
  phone.focus();
}

let renderToken = 0;
async function render() {
  if (!session.access) return showLogin();
  const token = ++renderToken;
  const [path, query = ''] = location.hash.replace(/^#/, '').split('?');
  const params = new URLSearchParams(query);
  const parts = path.split('/').filter(Boolean);
  const section = parts[0] || 'dashboard';

  const nav = (href, label, key) => h('a', { href, class: section === key ? 'active' : '', 'aria-current': section === key ? 'page' : null }, label);
  const content = h('main', { class: 'main' }, h('div', { class: 'loading' }, 'Loading…'));
  app.replaceChildren(h('div', { class: 'shell' },
    h('aside', { class: 'side' },
      h('div', { class: 'brand' }, h('div', { class: 'brand-mark' }, 'DR'), h('div', { class: 'brand-name' }, 'DriveRent')),
      h('nav', { class: 'nav', 'aria-label': 'Main' }, nav('#/dashboard', 'Dashboard', 'dashboard'), nav('#/drivers', 'Drivers', 'drivers'), nav('#/users', 'Users', 'users')),
      h('div', { class: 'spacer' }), h('div', { class: 'who' }, session.phone || 'Admin'),
      h('button', { class: 'btn secondary small', onclick: () => { session.clear(); location.hash = ''; render(); } }, 'Log out')),
    content));

  try {
    let page;
    if (section === 'drivers' && parts[1]) page = await driverPage(parts[1]);
    else if (section === 'drivers') page = await driversPage(params);
    else if (section === 'users') page = await usersPage(params);
    else page = await dashboardPage();
    if (token === renderToken) content.replaceChildren(page);
  } catch (e) {
    if (e.status !== 401 && token === renderToken) content.replaceChildren(h('div', { class: 'error' }, e.message));
  }
}

window.addEventListener('hashchange', render);
render();
