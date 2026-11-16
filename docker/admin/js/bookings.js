import { api } from './api.js';
import { buildQuery, fmtDate, rupees, timeAgo } from './util.js';
import { PAGE_SIZE, h, pager, skeleton, stagger, statusPill } from './ui.js';

const STATUSES = ['REQUESTED', 'ACCEPTED', 'IN_PROGRESS', 'COMPLETED', 'REJECTED', 'CANCELLED', 'EXPIRED'];

export async function bookingsPage(params) {
  const state = { offset: 0, status: params.get('status') || '' };
  const results = h('div', {}, skeleton());
  const status = h('select', { 'aria-label': 'Filter by status' },
    h('option', { value: '' }, 'Any status'), ...STATUSES.map((s) => h('option', { value: s, selected: s === state.status }, s.replaceAll('_', ' ').toLowerCase())));
  let latest = 0;
  async function load() {
    const mine = ++latest;
    try {
      const data = await api(`/admin/bookings?${buildQuery({ limit: PAGE_SIZE, offset: state.offset, status: state.status })}`);
      if (mine !== latest) return;
      const rows = stagger(data.items.map((b) => h('tr', { class: 'link', tabindex: '0', onclick: () => { location.hash = `#/bookings/${b.id}`; }, onkeydown: (e) => { if (e.key === 'Enter') location.hash = `#/bookings/${b.id}`; } },
        h('td', { class: 'name' }, b.customer_name), h('td', {}, b.driver_name), h('td', {}, statusPill(b.status)), h('td', {}, fmtDate(b.start_time)),
        h('td', {}, `${b.hours} h`), h('td', {}, rupees(b.price_amount)), h('td', {}, timeAgo(b.created_at)))));
      results.replaceChildren(
        data.items.length === 0 ? h('div', { class: 'card empty' }, 'No bookings match.')
          : h('div', { class: 'table-wrap' }, h('table', {}, h('thead', {}, h('tr', {}, ...['Customer', 'Driver', 'Status', 'Starts', 'Length', 'Price', 'Created'].map((t) => h('th', {}, t)))), h('tbody', {}, rows))),
        pager(state, data.total, load));
    } catch (e) { if (e.status !== 401) results.replaceChildren(h('div', { class: 'error' }, e.message)); }
  }
  status.addEventListener('change', () => { state.status = status.value; state.offset = 0; load(); });
  load();
  return h('div', {}, h('div', { class: 'page-head' }, h('h1', {}, 'Bookings')), h('div', { class: 'toolbar' }, status), results);
}

export async function bookingPage(id) {
  const b = await api(`/admin/bookings/${encodeURIComponent(id)}`);
  const fact = (k, v) => h('div', { class: 'fact' }, h('div', { class: 'k' }, k), h('div', { class: 'v' }, v));
  return h('div', {},
    h('div', { class: 'page-head' }, h('div', {}, h('a', { class: 'back', href: '#/bookings' }, '← All bookings'), h('h1', {}, `${b.customer_name} → ${b.driver_name}`))),
    h('div', { class: 'card rise' },
      h('div', { class: 'actions' }, statusPill(b.status)),
      h('div', { class: 'facts' }, fact('Starts', fmtDate(b.start_time)), fact('Ends', fmtDate(b.end_time)), fact('Length', `${b.hours} h (${b.booking_type.replaceAll('_', ' ').toLowerCase()})`),
        fact('Price', rupees(b.price_amount)), fact('Pickup', b.pickup_address), fact('Notes', b.notes || '-'), fact('Rating', b.rating ?? 'Not rated'),
        fact('Created', fmtDate(b.created_at)), fact('Completed', fmtDate(b.completed_at))),
      h('div', { class: 'actions' }, h('a', { class: 'btn secondary', href: `#/drivers/${b.driver_id}` }, `Driver: ${b.driver_name}`),
        h('a', { class: 'btn secondary', href: `#/users?q=${encodeURIComponent(b.customer_name)}` }, `Customer: ${b.customer_name}`))));
}
