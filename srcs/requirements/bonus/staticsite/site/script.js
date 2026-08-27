(() => {
  "use strict";

  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  // ── Hero typing effect ────────────────────────────────────────────
  const typed = document.getElementById("typed");
  const HERO_TEXT = "Inception — static site";
  if (typed) {
    if (reduceMotion) {
      typed.textContent = HERO_TEXT;
    } else {
      let i = 0;
      const tick = () => {
        typed.textContent = HERO_TEXT.slice(0, i);
        i++;
        if (i <= HERO_TEXT.length) setTimeout(tick, 45);
      };
      tick();
    }
  }

  // ── Live clock ───────────────────────────────────────────────────
  const clock = document.getElementById("clock");
  if (clock) {
    const pad = (n) => String(n).padStart(2, "0");
    const render = () => {
      const now = new Date();
      clock.textContent =
        `${pad(now.getHours())}:${pad(now.getMinutes())}:${pad(now.getSeconds())}`;
    };
    render();
    setInterval(render, 1000);
  }

  // ── Background: a slow, drifting grid of dots (canvas, no libs) ──
  const canvas = document.getElementById("bg");
  if (canvas && !reduceMotion && canvas.getContext) {
    const ctx = canvas.getContext("2d");
    let w, h, dpr;
    let dots = [];
    const SPACING = 46;

    const resize = () => {
      dpr = Math.min(window.devicePixelRatio || 1, 2);
      w = canvas.clientWidth = window.innerWidth;
      h = canvas.clientHeight = window.innerHeight;
      canvas.width = w * dpr;
      canvas.height = h * dpr;
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);

      dots = [];
      for (let x = 0; x < w + SPACING; x += SPACING) {
        for (let y = 0; y < h + SPACING; y += SPACING) {
          dots.push({ x, y, phase: Math.random() * Math.PI * 2 });
        }
      }
    };

    let t = 0;
    const draw = () => {
      ctx.clearRect(0, 0, w, h);
      ctx.fillStyle = "rgba(110, 231, 183, 0.35)";
      for (const d of dots) {
        const r = 1 + Math.sin(t * 0.6 + d.phase) * 0.7;
        ctx.beginPath();
        ctx.arc(d.x, d.y, Math.max(r, 0.2), 0, Math.PI * 2);
        ctx.fill();
      }
      t += 0.016;
      requestAnimationFrame(draw);
    };

    window.addEventListener("resize", resize, { passive: true });
    resize();
    requestAnimationFrame(draw);
  }
})();
