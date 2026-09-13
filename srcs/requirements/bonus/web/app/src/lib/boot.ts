// srcs/requirements/bonus/web/app/src/lib/boot.ts
// Runs once per page from the layout: theme, status bar, keymap, palette,
// cheatsheet, the poll loop and the motion fallbacks. ~all of the shared JS.
import { fmt } from './api';
import { live } from './live';
import { installKeymap } from './keymap';
import { createPalette } from './palette';
import { installMotionFallbacks } from './motion';

try { const t = localStorage.getItem('lab-theme'); if (t && t !== 'vga') document.documentElement.dataset.theme = t; } catch { /* no storage */ }

const status = document.getElementById('status')!;
const stApi = document.getElementById('st-api')!;
const stReq = document.getElementById('st-req')!;
const stHit = document.getElementById('st-hit')!;
const stClock = document.getElementById('st-clock')!;

function clock() { stClock.textContent = fmt.clock(new Date()); }
clock(); setInterval(clock, 15000);

let retryTimer: ReturnType<typeof setInterval> | undefined;
live.on((ev) => {
  if (ev.type === 'stats') {
    const c = ev.stats.counters;
    stReq.textContent = `req ${fmt.int(c.http_requests)}`;
    stHit.textContent = `hit ${fmt.pct(c.cache_hit, c.cache_hit + c.cache_miss)}`;
    if (retryTimer) { clearInterval(retryTimer); retryTimer = undefined; }
    status.dataset.health = 'ok';
    stApi.textContent = `api ok ${ev.stats.source}`;
  } else if (ev.type === 'health') {
    if (ev.ok) { status.dataset.health = 'ok'; stApi.textContent = `api ok ${ev.latencyMs ?? 0}ms`; }
    else {
      status.dataset.health = 'down';
      let left = ev.retryInS;
      const paint = () => { stApi.textContent = `api offline — retry ${left}s`; if (left > 0) left--; };
      paint();
      if (retryTimer) clearInterval(retryTimer);
      retryTimer = setInterval(paint, 1000);
    }
  }
});

const cheat = document.getElementById('cheatsheet') as HTMLDialogElement;
const palette = createPalette({ cheatsheet: () => { if (!cheat.open) cheat.showModal(); } });
document.getElementById('cheatsheet-close')?.addEventListener('click', () => cheat.close());
cheat.addEventListener('click', (ev) => { if (ev.target === cheat) cheat.close(); });
document.querySelectorAll<HTMLElement>('[data-open-palette]').forEach((el) =>
  el.addEventListener('click', () => palette.open(el.dataset.openPalette ?? '')));
document.querySelectorAll<HTMLElement>('[data-open-cheatsheet]').forEach((el) =>
  el.addEventListener('click', () => cheat.showModal()));

document.addEventListener('lab:palette', (ev) => palette.open(String((ev as CustomEvent).detail ?? '')));

installKeymap({
  palette: (prefill) => palette.open(prefill),
  cheatsheet: () => (cheat.open ? cheat.close() : cheat.showModal()),
  closeAll: () => { let any = false; document.querySelectorAll<HTMLDialogElement>('dialog[open]').forEach((d) => { d.close(); any = true; }); return any; },
});

installMotionFallbacks();
live.start();
