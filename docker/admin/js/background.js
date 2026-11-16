// A slow aurora of drifting glows and floating particles behind everything. Skipped for reduced motion.

export function startBackground(canvas) {
  const reduce = matchMedia('(prefers-reduced-motion: reduce)');
  const ctx = canvas.getContext('2d');
  let width = 0;
  let height = 0;
  let frame = 0;
  const blobs = [
    { x: 0.2, y: 0.25, r: 0.38, hue: 336, speed: 0.00011 },
    { x: 0.8, y: 0.2, r: 0.32, hue: 262, speed: 0.00009 },
    { x: 0.55, y: 0.85, r: 0.4, hue: 200, speed: 0.00013 },
  ];
  const dots = Array.from({ length: 36 }, (_, i) => ({ x: (i * 97) % 100 / 100, y: (i * 53) % 100 / 100, s: 0.4 + (i % 5) * 0.25, v: 0.00002 + (i % 7) * 0.000006 }));

  function resize() {
    const dpr = Math.min(devicePixelRatio || 1, 2);
    width = innerWidth;
    height = innerHeight;
    canvas.width = width * dpr;
    canvas.height = height * dpr;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  }

  function draw(t) {
    ctx.clearRect(0, 0, width, height);
    for (const b of blobs) {
      const cx = (b.x + Math.sin(t * b.speed * 6) * 0.08) * width;
      const cy = (b.y + Math.cos(t * b.speed * 5) * 0.08) * height;
      const r = b.r * Math.max(width, height);
      const g = ctx.createRadialGradient(cx, cy, 0, cx, cy, r);
      g.addColorStop(0, `hsla(${b.hue}, 85%, 55%, 0.30)`);
      g.addColorStop(1, `hsla(${b.hue}, 85%, 55%, 0)`);
      ctx.fillStyle = g;
      ctx.fillRect(0, 0, width, height);
    }
    ctx.fillStyle = 'rgba(255,255,255,0.35)';
    for (const d of dots) {
      const y = ((d.y - t * d.v) % 1 + 1) % 1;
      ctx.beginPath();
      ctx.arc(d.x * width, y * height, d.s, 0, Math.PI * 2);
      ctx.fill();
    }
  }

  function loop(t) {
    draw(t);
    frame = requestAnimationFrame(loop);
  }

  function apply() {
    cancelAnimationFrame(frame);
    resize();
    if (reduce.matches) draw(0); // one still frame
    else frame = requestAnimationFrame(loop);
  }

  addEventListener('resize', apply);
  reduce.addEventListener('change', apply);
  document.addEventListener('visibilitychange', () => (document.hidden ? cancelAnimationFrame(frame) : apply()));
  apply();
}
