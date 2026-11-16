import { api } from './api.js';
import { buildQuery, formatStatus, rupees, timeAgo, who } from './util.js';
import { PAGE_SIZE, debounce, h, pager, pill, skeleton, stagger, statusPill } from './ui.js';

const go = (id) => () => { location.hash = `#/drivers/${id}`; };

export async function driversPage(params) {
  const state = { offset: 0, q: '', verification: params.get('verification') || '', availability: '', needs_update: params.get('needs_update') === 'true' };
  const results = h('div', {}, skeleton());
  const search = h('input', { type: 'search', placeholder: 'Search by name, email or phone', 'aria-label': 'Search drivers' });
  const select = (label, options, key) => {
    const el = h('select', { 'aria-label': label }, ...options.map(([v, l]) => h('option', { value: v, selected: v === state[key] }, l)));
    el.addEventListener('change', () => { state[key] = el.value; state.offset = 0; load(); });
    return el;
  };
  const verification = select('Filter by approval', [['', 'Any approval'], ['NOT_SUBMITTED', 'Not applied yet'], ['PENDING', 'Waiting for review'], ['REJECTED', 'Needs changes'], ['APPROVED', 'Approved']], 'verification');
  const availability = select('Filter by availability', [['', 'Any availability'], ['AVAILABLE', 'Available'], ['ON_TRIP', 'On trip'], ['OFFLINE', 'Offline'], ['SUSPENDED', 'Suspended']], 'availability');
  const needs = h('input', { type: 'checkbox', checked: state.needs_update });
  needs.addEventListener('change', () => { state.needs_update = needs.checked; state.offset = 0; load(); });

  let latest = 0;
  async function load() {
    const mine = ++latest; // an older, slower answer must not replace a newer one
    try {
      const data = await api(`/admin/drivers?${buildQuery({ limit: PAGE_SIZE, offset: state.offset, verification: state.verification, availability: state.availability, needs_update: state.needs_update, q: state.q })}`);
      if (mine !== latest) return;
      const rows = stagger(data.items.map((d) => h('tr', { class: 'link', tabindex: '0', onclick: go(d.id), onkeydown: (e) => { if (e.key === 'Enter') go(d.id)(); } },
        h('td', { class: 'name' }, d.full_name), h('td', {}, who(d)), h('td', {}, statusPill(d.verification_status)), h('td', {}, statusPill(d.availability_status)),
        h('td', {}, d.rating === '0.00' ? '-' : d.rating), h('td', {}, rupees(d.hourly_rate)), h('td', {}, d.is_active ? pill('Active', 'ok') : pill('Deactivated', 'off')), h('td', {}, timeAgo(d.created_at)))));
      results.replaceChildren(
        data.items.length === 0
          ? h('div', { class: 'card empty' }, 'No drivers match.')
          : h('div', { class: 'table-wrap' }, h('table', {}, h('thead', {}, h('tr', {}, ...['Driver', 'Contact', 'Approval', 'Availability', 'Rating', 'Rate / hr', 'Account', 'Joined'].map((t) => h('th', {}, t)))), h('tbody', {}, rows))),
        pager(state, data.total, load));
    } catch (e) { if (e.status !== 401) results.replaceChildren(h('div', { class: 'error' }, e.message)); }
  }

  search.addEventListener('input', debounce(() => { state.q = search.value.trim(); state.offset = 0; load(); }, 300));
  load();
  return h('div', {},
    h('div', { class: 'page-head' }, h('h1', {}, 'Drivers')),
    h('div', { class: 'toolbar' }, search, verification, availability, h('label', { class: 'check' }, needs, 'Needs to update details')),
    results);
}

export { formatStatus };
