import { api } from './api.js';
import { countUp, h, stagger, statusPill } from './ui.js';
import { timeAgo, who } from './util.js';

export async function dashboardPage() {
  const [s, queue] = await Promise.all([api('/admin/stats'), api('/admin/drivers?verification=PENDING&limit=5')]);
  const tile = (value, label, href, hot) => {
    const num = h('div', { class: 'num' }, '0');
    countUp(num, value);
    return h('a', { class: `stat${hot ? ' hot' : ''}`, href }, num, h('div', { class: 'label' }, label));
  };
  const tiles = stagger([
    tile(s.drivers.PENDING, 'Applications to review', '#/review', s.drivers.PENDING > 0),
    tile(s.online_now, 'Drivers online now', '#/map', false),
    tile(s.needs_update, 'Approved, need to update', '#/drivers?needs_update=true&verification=APPROVED', s.needs_update > 0),
    tile(s.drivers.REJECTED, 'Waiting on changes', '#/drivers?verification=REJECTED'),
    tile(s.drivers.NOT_SUBMITTED, 'Signed up, not applied', '#/drivers?verification=NOT_SUBMITTED'),
    tile(s.drivers.APPROVED, 'Approved drivers', '#/drivers?verification=APPROVED'),
    tile(s.customers, 'Customers', '#/users?role=customer'),
    tile(s.bookings_today, 'Bookings today', '#/bookings'),
  ]);
  const recent = queue.items.length === 0
    ? h('p', { class: 'muted' }, 'Nothing waiting. New applications show up here.')
    : h('div', { class: 'recent' }, stagger(queue.items.map((d) => h('a', { class: 'recent-row', href: `#/drivers/${d.id}` },
      h('span', { class: 'name' }, d.full_name), h('span', { class: 'muted' }, who(d)), statusPill(d.verification_status), h('span', { class: 'muted' }, timeAgo(d.created_at))))));
  return h('div', {},
    h('div', { class: 'page-head' }, h('h1', {}, 'Dashboard')),
    h('div', { class: 'stats' }, tiles),
    h('div', { class: 'card' }, h('div', { class: 'row' }, h('h2', {}, 'Latest applications'), h('a', { class: 'btn secondary small', href: '#/review' }, 'Open review queue')), recent));
}
