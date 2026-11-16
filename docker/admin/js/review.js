import { api } from './api.js';
import { h, skeleton, stagger, statusPill } from './ui.js';
import { timeAgo, who } from './util.js';

/** Applications waiting for a decision, oldest first, each with a preview of what the driver told us. */
export async function reviewPage() {
  const list = await api('/admin/drivers?verification=PENDING&limit=50');
  const details = await Promise.all(list.items.map((d) => api(`/admin/drivers/${d.id}`)));
  details.reverse(); // the list is newest first; review the oldest first
  const cards = details.map((d) => {
    const docs = d.documents;
    const waiting = docs.filter((x) => x.status === 'PENDING').length;
    return h('a', { class: 'queue-card', href: `#/drivers/${d.id}` },
      h('div', { class: 'row' }, h('strong', {}, d.full_name), statusPill(d.verification_status)),
      h('div', { class: 'muted' }, `${who(d)} · applied ${timeAgo(d.created_at)}`),
      h('div', { class: 'chips' }, ...d.answers.slice(0, 4).map((a) => h('span', { class: 'chip' }, `${a.key.replaceAll('_', ' ')}: ${a.value}`))),
      h('div', { class: 'muted' }, `${docs.length} documents · ${waiting} not reviewed yet`),
      h('span', { class: 'btn small' }, 'Review application'));
  });
  return h('div', {},
    h('div', { class: 'page-head' }, h('h1', {}, 'Review queue'), h('span', { class: 'muted' }, `${details.length} waiting`)),
    cards.length === 0 ? h('div', { class: 'card empty' }, 'All caught up. New applications appear here.') : h('div', { class: 'queue' }, stagger(cards)));
}

export { skeleton };
