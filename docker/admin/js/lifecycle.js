// Things a page starts (timers, animation loops) register a cleanup here; the router runs them when the page is left.
let handlers = [];

export const onLeave = (fn) => { handlers.push(fn); };

export function runLeave() {
  const run = handlers;
  handlers = [];
  for (const fn of run) {
    try { fn(); } catch { /* one failing cleanup must not stop the others */ }
  }
}
