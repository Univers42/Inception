// srcs/requirements/bonus/web/app/src/lib/commands.ts
// The palette's vocabulary. Only real commands; each one does one thing the
// API or the page can actually do. Imported at build time by the cheatsheet
// and at run time by the palette, so this module touches no DOM at load.
import { api, ApiError, CABINETS, fmt } from './api';
import { live } from './live';
import { traffic } from './traffic';
import { WIRES, wireFmt } from './wires';

export interface Ctx {
  print(line: string, cls?: 'ok' | 'err' | 'attn'): void;
  close(): void;
  cheatsheet(): void;
}
export interface Command { name: string; usage: string; help: string; run(args: string[], c: Ctx): void | Promise<void> }

const base = '/lab/';
const PAGES: Record<string, string> = { room: '', home: '', flights: 'flights/', guestbook: 'guestbook/', about: 'about/' };
const THEMES = ['vga', 'green', 'amber'];

export function setTheme(t: string) {
  const root = document.documentElement;
  if (t === 'vga') delete root.dataset.theme; else root.dataset.theme = t;
  try { localStorage.setItem('lab-theme', t); } catch { /* private mode: not persisted, still applied */ }
}

function go(path: string, c: Ctx) { c.close(); location.assign(base + path); }

function errLine(e: unknown): string {
  if (e instanceof ApiError) return `api ${e.status || 'down'}: ${e.code}${e.field ? ` (${e.field})` : ''} — ${e.message}` + (e.retryAfterS ? `; retry in ${e.retryAfterS}s` : '');
  return String((e as Error)?.message ?? e);
}

