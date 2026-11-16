import { api } from './api.js';
import { h, statusPill } from './ui.js';
import { projectPoints, timeAgo } from './util.js';

const COLORS = { AVAILABLE: '#34d399', RESERVED: '#fbbf24', BOOKED: '#fb923c', ON_TRIP: '#60a5fa' };
const POLL_MS = 5000;

/** Live positions of online drivers. A plain plot (no map tiles): it needs no outside service and no keys. */
export async function mapPage() {
  const canvas = h('canvas', { class: 'map-canvas', role: 'img', 'aria-label': 'Live driver positions' });
  const info = h('div', { class: 'card map-info' }, h('p', { class: 'muted' }, 'Click a driver to see details.'));
  const count = h('span', { class: 'muted' }, '');
  const list = h('div', { class: 'map-list' });
  let drivers = [];
  let placed = [];
  let selected = null;
  let timer;
  let raf;
  let failed = false;

  const reduce = matchMedia('(prefers-reduced-motion: reduce)');

  function draw(t = 0) {
    const box = canvas.getBoundingClientRect();
    const dpr = Math.min(devicePixelRatio || 1, 2);
    const w = Math.max(320, Math.round(box.width));
    const hgt = Math.max(260, Math.round(box.height || 420));
    if (canvas.width !== w * dpr) { canvas.width = w * dpr; canvas.height = hgt * dpr; }
    const ctx = canvas.getContext('2d');
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, w, hgt);
    ctx.strokeStyle = 'rgba(255,255,255,0.06)';
    ctx.lineWidth = 1;
    for (let x = 0; x < w; x += 48) { ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, hgt); ctx.stroke(); }
    for (let y = 0; y < hgt; y += 48) { ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(w, y); ctx.stroke(); }
    placed = projectPoints(drivers, w, hgt, 48);
    for (const p of placed) {
      const color = COLORS[p.status] || '#fff';
      if (!reduce.matches) {
        const phase = ((t / 1400) + (p.x % 7) / 7) % 1;
        ctx.beginPath();
        ctx.arc(p.x, p.y, 8 + phase * 18, 0, Math.PI * 2);
        ctx.strokeStyle = color;
        ctx.globalAlpha = 0.5 * (1 - phase);
        ctx.stroke();
        ctx.globalAlpha = 1;
      }
      ctx.beginPath();
      ctx.arc(p.x, p.y, p.id === selected ? 9 : 7, 0, Math.PI * 2);
      ctx.fillStyle = color;
      ctx.fill();
      ctx.lineWidth = 2;
      ctx.strokeStyle = p.id === selected ? '#fff' : 'rgba(0,0,0,0.5)';
      ctx.stroke();
      ctx.fillStyle = '#fff';
      ctx.font = '12px system-ui, sans-serif';
      ctx.fillText(p.name, p.x + 12, p.y + 4);
    }
    if (drivers.length === 0) {
      ctx.fillStyle = 'rgba(255,255,255,0.6)';
      ctx.font = '15px system-ui, sans-serif';
      ctx.textAlign = 'center';
      ctx.fillText(failed ? 'Could not load positions. Retrying…' : 'No drivers are online right now.', w / 2, hgt / 2);
      ctx.textAlign = 'start';
    }
  }

  function loop(t) {
    draw(t);
    raf = requestAnimationFrame(loop);
  }

  function showInfo(d) {
    selected = d?.id ?? null;
    info.replaceChildren(d
      ? h('div', {}, h('h2', {}, d.name), h('div', { class: 'actions' }, statusPill(d.status)),
        h('p', { class: 'muted' }, `Updated ${timeAgo(d.recorded_at)}${d.speed != null ? ` · ${Math.round(d.speed * 3.6)} km/h` : ''}`),
        h('a', { class: 'btn small', href: `#/drivers/${d.id}` }, 'Open driver'))
      : h('p', { class: 'muted' }, 'Click a driver to see details.'));
  }

  canvas.addEventListener('click', (e) => {
    const box = canvas.getBoundingClientRect();
    const x = e.clientX - box.left;
    const y = e.clientY - box.top;
    const hit = placed.find((p) => Math.hypot(p.x - x, p.y - y) < 16);
    showInfo(hit || null);
    if (reduce.matches) draw();
  });

  function renderList() {
    count.textContent = `${drivers.length} online`;
    list.replaceChildren(...drivers.map((d) => h('button', { class: `map-row${d.id === selected ? ' active' : ''}`, onclick: () => { showInfo(d); renderList(); if (reduce.matches) draw(); } },
      h('span', { class: 'swatch', 'data-status': d.status }), h('span', { class: 'name' }, d.name), h('span', { class: 'muted' }, timeAgo(d.recorded_at)))));
  }

  async function poll() {
    if (!document.hidden) {
      try {
        drivers = (await api('/admin/drivers/live')).drivers;
        failed = false;
        if (selected && !drivers.some((d) => d.id === selected)) showInfo(null);
        renderList();
      } catch (e) { if (e.status === 401) return; failed = true; }
      if (reduce.matches) draw();
    }
    timer = setTimeout(poll, POLL_MS);
  }

  // The page element is replaced on navigation; stop polling and drawing when it leaves the document.
  const root = h('div', {},
    h('div', { class: 'page-head' }, h('h1', {}, 'Live map'), count),
    h('div', { class: 'map-layout' }, h('div', { class: 'card map-card' }, canvas), h('div', {}, info, h('div', { class: 'card' }, list))),
    h('div', { class: 'legend' }, Object.entries(COLORS).map(([s, c]) => h('span', { class: 'legend-item' }, h('span', { class: 'swatch', 'data-status': s }), s.replaceAll('_', ' ').toLowerCase()))));
  const watchdog = setInterval(() => {
    if (!root.isConnected) { clearTimeout(timer); cancelAnimationFrame(raf); clearInterval(watchdog); }
  }, 1000);
  await poll();
  if (!reduce.matches) raf = requestAnimationFrame(loop);
  requestAnimationFrame(() => draw());
  return root;
}
