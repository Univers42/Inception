// srcs/requirements/bonus/web/app/src/lib/live.ts
// One poll loop for the whole page.
//   stats    every 5 s  — what the counters say
//   flights  every 15 s — and at once after a dispatch or a flight_created delta
//   probe    every 30 s — healthz (MariaDB, Redis) + a HEAD to WordPress and to /lab/
// Three failures in a row = offline, retried at 10 → 20 → 40 s. A hidden tab
// does not poll; it catches up the moment it is visible again.
import { api, head, net, ApiError, type Flight, type Stats, type Health } from './api';

export interface ProbeResult { health?: Health; wordpress: number; web: number; at: number }
export type LiveEvent =
  | { type: 'stats'; stats: Stats; delta: Record<string, number>; first: boolean }
  | { type: 'flights'; flights: Flight[]; added: Flight[]; changed: Flight[]; first: boolean }
  | { type: 'probe'; probe: ProbeResult }
  | { type: 'health'; ok: boolean; failures: number; retryInS: number; lastGoodAt: number };

type Listener = (ev: LiveEvent) => void;

const STATS_MS = 5000, FLIGHTS_MS = 15000, PROBE_MS = 30000, BACKOFF = [10000, 20000, 40000];
const listeners = new Set<Listener>();
let timer: ReturnType<typeof setTimeout> | undefined;
let started = false, failures = 0, lastGoodAt = 0, lastFlightsAt = 0, lastProbeAt = 0, lastSent = 0;

export const live = {
  stats: undefined as Stats | undefined,
  flights: undefined as Flight[] | undefined,
  probe: undefined as ProbeResult | undefined,
  ok: undefined as boolean | undefined,
  // server clock minus browser clock, from the last stats document
  skewMs: 0,
  receivedAt: 0,
  pollMs: STATS_MS,
  on(l: Listener) { listeners.add(l); return () => { listeners.delete(l); }; },
  start() { if (started) return; started = true; document.addEventListener('visibilitychange', onVis); schedule(0); },
  refreshFlights() { lastFlightsAt = 0; schedule(0); },
  now() { return Date.now() + live.skewMs; },
  get lastGoodAt() { return lastGoodAt; },
};

function emit(ev: LiveEvent) { for (const l of listeners) { try { l(ev); } catch (e) { console.error(e); } } }
function onVis() { if (document.visibilityState === 'visible') schedule(0); }
function schedule(ms: number) { if (!started) return; if (timer) clearTimeout(timer); timer = setTimeout(tick, ms); }

async function tick() {
  if (document.visibilityState === 'hidden') return;
  try {
    const stats = await api.stats();
    const prev = live.stats;
    const mine = net.sent - lastSent; lastSent = net.sent;
    const delta: Record<string, number> = {};
    for (const k of Object.keys(stats.counters)) delta[k] = prev ? Math.max(0, stats.counters[k] - (prev.counters[k] ?? 0)) : 0;
    delta.foreign_requests = prev ? Math.max(0, delta.http_requests - mine) : 0;
    live.stats = stats; live.receivedAt = Date.now(); live.skewMs = Date.parse(stats.ts) - live.receivedAt;
    failures = 0; lastGoodAt = Date.now();
    if (live.ok !== true) { live.ok = true; emit({ type: 'health', ok: true, failures: 0, retryInS: 0, lastGoodAt }); }
    emit({ type: 'stats', stats, delta, first: !prev });
    if (delta.flight_created) lastFlightsAt = 0;

    if (Date.now() - lastFlightsAt >= FLIGHTS_MS) {
      const flights = await api.flights();
      const before = new Map((live.flights ?? []).map((f) => [f.id, f]));
      const first = !live.flights;
      const added = first ? [] : flights.filter((f) => !before.has(f.id));
      const changed = flights.filter((f) => { const b = before.get(f.id); return b !== undefined && b.status !== f.status; });
      live.flights = flights; lastFlightsAt = Date.now();
      emit({ type: 'flights', flights, added, changed, first });
    }
    if (Date.now() - lastProbeAt >= PROBE_MS) {
      lastProbeAt = Date.now();
      const [health, wordpress, web] = await Promise.all([api.health().catch(() => undefined), head('/'), head('/lab/')]);
      live.probe = { health, wordpress, web, at: Date.now() };
      emit({ type: 'probe', probe: live.probe });
    }
    schedule(STATS_MS);
  } catch (err) {
    failures++;
    const down = failures >= 3 || (err instanceof ApiError && err.status >= 500);
    const wait = failures < 3 ? STATS_MS : BACKOFF[Math.min(failures - 3, BACKOFF.length - 1)];
    if (down && (live.ok !== false || failures >= 3)) {
      live.ok = false;
      emit({ type: 'health', ok: false, failures, retryInS: wait / 1000, lastGoodAt });
    }
    schedule(wait);
  }
}
