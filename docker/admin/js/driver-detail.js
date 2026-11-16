import { api } from './api.js';
import { askNote, confirmBox, h, openDialog, pill, stagger, statusPill, toast } from './ui.js';
import { fmtDate, fmtSize, lifecycleSteps, rupees, timeAgo } from './util.js';

async function viewDocument(doc) {
  let url;
  let closed = false;
  const done = openDialog((dialog, close) => {
    const body = h('div', { class: 'viewer' }, h('div', { class: 'loading' }, 'Loading document…'));
    dialog.append(h('h2', {}, doc.doc_type.replaceAll('_', ' ')), body, h('div', { class: 'foot' }, h('button', { class: 'btn', onclick: () => close() }, 'Close')));
    api(`/admin/documents/${doc.id}/file`, { blob: true }).then((blob) => {
      if (closed) return; // closed before it arrived: nothing to show, nothing to free
      url = URL.createObjectURL(blob);
      body.replaceChildren(blob.type.startsWith('image/')
        ? h('img', { src: url, alt: `${doc.doc_type} uploaded by the driver` })
        : h('a', { class: 'btn', href: url, target: '_blank', rel: 'noopener' }, 'Open PDF in a new tab'));
    }).catch((e) => body.replaceChildren(h('div', { class: 'error' }, e.message)));
  });
  await done;
  closed = true;
  if (url) URL.revokeObjectURL(url);
}

export async function driverPage(id, { rerender }) {
  const d = await api(`/admin/drivers/${encodeURIComponent(id)}`);

  async function run(label, request) {
    try { await request(); toast(label); rerender(); } catch (e) { if (e.status !== 401) toast(e.message, true); }
  }
  const decide = async (what, status, send) => {
    let note = null;
    if (status === 'REJECTED') {
      note = await askNote(`Send this ${what} back?`, 'Tell the driver what is wrong so they can fix it. They will see this note.', 'Send back');
      if (note === null) return;
    }
    run(status === 'APPROVED' ? `${what} approved` : `${what} sent back`, () => send(status, note || null));
  };

  const timeline = h('ol', { class: 'timeline' }, stagger(lifecycleSteps(d.verification_status, d.availability_status)
    .map((s) => h('li', { class: s.state }, h('span', { class: 'dot' }), h('span', {}, s.label)))));

  const itemRow = (label, value, status, note, buttons) => h('div', { class: 'item' },
    h('div', { class: 'item-main' }, h('div', { class: 'k' }, label), h('div', { class: 'v' }, value), note ? h('div', { class: 'note' }, `Note: ${note}`) : null),
    statusPill(status), h('div', { class: 'actions' }, buttons));

  const answerRows = d.answers.map((a) => itemRow(a.key.replaceAll('_', ' '), a.value, a.status, a.review_note, [
    a.status !== 'APPROVED' ? h('button', { class: 'btn small', onclick: () => decide('answer', 'APPROVED', (status, note) => api(`/admin/drivers/${d.id}/answers/${encodeURIComponent(a.key)}`, { method: 'PATCH', body: { status, note } })) }, 'Approve') : null,
    a.status !== 'REJECTED' ? h('button', { class: 'btn danger small', onclick: () => decide('answer', 'REJECTED', (status, note) => api(`/admin/drivers/${d.id}/answers/${encodeURIComponent(a.key)}`, { method: 'PATCH', body: { status, note } })) }, 'Send back') : null,
  ]));

  const docRows = d.documents.map((doc) => h('div', { class: 'item' },
    h('div', { class: 'item-main' }, h('div', { class: 'k' }, doc.doc_type.replaceAll('_', ' ')), h('div', { class: 'muted' }, `${doc.content_type} · ${fmtSize(doc.size_bytes)} · ${timeAgo(doc.updated_at)}`),
      doc.review_note ? h('div', { class: 'note' }, `Note: ${doc.review_note}`) : null),
    statusPill(doc.status),
    h('div', { class: 'actions' },
      h('button', { class: 'btn secondary small', onclick: () => viewDocument(doc) }, 'View'),
      doc.status !== 'APPROVED' ? h('button', { class: 'btn small', onclick: () => decide('document', 'APPROVED', (status, note) => api(`/admin/documents/${doc.id}`, { method: 'PATCH', body: { status, note } })) }, 'Approve') : null,
      doc.status !== 'REJECTED' ? h('button', { class: 'btn danger small', onclick: () => decide('document', 'REJECTED', (status, note) => api(`/admin/documents/${doc.id}`, { method: 'PATCH', body: { status, note } })) }, 'Send back') : null)));

  const fact = (k, v) => h('div', { class: 'fact' }, h('div', { class: 'k' }, k), h('div', { class: 'v' }, v));
  const suspended = d.availability_status === 'SUSPENDED';
  const actions = h('div', { class: 'actions' },
    d.verification_status !== 'APPROVED' ? h('button', { class: 'btn', onclick: () => run('Driver approved', () => api(`/admin/drivers/${d.id}/verification`, { method: 'PATCH', body: { status: 'APPROVED' } })) }, 'Approve driver') : null,
    d.verification_status !== 'REJECTED' ? h('button', { class: 'btn danger', onclick: async () => {
      const note = await askNote('Send this driver back for changes?', 'They go offline and cannot take bookings until approved again.', 'Send back');
      if (note !== null) run('Driver sent back', () => api(`/admin/drivers/${d.id}/verification`, { method: 'PATCH', body: { status: 'REJECTED', note: note || null } }));
    } }, 'Needs changes') : null,
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
      h('div', { class: 'actions' }, statusPill(d.verification_status), statusPill(d.availability_status), d.is_active ? pill('Account active', 'ok') : pill('Account deactivated', 'off'),
        d.needs_update.length ? pill(`Needs to update: ${d.needs_update.join(', ')}`, 'warn') : null),
      timeline,
      h('div', { class: 'facts' }, fact('Phone', d.phone || '-'), fact('Email', d.email || '-'), fact('Hourly rate', rupees(d.hourly_rate)), fact('Rating', d.rating === '0.00' ? 'Not rated yet' : d.rating),
        fact('Completed trips', d.completed_trips), fact('Last seen', d.last_seen ? timeAgo(d.last_seen) : 'Never shared a location'), fact('Joined', fmtDate(d.created_at))),
      actions),
    h('div', { class: 'card rise' }, h('h2', {}, 'Application answers'),
      d.answers.length === 0 ? h('p', { class: 'muted' }, 'The driver has not submitted their details yet.') : h('div', { class: 'items' }, answerRows)),
    h('div', { class: 'card rise' }, h('h2', {}, 'Documents'),
      d.documents.length === 0 ? h('p', { class: 'muted' }, 'No documents uploaded yet.') : h('div', { class: 'items' }, docRows)));
}
