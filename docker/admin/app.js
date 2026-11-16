// DriveRent admin site. Plain ES modules, no build step. All server text is put on the page with
// textContent (never as HTML), so a name or note typed by a user can never run as code.
import { login, session, setSessionEndHandler, ApiError } from './js/api.js';
import { startBackground } from './js/background.js';
import { bookingPage, bookingsPage } from './js/bookings.js';
import { dashboardPage } from './js/dashboard.js';
import { driverPage } from './js/driver-detail.js';
import { driversPage } from './js/drivers.js';
import { formsPage } from './js/forms.js';
import { mapPage } from './js/map.js';
import { reviewPage } from './js/review.js';
import { runLeave } from './js/lifecycle.js';
import { skeleton, h } from './js/ui.js';
import { userPage, usersPage } from './js/users.js';

const app = document.getElementById('app');
startBackground(document.getElementById('bg'));

let loginNotice = null; // shown once on the login form, e.g. after the session ended
setSessionEndHandler((message) => {
  loginNotice = message;
  if (location.hash) location.hash = '';
  else render();
});

function showLogin(message = loginNotice) {
  loginNotice = null;
  const identifier = h('input', { type: 'text', autocomplete: 'username', required: true, placeholder: 'admin@example.com or 98765 43210', 'aria-label': 'Email or mobile number' });
  const password = h('input', { type: 'password', autocomplete: 'current-password', required: true, 'aria-label': 'Password' });
  const error = h('div', { class: 'error', role: 'alert', hidden: !message }, message || '');
  const submit = h('button', { class: 'btn block', type: 'submit' }, 'Log in');
  const form = h('form', { class: 'login-card rise' },
    h('div', { class: 'brand' }, h('div', { class: 'brand-mark' }, 'DR'), h('div', {}, h('div', { class: 'brand-name' }, 'DriveRent'), h('div', { class: 'muted' }, 'Admin'))),
    h('h1', {}, 'Welcome back'), h('p', { class: 'muted' }, 'Log in with your admin account.'),
    h('label', { class: 'field' }, h('span', {}, 'Email or mobile number'), identifier),
    h('label', { class: 'field' }, h('span', {}, 'Password'), password), error, submit);
  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    submit.disabled = true;
    error.hidden = true;
    try {
      await login(identifier.value.trim(), password.value);
      location.hash = '#/dashboard';
      render();
    } catch (err) {
      error.textContent = err instanceof ApiError ? err.message : 'Something went wrong. Try again.';
      error.hidden = false;
      submit.disabled = false;
    }
  });
  app.replaceChildren(h('div', { class: 'login-wrap' }, form));
  identifier.focus();
}

const NAV = [
  ['dashboard', 'Dashboard'], ['review', 'Review queue'], ['drivers', 'Drivers'], ['users', 'Users'],
  ['bookings', 'Bookings'], ['forms', 'Forms'], ['map', 'Live map'],
];

let renderToken = 0;
async function render() {
  runLeave(); // stop timers and loops of the page we are leaving
  if (!session.access) return showLogin();
  const token = ++renderToken;
  const [path, query = ''] = location.hash.replace(/^#/, '').split('?');
  const params = new URLSearchParams(query);
  const parts = path.split('/').filter(Boolean);
  const section = parts[0] || 'dashboard';
  const ctx = { rerender: render };

  const nav = NAV.map(([key, label]) => h('a', { href: `#/${key}`, class: section === key ? 'active' : '', 'aria-current': section === key ? 'page' : null }, label));
  const content = h('main', { class: 'main' }, skeleton());
  app.replaceChildren(h('div', { class: 'shell' },
    h('aside', { class: 'side' },
      h('div', { class: 'brand' }, h('div', { class: 'brand-mark' }, 'DR'), h('div', { class: 'brand-name' }, 'DriveRent')),
      h('nav', { class: 'nav', 'aria-label': 'Main' }, nav),
      h('div', { class: 'spacer' }), h('div', { class: 'who' }, session.who || 'Admin'),
      h('button', { class: 'btn secondary small', onclick: () => { session.clear(); location.hash = ''; render(); } }, 'Log out')),
    content));

  try {
    const pages = {
      dashboard: () => dashboardPage(),
      review: () => reviewPage(),
      drivers: () => (parts[1] ? driverPage(parts[1], ctx) : driversPage(params)),
      users: () => (parts[1] ? userPage(parts[1]) : usersPage(params)),
      bookings: () => (parts[1] ? bookingPage(parts[1]) : bookingsPage(params)),
      forms: () => formsPage(params, ctx),
      map: () => mapPage(),
    };
    const page = await (pages[section] || pages.dashboard)();
    if (token === renderToken) content.replaceChildren(page);
  } catch (e) {
    if (e.status !== 401 && token === renderToken) content.replaceChildren(h('div', { class: 'error' }, e.message));
  }
}

window.addEventListener('hashchange', render);
render();
