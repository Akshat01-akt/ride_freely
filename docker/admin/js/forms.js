import { api } from './api.js';
import { askNote, h, openDialog, pill, stagger, toast } from './ui.js';

const TYPES = [['text', 'Short text'], ['number', 'Number'], ['date', 'Date'], ['choice', 'Choice'], ['document', 'Document upload']];

export async function formsPage(params, { rerender }) {
  const role = params.get('role') === 'customer' ? 'customer' : 'driver';
  const form = await api(`/admin/forms/${role}`);

  async function run(label, request) {
    try { await request(); toast(label); rerender(); } catch (e) { if (e.status !== 401) toast(e.message, true); }
  }
  const patch = (f, body, label) => run(label, () => api(`/admin/forms/${role}/fields/${f.id}`, { method: 'PATCH', body }));
  const move = (index, delta) => {
    const ids = form.fields.map((f) => f.id);
    [ids[index], ids[index + delta]] = [ids[index + delta], ids[index]];
    run('Order saved', () => api(`/admin/forms/${role}/order`, { method: 'PUT', body: { ids } }));
  };
  const rename = (f) => openDialog((dialog, close) => {
    const input = h('input', { value: f.label, maxlength: '120', 'aria-label': 'Question text' });
    dialog.append(h('h2', {}, 'Change the question'), input,
      h('div', { class: 'foot' }, h('button', { class: 'btn secondary', onclick: () => close(null) }, 'Cancel'), h('button', { class: 'btn', onclick: () => close(input.value.trim()) }, 'Save')));
  }).then((label) => { if (label) patch(f, { label }, 'Question updated'); });

  const rows = form.fields.map((f, i) => h('div', { class: `field-row${f.is_active ? '' : ' inactive'}` },
    h('div', { class: 'item-main' }, h('div', { class: 'v' }, f.label), h('div', { class: 'muted' }, `${f.key} · ${TYPES.find(([t]) => t === f.field_type)?.[1] || f.field_type}${f.choices ? ` · ${f.choices.join(', ')}` : ''}`)),
    f.is_core ? pill('Core', 'off') : null, f.required ? pill('Required', 'warn') : pill('Optional', 'off'), f.is_active ? null : pill('Hidden', 'off'),
    h('div', { class: 'actions' },
      h('button', { class: 'btn secondary small', disabled: i === 0, 'aria-label': `Move ${f.label} up`, onclick: () => move(i, -1) }, '↑'),
      h('button', { class: 'btn secondary small', disabled: i === form.fields.length - 1, 'aria-label': `Move ${f.label} down`, onclick: () => move(i, 1) }, '↓'),
      h('button', { class: 'btn secondary small', onclick: () => rename(f) }, 'Edit text'),
      h('button', { class: 'btn secondary small', disabled: f.is_core && f.required, onclick: () => patch(f, { required: !f.required }, f.required ? 'Now optional' : 'Now required') }, f.required ? 'Make optional' : 'Make required'),
      f.is_active
        ? h('button', { class: 'btn danger small', disabled: f.is_core, onclick: () => run('Question hidden', () => api(`/admin/forms/${role}/fields/${f.id}`, { method: 'DELETE' })) }, 'Hide')
        : h('button', { class: 'btn small', onclick: () => patch(f, { is_active: true }, 'Question shown again') }, 'Show again'))));

  // add form
  const key = h('input', { placeholder: 'badge_number', maxlength: '40', 'aria-label': 'Key (letters, digits, underscore)' });
  const label = h('input', { placeholder: 'Question shown to the person', maxlength: '120', 'aria-label': 'Question' });
  const type = h('select', { 'aria-label': 'Type' }, ...TYPES.filter(([t]) => role === 'driver' || t !== 'document').map(([v, l]) => h('option', { value: v }, l)));
  const required = h('input', { type: 'checkbox' });
  const choices = h('textarea', { placeholder: 'One option per line', 'aria-label': 'Options', hidden: true });
  type.addEventListener('change', () => { choices.hidden = type.value !== 'choice'; });
  const add = h('button', { class: 'btn', onclick: () => run('Question added', () => api(`/admin/forms/${role}/fields`, { method: 'POST', body: {
    key: key.value.trim(), label: label.value.trim(), field_type: type.value, required: required.checked,
    choices: type.value === 'choice' ? choices.value.split('\n').map((c) => c.trim()).filter(Boolean) : null } })) }, 'Add question');

  const tab = (r, text) => h('a', { class: `tab${role === r ? ' active' : ''}`, href: `#/forms?role=${r}` }, text);
  return h('div', {},
    h('div', { class: 'page-head' }, h('h1', {}, 'Registration forms'), h('span', { class: 'muted' }, `Version ${form.version}`)),
    h('div', { class: 'tabs' }, tab('driver', 'Driver application'), tab('customer', 'Customer profile')),
    h('p', { class: 'muted' }, role === 'driver'
      ? 'Drivers see these questions after they sign up. Core questions feed pricing and search, so they can be reworded but not removed. Approved drivers stay bookable when you add a required question; they get a prompt to answer it.'
      : 'Customers can fill these in from their profile. Nothing here blocks booking.'),
    h('div', { class: 'card' }, h('div', { class: 'field-list' }, stagger(rows))),
    h('div', { class: 'card rise' }, h('h2', {}, 'Add a question'),
      h('div', { class: 'add-grid' }, h('label', { class: 'field' }, h('span', {}, 'Key'), key), h('label', { class: 'field' }, h('span', {}, 'Question'), label), h('label', { class: 'field' }, h('span', {}, 'Type'), type),
        h('label', { class: 'check' }, required, 'Required')), choices, h('div', { class: 'actions' }, add)));
}

export { askNote };
