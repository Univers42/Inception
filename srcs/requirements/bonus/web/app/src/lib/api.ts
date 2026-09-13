// srcs/requirements/bonus/web/app/src/lib/api.ts
// The only place the browser talks to /api/v1/. Typed, timed out, and every
// non-2xx answer becomes an ApiError carrying the API's own {error:{code,…}}.
// Touches no DOM at load, so pages can import it at build time too.
export const API = '/api/v1';
export const CABINETS = ['nginx', 'wordpress', 'mariadb', 'redis', 'web', 'api'] as const;
export type Cabinet = (typeof CABINETS)[number];
export type FlightStatus = 'boarding' | 'en-route' | 'landed' | 'diverted';
export const STATUSES: FlightStatus[] = ['boarding', 'en-route', 'landed', 'diverted'];

export interface Flight {
  id: number; callsign: string; origin: Cabinet; destination: Cabinet;
  status: FlightStatus; payload_kb: number; note: string | null; created_at: string;
}
export interface Stats {
  ts: string; source: 'redis' | 'mariadb';
  counters: Record<string, number>;
  gauges: { inflight: number; uptime_s: number; started_at: string; rss_mb: number; heap_mb: number;
    redis_connected: boolean; db_pool: { size: number; idle: number; queued: number; limit: number } };
  flights: Record<FlightStatus, number>;
  guestbook_entries: number;
  next_minute_tick_s: number;
}
export interface Probe { ok: boolean; latency_ms?: number; error?: string }
export interface Health { ok: boolean; draining: boolean; uptime_s: number; mariadb: Probe; redis: Probe }
export interface GuestbookEntry { id: number; handle: string; message: string; created_at: string }

export class ApiError extends Error {
  constructor(public status: number, public code: string, message: string,
    public field?: string, public retryAfterS?: number) { super(message); }
}

// How many API requests this page has sent. The stats counter counts every
// request, ours included; the difference is what other clients did.
export const net = { sent: 0 };

async function call<T>(method: string, path: string, body?: unknown, accept: number[] = []): Promise<T> {
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), 4000);
  try {
    net.sent++;
    const res = await fetch(API + path, {
      method, signal: ctl.signal, cache: 'no-store',
      headers: body === undefined ? { accept: 'application/json' }
        : { accept: 'application/json', 'content-type': 'application/json' },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    const text = await res.text();
    let json: any = null;
    try { json = text ? JSON.parse(text) : null; } catch { /* not JSON: handled below */ }
    if (!res.ok && !accept.includes(res.status)) {
      const e = json?.error ?? {};
      const ra = Number(res.headers.get('retry-after') ?? '') || undefined;
      throw new ApiError(res.status, e.code ?? `http_${res.status}`, e.message ?? (res.statusText || 'request failed'), e.field, ra);
    }
    if (json === null) throw new ApiError(res.status, 'bad_response', 'the API did not answer with JSON');
    return json as T;
  } catch (err) {
    if (err instanceof ApiError) throw err;
    const aborted = (err as Error)?.name === 'AbortError';
    throw new ApiError(0, aborted ? 'timeout' : 'network', aborted ? 'no answer in 4 s' : 'network error');
  } finally { clearTimeout(timer); }
}

// A HEAD through the edge to something that is not the API (WordPress, the
// static site). Returns the HTTP status, or 0 when nothing answered.
export async function head(path: string): Promise<number> {
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), 4000);
  try { return (await fetch(path, { method: 'HEAD', cache: 'no-store', signal: ctl.signal })).status; }
  catch { return 0; }
  finally { clearTimeout(timer); }
}

export const api = {
  health: () => call<Health>('GET', '/healthz', undefined, [503]),
  stats: () => call<Stats>('GET', '/stats'),
  flights: () => call<{ flights: Flight[] }>('GET', '/flights').then((r) => r.flights),
  flight: (id: number | string) => call<{ flight: Flight }>('GET', `/flights/${id}`).then((r) => r.flight),
  dispatch: (b: { origin: string; destination: string; payload_kb?: number; note?: string }) =>
    call<{ flight: Flight }>('POST', '/flights', b).then((r) => r.flight),
  guestbook: () => call<{ entries: GuestbookEntry[] }>('GET', '/guestbook').then((r) => r.entries),
  sign: (b: { handle: string; message: string }) =>
    call<{ entry: GuestbookEntry }>('POST', '/guestbook', b).then((r) => r.entry),
};

export const fmt = {
  int: (n: number) => Math.round(n).toLocaleString('en-US'),
  pct: (num: number, den: number) => (den > 0 ? Math.round((100 * num) / den) + '%' : '—'),
  // at most five characters, for the cabinet windows
  compact: (n: number) => n < 1000 ? String(n) : n < 1e4 ? (n / 1e3).toFixed(1) + 'K'
    : n < 1e6 ? Math.floor(n / 1e3) + 'K' : n < 1e7 ? (n / 1e6).toFixed(1) + 'M' : Math.floor(n / 1e6) + 'M',
  clock: (d: Date) => d.toTimeString().slice(0, 5),
  // times are shown in UTC everywhere: the build and the browser agree on them
  utc: (iso: string) => iso.slice(11, 19) + 'Z',
  date: (iso: string) => iso.slice(0, 10),
  mmss: (s: number) => { s = Math.max(0, Math.floor(s)); return String(Math.floor(s / 60)).padStart(2, '0') + ':' + String(s % 60).padStart(2, '0'); },
  uptime: (s: number) => { s = Math.max(0, Math.floor(s)); const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60);
    return h ? `${h}h${String(m).padStart(2, '0')}m` : `${m}m${String(s % 60).padStart(2, '0')}s`; },
  // a text meter: box-drawing blocks, no inline style needed
  bar: (v: number, max: number, cells = 16) => { const n = max > 0 ? Math.min(cells, Math.max(v > 0 ? 1 : 0, Math.round((v / max) * cells))) : 0;
    return '█'.repeat(n) + '░'.repeat(cells - n); },
};