export const commands: Command[] = [
  { name: 'help', usage: 'help', help: 'keys and commands', run: (_a, c) => { c.close(); c.cheatsheet(); } },
  { name: 'goto', usage: 'goto room|flights|guestbook|about', help: 'open a page',
    run: (a, c) => { const p = PAGES[a[0] ?? '']; if (p === undefined) c.print(`goto: no such page: ${a[0] ?? ''} (room, flights, guestbook, about)`, 'err'); else go(p, c); } },
  { name: 'flights', usage: 'flights', help: 'the departures board', run: (_a, c) => go('flights/', c) },
  { name: 'flight', usage: 'flight <id|callsign>', help: 'one flight',
    run: async (a, c) => {
      const q = (a[0] ?? '').toUpperCase();
      if (!q) return c.print('flight: which one? an id or a callsign like PKT-0003', 'err');
      if (/^\d+$/.test(q)) return go(`flights/${q}/`, c);
      try {
        const list = live.flights ?? (await api.flights());
        const f = list.find((x) => x.callsign.toUpperCase() === q);
        if (!f) c.print(`flight: ${q} is not on the board`, 'err'); else go(`flights/${f.id}/`, c);
      } catch (e) { c.print(errLine(e), 'err'); }
    } },
  { name: 'stats', usage: 'stats', help: 'live counters, from the API right now',
    run: async (_a, c) => {
      try {
        const s = await api.stats();
        c.print(`source ${s.source}  uptime ${fmt.mmss(s.gauges.uptime_s)}  rss ${s.gauges.rss_mb} MB  pool ${s.gauges.db_pool.size}/${s.gauges.db_pool.limit}`, 'attn');
        for (const [k, v] of Object.entries(s.counters)) c.print(`${k.padEnd(16)} ${fmt.int(v).padStart(8)}`);
        c.print(`flights  boarding ${s.flights.boarding}  en-route ${s.flights['en-route']}  landed ${s.flights.landed}  diverted ${s.flights.diverted}`);
      } catch (e) { c.print(errLine(e), 'err'); }
    } },
  { name: 'health', usage: 'health', help: 'GET /api/v1/healthz',
    run: async (_a, c) => {
      try {
        const h = await api.health();
        c.print(`api ${h.ok ? 'ok' : 'DEGRADED'}${h.draining ? ' (draining)' : ''}  uptime ${fmt.mmss(h.uptime_s)}`, h.ok ? 'ok' : 'err');
        c.print(`mariadb ${h.mariadb.ok ? `ok ${h.mariadb.latency_ms} ms` : `down: ${h.mariadb.error}`}`, h.mariadb.ok ? 'ok' : 'err');
        c.print(`redis   ${h.redis.ok ? `ok ${h.redis.latency_ms} ms` : `down: ${h.redis.error}`}`, h.redis.ok ? 'ok' : 'err');
      } catch (e) { c.print(errLine(e), 'err'); }
    } },
  { name: 'wires', usage: 'wires', help: 'traffic on each wire, from the live stream',
    run: async (_a, c) => {
      const already = traffic.state === 'live';
      const release = traffic.acquire();
      try {
        // a stream opened just now needs two samples before the sampled wires say anything
        if (!already) { c.print('wires: listening to /api/v1/traffic for 2.5 s …'); await new Promise((r) => setTimeout(r, 2500)); }
        if (traffic.state !== 'live') return c.print(`wires: stream ${traffic.state}`, 'err');
        c.print(`${'wire'.padEnd(20)} ${'req/s'.padStart(7)} ${'p50'.padStart(9)}  1 dot`, 'attn');
        for (const w of WIRES) {
          const s = traffic.wires[w.id];
          const rate = s.err ? `down: ${s.err}` : fmt.int(s.rate);
          const p50 = w.sampled ? 'sampled' : s.p50 === null ? '—' : `${wireFmt.ms(s.p50)} ms`;
          c.print(`${`${w.from} → ${w.to}`.padEnd(20)} ${rate.padStart(7)} ${p50.padStart(9)}  ${fmt.int(s.per)} req`, s.err ? 'err' : undefined);
        }
      } finally { release(); }
    } },
  { name: 'dispatch', usage: 'dispatch <from> <to> [kb] [note…]', help: 'POST a flight between two cabinets',
    run: async (a, c) => {
      const [origin, destination, kb, ...note] = a;
      if (!origin || !destination) return c.print(`dispatch: usage: dispatch <from> <to> [kb] [note]  — cabinets: ${CABINETS.join(' ')}`, 'err');
      const body: { origin: string; destination: string; payload_kb?: number; note?: string } = { origin, destination };
      if (kb !== undefined) { if (!/^\d+$/.test(kb)) return c.print(`dispatch: payload must be a number of kB, not "${kb}"`, 'err'); body.payload_kb = Number(kb); }
      if (note.length) body.note = note.join(' ');
      try {
        const f = await api.dispatch(body);
        c.print(`${f.callsign} boarding at ${f.origin} for ${f.destination}, ${f.payload_kb} kB — id ${f.id}`, 'ok');
        live.refreshFlights();
      } catch (e) { c.print(errLine(e), 'err'); }
    } },
  { name: 'theme', usage: 'theme [vga|green|amber]', help: 'room lighting; no argument cycles',
    run: (a, c) => {
      const cur = document.documentElement.dataset.theme ?? 'vga';
      let next = a[0] ?? THEMES[(THEMES.indexOf(cur) + 1) % THEMES.length];
      if (!THEMES.includes(next)) return c.print(`theme: ${next}? try ${THEMES.join(', ')}`, 'err');
      setTheme(next); c.print(`theme ${next}`, 'ok');
    } },
  { name: 'q', usage: 'q', help: 'leave', run: (_a, c) => c.print('E37: No write since last change (add ! to override)', 'err') },
  { name: 'q!', usage: 'q!', help: 'really leave', run: (_a, c) => c.close() },
];

export function findCommand(name: string) { return commands.find((c) => c.name === name); }
export function complete(prefix: string): string[] { return commands.map((c) => c.name).filter((n) => n.startsWith(prefix) && n !== prefix); }
