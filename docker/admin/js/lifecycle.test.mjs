import assert from 'node:assert/strict';
import { test } from 'node:test';

import { onLeave, runLeave } from './lifecycle.js';

test('leave handlers run once, when the page is left', () => {
  const calls = [];
  onLeave(() => calls.push('a'));
  onLeave(() => calls.push('b'));
  runLeave();
  runLeave();
  assert.deepEqual(calls, ['a', 'b']);
});

test('a handler that throws does not stop the others', () => {
  const calls = [];
  onLeave(() => { throw new Error('boom'); });
  onLeave(() => calls.push('after'));
  runLeave();
  assert.deepEqual(calls, ['after']);
});
