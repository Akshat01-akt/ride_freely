// Pure helpers: no DOM, so they can be tested with `node --test`.

export const formatStatus = (status) =>
  status ? status.replaceAll('_', ' ').toLowerCase().replace(/^./, (c) => c.toUpperCase()) : '-';

export function timeAgo(iso, now = Date.now()) {
  if (!iso) return 'never';
  const seconds = Math.max(0, Math.round((now - Date.parse(iso)) / 1000));
  if (seconds < 30) return 'just now';
  if (seconds < 3600) return `${Math.max(1, Math.round(seconds / 60))} min ago`;
  if (seconds < 86400) return `${Math.round(seconds / 3600)} h ago`;
  return `${Math.round(seconds / 86400)} days ago`;
}

/** Query string without empty values; URLSearchParams does the encoding. */
export function buildQuery(params) {
  const q = new URLSearchParams();
  for (const [key, value] of Object.entries(params)) {
    if (value === undefined || value === null || value === false || value === '') continue;
    q.set(key, String(value));
  }
  return q.toString();
}

export const fmtSize = (bytes) => (bytes < 1024 ? `${bytes} B` : `${(bytes / 1024).toFixed(1)} KB`);
export const rupees = (amount) => (amount === null || amount === undefined ? '-' : `₹${amount}`);
export const fmtDate = (iso) =>
  iso ? new Date(iso).toLocaleString('en-IN', { dateStyle: 'medium', timeStyle: 'short' }) : '-';
export const who = (u) => u.phone || u.email || '-';

/** The stages of a driver's life, for the timeline. state: done | current | todo | problem. */
export function lifecycleSteps(verification, availability) {
  const past = { NOT_SUBMITTED: 1, PENDING: 2, REJECTED: 2, APPROVED: 3 }[verification] ?? 1;
  const steps = [
    ['signup', 'Signed up'],
    ['submitted', 'Application submitted'],
    ['review', 'Documents reviewed'],
    ['approved', 'Approved and bookable'],
  ];
  return steps.map(([key, label], i) => {
    let state = i < past ? 'done' : i === past ? 'current' : 'todo';
    if (key === 'review' && verification === 'REJECTED') state = 'problem';
    if (key === 'approved' && verification === 'APPROVED') state = availability === 'SUSPENDED' ? 'problem' : 'current';
    if (key === 'approved' && verification === 'APPROVED' && availability === 'SUSPENDED') return { key, label: 'Suspended', state };
    return { key, label, state };
  });
}

/** Fit points (latitude/longitude) into a width x height box with padding; north is up. */
export function projectPoints(points, width, height, pad) {
  if (points.length === 0) return [];
  const lats = points.map((p) => p.latitude);
  const lngs = points.map((p) => p.longitude);
  const [minLat, maxLat, minLng, maxLng] = [Math.min(...lats), Math.max(...lats), Math.min(...lngs), Math.max(...lngs)];
  const spanLat = maxLat - minLat;
  const spanLng = maxLng - minLng;
  const innerW = width - 2 * pad;
  const innerH = height - 2 * pad;
  if (spanLat === 0 && spanLng === 0) return points.map((p) => ({ ...p, x: width / 2, y: height / 2 }));
  // Keep a true aspect ratio (longitude shrinks with latitude), so distances look right.
  const lngScale = Math.cos(((minLat + maxLat) / 2) * Math.PI / 180);
  const w = Math.max(spanLng * lngScale, 1e-9);
  const hgt = Math.max(spanLat, 1e-9);
  const scale = Math.min(innerW / w, innerH / hgt);
  const offsetX = (width - w * scale) / 2;
  const offsetY = (height - hgt * scale) / 2;
  return points.map((p) => ({
    ...p,
    x: offsetX + (p.longitude - minLng) * lngScale * scale,
    y: offsetY + (maxLat - p.latitude) * scale,
  }));
}
