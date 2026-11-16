import assert from 'node:assert/strict';
import { test } from 'node:test';

// A tiny stand-in for the browser, enough to see what h() builds.
class Node_ { constructor(type) { this.nodeType = type; this.children = []; this.attrs = {}; this.listeners = {}; }
  append(...c) { this.children.push(...c); }
  setAttribute(k, v) { this.attrs[k] = v; }
  addEventListener(k, f) { this.listeners[k] = f; } }
globalThis.document = {
  createElement: (tag) => Object.assign(new Node_(1), { tag, innerHTML: undefined }),
  createTextNode: (text) => Object.assign(new Node_(3), { text }),
};

const { h } = await import('./ui.js');

test('text from the server becomes a text node, never markup', () => {
  const evil = '<img src=x onerror=alert(1)>';
  const el = h('div', {}, evil);
  assert.equal(el.children.length, 1);
  assert.equal(el.children[0].nodeType, 3);
  assert.equal(el.children[0].text, evil);
  assert.equal(el.innerHTML, undefined, 'innerHTML is never assigned');
});

test('attributes go through setAttribute and handlers through listeners', () => {
  const click = () => {};
  const el = h('button', { class: 'btn', onclick: click, hidden: false, disabled: true });
  assert.equal(el.className, 'btn');
  assert.equal(el.listeners.click, click);
  assert.equal('hidden' in el.attrs, false);
  assert.equal(el.attrs.disabled, '');
});
