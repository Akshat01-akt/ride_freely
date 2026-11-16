// DOM helpers. Everything from the server is added with createTextNode, never as HTML, so a name or note
// typed by a user can never run as code.
import { formatStatus } from './util.js';

export function h(tag, attrs, ...children) {
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

export const pill = (text, kind) => h('span', { class: `pill ${kind || ''}` }, text);

const STATUS_KIND = {
  APPROVED: 'ok', PENDING: 'warn', REJECTED: 'bad', NOT_SUBMITTED: 'off',
  AVAILABLE: 'ok', SUSPENDED: 'bad', OFFLINE: 'off', ON_TRIP: 'warn', RESERVED: 'warn', BOOKED: 'warn',
  REQUESTED: 'warn', ACCEPTED: 'ok', IN_PROGRESS: 'warn', COMPLETED: 'ok', CANCELLED: 'off', EXPIRED: 'off',
};
export const statusPill = (status) => pill(formatStatus(status), STATUS_KIND[status]);

let toastTimer;
export function toast(message, bad = false) {
  document.querySelector('.toast')?.remove();
  const el = h('div', { class: `toast${bad ? ' bad' : ''}`, role: bad ? 'alert' : 'status' }, message);
  document.body.append(el);
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => el.remove(), 4500);
}

export function openDialog(build) {
  return new Promise((resolve) => {
    const dialog = h('dialog');
    const close = (value) => { dialog.close(); dialog.remove(); resolve(value); };
    build(dialog, close);
    dialog.addEventListener('cancel', () => close(null));
    document.body.append(dialog);
    dialog.showModal();
  });
}

export const confirmBox = (title, text, okLabel) => openDialog((dialog, close) => {
  dialog.append(
    h('h2', {}, title), h('p', { class: 'muted' }, text),
    h('div', { class: 'foot' },
      h('button', { class: 'btn secondary', onclick: () => close(false) }, 'Cancel'),
      h('button', { class: 'btn danger', onclick: () => close(true) }, okLabel)));
});

export const askNote = (title, text, okLabel) => openDialog((dialog, close) => {
  const note = h('textarea', { maxlength: '500', 'aria-label': 'Note for the driver', placeholder: 'Reason (shown to the driver)' });
  dialog.append(
    h('h2', {}, title), h('p', { class: 'muted' }, text), note,
    h('div', { class: 'foot' },
      h('button', { class: 'btn secondary', onclick: () => close(null) }, 'Cancel'),
      h('button', { class: 'btn danger', onclick: () => close(note.value.trim()) }, okLabel)));
});

export const PAGE_SIZE = 25;

export function pager(state, total, reload) {
  const move = (delta) => (e) => { e.currentTarget.disabled = true; state.offset += delta; reload(); };
  const from = total === 0 ? 0 : state.offset + 1;
  const to = Math.min(state.offset + PAGE_SIZE, total);
  return h('div', { class: 'pager' },
    h('span', {}, `${from}–${to} of ${total}`),
    h('button', { class: 'btn secondary small', disabled: state.offset === 0, onclick: move(-PAGE_SIZE) }, 'Previous'),
    h('button', { class: 'btn secondary small', disabled: to >= total, onclick: move(PAGE_SIZE) }, 'Next'));
}

export function debounce(fn, ms) {
  let t;
  return (...args) => { clearTimeout(t); t = setTimeout(() => fn(...args), ms); };
}

/** Rows that fade in one after another; the delay comes from the position, set via the CSSOM (CSP allows it). */
export function stagger(elements) {
  elements.forEach((el, i) => { el.style.setProperty('--i', String(Math.min(i, 12))); el.classList.add('rise'); });
  return elements;
}

/** Counts a number up from zero (skipped when the user prefers reduced motion). */
export function countUp(el, target) {
  const value = Number(target) || 0;
  if (value === 0 || matchMedia('(prefers-reduced-motion: reduce)').matches) { el.textContent = String(value); return; }
  const start = performance.now();
  const step = (now) => {
    const t = Math.min(1, (now - start) / 700);
    el.textContent = String(Math.round(value * (1 - (1 - t) ** 3)));
    if (t < 1) requestAnimationFrame(step);
  };
  requestAnimationFrame(step);
}

export const skeleton = (rows = 4) =>
  h('div', { class: 'skeleton-list', 'aria-busy': 'true', 'aria-label': 'Loading' }, Array.from({ length: rows }, () => h('div', { class: 'skeleton' })));
