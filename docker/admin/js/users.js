import { api } from './api.js';
import { buildQuery, fmtDate, timeAgo, who } from './util.js';
import { PAGE_SIZE, confirmBox, debounce, h, pager, pill, skeleton, stagger, statusPill, toast } from './ui.js';

export async function usersPage(params) {
  const state = { offset: 0, q: '', role: params.get('role') || '' };
  const results = h('div', {}, skeleton());
  const search = h('input', { type: 'search', placeholder: 'Search by name, email or phone', 'aria-label': 'Search users' });
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
      const data = await api(`/admin/users?${buildQuery({ limit: PAGE_SIZE, offset: state.offset, role: state.role, q: state.q })}`);
      if (mine !== latest) return;
      const rows = stagger(data.items.map((u) => h('tr', { class: 'link', tabindex: '0', onclick: () => { location.hash = `#/users/${u.id}`; }, onkeydown: (e) => { if (e.key === 'Enter') location.hash = `#/users/${u.id}`; } },
        h('td', { class: 'name' }, u.full_name), h('td', {}, who(u)), h('td', {}, pill(u.role.replace(/^./, (c) => c.toUpperCase()))),
        h('td', {}, u.is_active ? pill('Active', 'ok') : pill('Deactivated', 'off')), h('td', {}, timeAgo(u.created_at)),
        h('td', {}, u.role === 'admin' ? null : h('button', { class: 'btn secondary small', onclick: (e) => { e.stopPropagation(); toggle(u); } }, u.is_active ? 'Deactivate' : 'Activate')))));
      results.replaceChildren(
        data.items.length === 0 ? h('div', { class: 'card empty' }, 'No users match.')
          : h('div', { class: 'table-wrap' }, h('table', {}, h('thead', {}, h('tr', {}, ...['Name', 'Contact', 'Type', 'Account', 'Joined', ''].map((t) => h('th', {}, t)))), h('tbody', {}, rows))),
        pager(state, data.total, load));
    } catch (e) { if (e.status !== 401) results.replaceChildren(h('div', { class: 'error' }, e.message)); }
  }

  search.addEventListener('input', debounce(() => { state.q = search.value.trim(); state.offset = 0; load(); }, 300));
  role.addEventListener('change', () => { state.role = role.value; state.offset = 0; load(); });
  load();
  return h('div', {}, h('div', { class: 'page-head' }, h('h1', {}, 'Users')), h('div', { class: 'toolbar' }, search, role), results);
}

export async function userPage(id) {
  const u = await api(`/admin/users/${encodeURIComponent(id)}`);
  const fact = (k, v) => h('div', { class: 'fact' }, h('div', { class: 'k' }, k), h('div', { class: 'v' }, v));
  const answers = Object.entries(u.customer_answers);
  return h('div', {},
    h('div', { class: 'page-head' }, h('div', {}, h('a', { class: 'back', href: '#/users' }, '← All users'), h('h1', {}, u.full_name))),
    h('div', { class: 'card rise' },
      h('div', { class: 'actions' }, pill(u.role.replace(/^./, (c) => c.toUpperCase())), u.is_active ? pill('Active', 'ok') : pill('Deactivated', 'off')),
      h('div', { class: 'facts' }, fact('Phone', u.phone || '-'), fact('Email', u.email || '-'), fact('Joined', fmtDate(u.created_at))),
      u.driver_id ? h('div', { class: 'actions' }, h('a', { class: 'btn', href: `#/drivers/${u.driver_id}` }, 'Open driver profile')) : null),
    u.role === 'customer' ? h('div', { class: 'card rise' }, h('h2', {}, 'Profile answers'),
      answers.length === 0 ? h('p', { class: 'muted' }, 'This customer has not filled in their profile.')
        : h('div', { class: 'facts' }, answers.map(([k, v]) => fact(k.replaceAll('_', ' '), v)))) : null);
}

export { statusPill };
