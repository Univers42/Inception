// srcs/requirements/bonus/web/app/src/lib/traffic.ts
// The wires stream: GET /api/v1/traffic, Server-Sent Events, one frame every
// 200 ms. One EventSource for the page, open only while something holds a
// lease on it (the machine room while it is on screen, :wires for a moment),
// because the API records and samples only while someone is connected.
//
// Per wire it keeps what the labels need: requests per second over the last
// second, the latest median latency, and how many requests one dot stands for.
// Touches no DOM at load: the palette's commands import it at build time.
import { WIRES, type Outcome } from './wires';

export interface LinkFrame {
  n?: number; k?: Partial<Record<Outcome, number>>; dt?: number;
  e?: number[]; p50?: number; sampled?: boolean; err?: string;
}
export interface TrafficFrame { t: number; links: Record<string, LinkFrame | undefined> }
export type StreamState = 'off' | 'connecting' | 'live' | 'down';
export type TrafficEvent =
  | { type: 'frame'; frame: TrafficFrame; at: number }
  | { type: 'state'; state: StreamState };

export interface WireState {
  rate: number;              // requests per second
  p50: number | null;        // ms, seen wires only
  per: number;               // requests per dot
  err?: string;              // the last sample of a sampled wire failed
  history: { at: number; n: number }[];
  sampleAt: number;          // when a sampled wire last reported
  p50At: number;
}

// A dot crosses its wire in CROSS_MS whatever the wire's length; that is the
// only thing slowed down for the eye. Past MAX_ON_WIRE dots on one wire at
// once, a dot stands for several requests, in 1-2-5 steps.
export const CROSS_MS = 500;
const MAX_ON_WIRE = 60;
const STEPS = [1, 2, 5, 10, 20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000, 50000];
const STALE_MS = 3000;

type Listener = (ev: TrafficEvent) => void;
const listeners = new Set<Listener>();
let es: EventSource | undefined;
let leases = 0;
let retryTimer: ReturnType<typeof setTimeout> | undefined;
let tickTimer: ReturnType<typeof setInterval> | undefined;
let lastFrameAt = 0;

const fresh = (): WireState => ({ rate: 0, p50: null, per: 1, history: [], sampleAt: 0, p50At: 0 });

export const traffic = {
  state: 'off' as StreamState,
  wires: Object.fromEntries(WIRES.map((w) => [w.id, fresh()])) as Record<string, WireState>,
  on(l: Listener) { listeners.add(l); return () => { listeners.delete(l); }; },
  // → release(); the stream closes when the last lease is released
  acquire() {
    leases++;
    if (leases === 1) connect();
    let released = false;
    return () => { if (released) return; released = true; if (--leases === 0) disconnect(); };
  },
};

function emit(ev: TrafficEvent) { for (const l of listeners) { try { l(ev); } catch (e) { console.error(e); } } }
function setState(s: StreamState) { if (traffic.state !== s) { traffic.state = s; emit({ type: 'state', state: s }); } }

function connect() {
  clearTimeout(retryTimer);
  setState('connecting');
  const source = new EventSource('/api/v1/traffic');
  es = source;
  source.addEventListener('open', () => { lastFrameAt = performance.now(); setState('live'); });
  source.addEventListener('traffic', (ev) => {
    lastFrameAt = performance.now();
    if (traffic.state !== 'live') setState('live');
    try { onFrame(JSON.parse((ev as MessageEvent).data), lastFrameAt); } catch (e) { console.error(e); }
  });
  // the API is shutting down: it ends the stream, and EventSource reconnects by itself
  source.addEventListener('bye', () => setState('connecting'));
  source.addEventListener('error', () => {
    if (es !== source) return;
    if (source.readyState === EventSource.CLOSED) {
      // refused (429/503) or not an event stream: EventSource gives up, so do it by hand
      es = undefined;
      setState('down');
      retryTimer = setTimeout(() => { if (leases > 0 && !es) connect(); }, 10000);
    } else setState('connecting');
  });
  tickTimer ??= setInterval(tick, 1000);
}

function disconnect() {
  clearTimeout(retryTimer);
  clearInterval(tickTimer); tickTimer = undefined;
  es?.close(); es = undefined;
  for (const w of WIRES) traffic.wires[w.id] = fresh();
  setState('off');
}

// Once a second: let rates decay when frames stop saying anything, and
// replace a stream that went quiet (the API sends at least one frame a second).
function tick() {
  const now = performance.now();
  for (const w of WIRES) { rate(w.id, now); per(traffic.wires[w.id]); }
  if (es && traffic.state === 'live' && now - lastFrameAt > 4000) {
    es.close(); es = undefined;
    setState('down');
    connect();
  }
}

function rate(id: string, now: number) {
  const s = traffic.wires[id];
  const wire = WIRES.find((w) => w.id === id)!;
  if (wire.sampled) {
    if (now - s.sampleAt > STALE_MS) s.rate = 0;
  } else {
    while (s.history.length && now - s.history[0].at > 1000) s.history.shift();
    s.rate = s.history.reduce((a, h) => a + h.n, 0);
    if (now - s.p50At > STALE_MS) s.p50 = null;
  }
}

function per(s: WireState) {
  const onWire = (p: number) => (s.rate * CROSS_MS) / 1000 / p;
  let i = STEPS.indexOf(s.per);
  while (onWire(STEPS[i]) > MAX_ON_WIRE && i < STEPS.length - 1) i++;
  // step down only well below the limit, so the scale does not flap
  while (i > 0 && onWire(STEPS[i - 1]) <= MAX_ON_WIRE / 2) i--;
  s.per = STEPS[i];
}

function onFrame(frame: TrafficFrame, at: number) {
  for (const w of WIRES) {
    const lf = frame.links[w.id];
    if (!lf) continue;
    const s = traffic.wires[w.id];
    if (lf.err) { s.err = lf.err; s.sampleAt = at; s.rate = 0; continue; }
    s.err = undefined;
    if (w.sampled) { s.sampleAt = at; s.rate = lf.dt ? ((lf.n ?? 0) * 1000) / lf.dt : 0; }
    else {
      s.history.push({ at, n: lf.n ?? 0 });
      if (lf.p50 !== undefined) { s.p50 = lf.p50; s.p50At = at; }
      rate(w.id, at);
    }
    per(s);
  }
  emit({ type: 'frame', frame, at });
}
