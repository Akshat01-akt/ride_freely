import assert from 'node:assert/strict';
import { test } from 'node:test';

import { buildQuery, fmtSize, formatStatus, lifecycleSteps, projectPoints, timeAgo } from './util.js';

test('formatStatus makes server codes readable', () => {
  assert.equal(formatStatus('NOT_SUBMITTED'), 'Not submitted');
  assert.equal(formatStatus('ON_TRIP'), 'On trip');
  assert.equal(formatStatus('APPROVED'), 'Approved');
  assert.equal(formatStatus(undefined), '-');
});

test('timeAgo words', () => {
  const now = Date.parse('2026-11-16T12:00:00Z');
  assert.equal(timeAgo('2026-11-16T11:59:50Z', now), 'just now');
  assert.equal(timeAgo('2026-11-16T11:58:00Z', now), '2 min ago');
  assert.equal(timeAgo('2026-11-16T09:00:00Z', now), '3 h ago');
  assert.equal(timeAgo('2026-11-14T12:00:00Z', now), '2 days ago');
  assert.equal(timeAgo(null, now), 'never');
});

test('buildQuery drops empty values and encodes the rest', () => {
  assert.equal(buildQuery({ q: '', a: undefined, b: null, c: false }), '');
  assert.equal(buildQuery({ q: '100%_off & more', limit: 25, offset: 0 }), 'q=100%25_off+%26+more&limit=25&offset=0');
  assert.equal(buildQuery({ needs_update: true }), 'needs_update=true');
});

test('fmtSize', () => {
  assert.equal(fmtSize(512), '512 B');
  assert.equal(fmtSize(2048), '2.0 KB');
});

test('lifecycleSteps marks where a driver is', () => {
  const step = (status, availability = 'OFFLINE') => lifecycleSteps(status, availability).map((s) => `${s.key}:${s.state}`).join(' ');
  assert.equal(step('NOT_SUBMITTED'), 'signup:done submitted:current review:todo approved:todo');
  assert.equal(step('PENDING'), 'signup:done submitted:done review:current approved:todo');
  assert.equal(step('APPROVED'), 'signup:done submitted:done review:done approved:current');
  assert.equal(step('REJECTED'), 'signup:done submitted:done review:problem approved:todo');
  assert.equal(step('APPROVED', 'SUSPENDED'), 'signup:done submitted:done review:done approved:problem');
});

test('projectPoints fits every point inside the box and keeps north up', () => {
  const pts = [{ latitude: 10, longitude: 20 }, { latitude: 12, longitude: 24 }];
  const out = projectPoints(pts, 400, 300, 20);
  for (const p of out) {
    assert.ok(p.x >= 20 && p.x <= 380, `x ${p.x}`);
    assert.ok(p.y >= 20 && p.y <= 280, `y ${p.y}`);
  }
  assert.ok(out[1].y < out[0].y, 'higher latitude is higher on screen');
  assert.ok(out[1].x > out[0].x, 'higher longitude is further right');
});

test('projectPoints centres a single driver and survives no drivers', () => {
  assert.deepEqual(projectPoints([{ latitude: 1, longitude: 1 }], 400, 300, 20).map(({ x, y }) => [x, y]), [[200, 150]]);
  assert.deepEqual(projectPoints([], 400, 300, 20), []);
});
