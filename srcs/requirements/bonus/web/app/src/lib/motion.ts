// srcs/requirements/bonus/web/app/src/lib/motion.ts
// CSS scroll-driven animations do the work where they exist. Elsewhere the
// same two effects (meter fill, stroke draw) run once through WAAPI when the
// element enters the viewport. Reduced motion: final state, no animation.
export function installMotionFallbacks() {
  const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const native = CSS.supports('animation-timeline: view()');
  const draws = document.querySelectorAll<SVGElement>('.draw');
  const bars = document.querySelectorAll<HTMLElement>('.meter .bar');
  if (reduced) { draws.forEach((d) => d.classList.add('draw--done')); return; }
  if (native) return;
  const io = new IntersectionObserver((entries) => {
    for (const en of entries) {
      if (!en.isIntersecting) continue;
      const el = en.target as HTMLElement;
      io.unobserve(el);
      if (el.matches('.draw')) {
        el.querySelectorAll<SVGElement>('path, polyline').forEach((p, i) =>
          p.animate([{ strokeDashoffset: 1 }, { strokeDashoffset: 0 }], { duration: 900, delay: i * 120, easing: 'steps(12)', fill: 'forwards' }));
        el.classList.add('draw--done');
      } else {
        el.animate([{ clipPath: 'inset(0 100% 0 0)' }, { clipPath: 'inset(0 0 0 0)' }], { duration: 600, easing: 'steps(16)', fill: 'both' });
      }
    }
  }, { threshold: 0.2 });
  draws.forEach((d) => io.observe(d));
  bars.forEach((b) => io.observe(b));
}
