// srcs/requirements/bonus/api/app/traffic.js
//
// The wires in the machine room: six links, known in two different ways.
//
//   seen      nginx → api, api → redis, api → mariadb
//             The API is one end of each, so every request, command and
//             statement is recorded as it completes, with its outcome and
//             latency.
//   sampled   nginx → wordpress, wordpress → redis, wordpress → mariadb
//             The API is neither end. Once a second it reads a server-side
//             counter and takes away its own share:
//               php-fpm  accepted conn (FastCGI status)    − our status reads
//               redis    INFO total_commands_processed     − our commands
//               mariadb  SHOW GLOBAL STATUS 'Questions'    − our statements
//             That gives a count per second, not individual requests. It is
//             "every other client": WordPress, and the few healthcheck probes
//             the containers run on themselves.
//             (Redis MONITOR would show every command, but it slows Redis down
//             more than the traffic it is watching.)
//
// Delivery: Server-Sent Events on GET /api/v1/traffic. Every frameMs one frame
// carries everything recorded since the previous one. One message per request
// would cost more than the requests themselves at thousands per second.
// Nothing is recorded and nothing is sampled while no one is connected.
//
// Frame (event: traffic), links present only when they have something to say:
//   { "t": <epoch ms>,
//     "links": { "nginx>api": { "n": 12, "k": { "hit": 8, "miss": 3, "err": 1 },
//                               "dt": 200, "e": [ … ], "p50": 0.61 },
//                "wordpress>redis": { "n": 40, "k": { … }, "dt": 1003, "sampled": true },
//                "nginx>wordpress": { "err": "ECONNREFUSED" } } }
//   n    requests / commands / statements in the window
//   k    n split by outcome: ok, hit, miss, slow, err
//   dt   the window, in ms
//   e    only when n ≤ 48: each event as (ms since the window opened) × 8 + outcome
//        index, so a client can replay a burst with its real spacing
//   p50  median latency in ms over the last second (seen links only)
import { log } from './log.js';
import { config } from './config.js';
import * as db from './db.js';
import * as fpm from './fpm.js';
import { redis, loading } from './cache.js';

export const OUTCOMES = ['ok', 'hit', 'miss', 'slow', 'err'];
const IDX = Object.fromEntries(OUTCOMES.map((o, i) => [o, i]));
const EVENTS_MAX = 48;
const LAT_KEEP = 256;          // latency samples kept per link (the most recent)
const LAT_WINDOW_MS = 1000;

export const WIRES = [
  { id: 'nginx>api', from: 'nginx', to: 'api', measured: 'every request, by the API' },
  { id: 'api>redis', from: 'api', to: 'redis', measured: 'every command, by the API' },
  { id: 'api>mariadb', from: 'api', to: 'mariadb', measured: 'every statement, by the API' },
  { id: 'nginx>wordpress', from: 'nginx', to: 'wordpress', measured: 'php-fpm accepted conn, each second' },
  { id: 'wordpress>redis', from: 'wordpress', to: 'redis', measured: 'redis INFO, each second, minus the API' },
  { id: 'wordpress>mariadb', from: 'wordpress', to: 'mariadb', measured: 'mariadb Questions, each second, minus the API' },
];

class Seen {
  n = 0;
  k = [0, 0, 0, 0, 0];
  e = [];
  lat = new Float64Array(LAT_KEEP);
  latAt = new Float64Array(LAT_KEEP);
  latLen = 0;
  latNext = 0;

  add(outcome, ms, now) {
    const i = IDX[outcome];
    this.n += 1;
    this.k[i] += 1;
    if (this.e.length < EVENTS_MAX) this.e.push((Math.max(0, Math.round(now - frameStart)) << 3) | i);
    if (ms !== null) {
      this.lat[this.latNext] = ms;
      this.latAt[this.latNext] = now;
      this.latNext = (this.latNext + 1) % LAT_KEEP;
      if (this.latLen < LAT_KEEP) this.latLen += 1;
    }
  }

  take(now, dt) {
    if (!this.n) return null;
    const out = { n: this.n, k: counts(this.k), dt: Math.round(dt) };
    if (this.n <= EVENTS_MAX) out.e = this.e;
    const recent = [];
    for (let i = 0; i < this.latLen; i += 1) if (now - this.latAt[i] <= LAT_WINDOW_MS) recent.push(this.lat[i]);
    if (recent.length) {
      recent.sort((a, b) => a - b);
      out.p50 = Math.round(recent[recent.length >> 1] * 100) / 100;
    }
    this.n = 0;
    this.k = [0, 0, 0, 0, 0];
    this.e = [];
    return out;
  }

  // a new watcher starts from an empty ring: take() reads slots 0..latLen-1,
  // so the write position must start over with the length
  clear() {
    this.n = 0;
    this.k = [0, 0, 0, 0, 0];
    this.e = [];
    this.latLen = 0;
    this.latNext = 0;
  }
}

function counts(k) {
  const o = {};
  k.forEach((v, i) => { if (v) o[OUTCOMES[i]] = v; });
  return o;
}

const seen = { 'nginx>api': new Seen(), 'api>redis': new Seen(), 'api>mariadb': new Seen() };
const clients = new Set();
let active = false;
let frameStart = performance.now();
let lastSentAt = 0;
let frameTimer = null;
let sampleTimer = null;
let sampled = {};

// ── recording (cheap, and a no-op while no one watches) ────────────────────

// nginx → api: called when a response finishes. ms is null for a stream.
export function request(outcome, ms) {
  if (active) seen['nginx>api'].add(outcome, ms, performance.now());
}

redis.onCommand = (outcome, ms) => {
  if (active) seen['api>redis'].add(outcome, ms, performance.now());
};

db.hooks.onStatement = (ms, failed) => {
  if (!active) return;
  let outcome = 'ok';
  if (failed) outcome = 'err';
  else if (ms > config.db.slowQueryMs) outcome = 'slow';
  else if (loading.getStore() !== undefined) outcome = 'miss';
  seen['api>mariadb'].add(outcome, ms, performance.now());
};

// ── sampling the wires the API is not an end of ─────────────────────────────

// A counter read once a second, minus our own share. A difference can come
// out negative for one sample (our statement counted before the server's, on
// another pool connection); it is carried into the next one instead of being
// clamped away, so nothing phantom appears and nothing is lost.
class Delta {
  prev = null;
  carry = 0;

  // → the increase since the last reading, or null on the first one
  next(total, ownTotal, at) {
    const p = this.prev;
    this.prev = { total, ownTotal, at };
    if (!p || total < p.total) { this.carry = 0; return null; }   // first read, or the server restarted
    let d = total - p.total - (ownTotal - p.ownTotal) + this.carry;
    this.carry = 0;
    if (d < 0) { this.carry = Math.max(d, -16); d = 0; }
    return { d, dt: Math.round(at - p.at) };
  }
}

const deltas = { fpm: new Delta(), fpmHalf: 0, cmds: new Delta(), hits: new Delta(), misses: new Delta(), sql: new Delta() };
let fpmReads = 0;
let sampling = false;

const errCode = (e) => e?.code || e?.message || 'unreachable';

async function sampleFpm() {
  const s = await fpm.status({ host: config.fpm.host, port: config.fpm.port, timeoutMs: 800 });
  fpmReads += 1;   // php-fpm counted this read before it answered, so it is in s
  const r = deltas.fpm.next(Number(s['accepted conn']), fpmReads, performance.now());
  if (!r) return;
  const per = config.fpm.countsPerRequest;
  const total = r.d + deltas.fpmHalf;
  const n = Math.floor(total / per);
  deltas.fpmHalf = total - n * per;
  sampled['nginx>wordpress'] = { n, k: n ? { ok: n } : {}, dt: r.dt, sampled: true };
}

async function sampleRedis() {
  const { value, own } = await redis.info('stats');
  const at = performance.now();
  const field = (name) => Number((value.match(new RegExp(`^${name}:(\\d+)`, 'm')) || [])[1]);
  const cmds = deltas.cmds.next(field('total_commands_processed'), own.replies, at);
  const hits = deltas.hits.next(field('keyspace_hits'), own.hits, at);
  const misses = deltas.misses.next(field('keyspace_misses'), own.misses, at);
  if (!cmds || !hits || !misses) return;
  const n = cmds.d;
  const hit = Math.min(hits.d, n);
  const miss = Math.min(misses.d, n - hit);
  sampled['wordpress>redis'] = { n, k: counts([n - hit - miss, hit, miss, 0, 0]), dt: cmds.dt, sampled: true };
}

async function sampleSql() {
  const rows = await db.query("SHOW GLOBAL STATUS LIKE 'Questions'", [], { internal: true });
  // own.statements already includes this SHOW; so does Questions
  const r = deltas.sql.next(Number(rows[0]?.Value), db.own.statements, performance.now());
  if (r) sampled['wordpress>mariadb'] = { n: r.d, k: r.d ? { ok: r.d } : {}, dt: r.dt, sampled: true };
}

async function sample() {
  if (sampling) return;   // a slow backend never stacks samples
  sampling = true;
  const probes = [['nginx>wordpress', sampleFpm], ['wordpress>redis', sampleRedis], ['wordpress>mariadb', sampleSql]];
  await Promise.all(probes.map(([id, fn]) => fn().catch((e) => { sampled[id] = { err: errCode(e) }; })));
  sampling = false;
}

// ── delivery ────────────────────────────────────────────────────────────────

function frame() {
  const now = performance.now();
  const dt = now - frameStart;
  const links = {};
  for (const [id, s] of Object.entries(seen)) {
    const f = s.take(now, dt);
    if (f) links[id] = f;
  }
  Object.assign(links, sampled);
  sampled = {};
  frameStart = now;
  // an idle stream still sends one frame a second, so a client can tell
  // "nothing happened" from "the stream is gone"
  if (!Object.keys(links).length && now - lastSentAt < 1000) return;
  lastSentAt = now;
  const msg = `event: traffic\ndata: ${JSON.stringify({ t: Date.now(), links })}\n\n`;
  for (const c of clients) {
    // a client that cannot keep up loses frames; it never makes us buffer
    if (c.res.writableNeedDrain) { c.dropped += 1; continue; }
    c.res.write(msg);
  }
}

function activate() {
  if (active) return;
  active = true;
  frameStart = performance.now();
  frameTimer = setInterval(frame, config.traffic.frameMs);
  sampleTimer = setInterval(sample, config.traffic.sampleMs);
  sample();   // the first reading is only a baseline
  log('info', 'traffic: first watcher, recording');
}

function deactivate() {
  if (!active) return;
  active = false;
  clearInterval(frameTimer);
  clearInterval(sampleTimer);
  for (const s of Object.values(seen)) s.clear();
  for (const d of [deltas.fpm, deltas.cmds, deltas.hits, deltas.misses, deltas.sql]) { d.prev = null; d.carry = 0; }
  deltas.fpmHalf = 0;
  sampled = {};
  log('info', 'traffic: no watchers, stopped');
}

// → null when a new stream from `ip` may open, else the refusal to send
export function admit(ip) {
  if (clients.size >= config.traffic.maxClients) {
    return { status: 503, code: 'too_many_streams', message: `${config.traffic.maxClients} traffic streams are already open`, retryAfter: 30 };
  }
  let mine = 0;
  for (const c of clients) if (c.ip === ip) mine += 1;
  if (mine >= config.traffic.maxPerAddress) {
    return { status: 429, code: 'too_many_streams', message: `${config.traffic.maxPerAddress} traffic streams per address`, retryAfter: 10 };
  }
  return null;
}

// Takes over the response: headers, a hello event, then frames until the
// client goes away or the server shuts down.
export function attach(req, res, ip) {
  res.writeHead(200, {
    'Content-Type': 'text/event-stream; charset=utf-8',
    'Cache-Control': 'no-store',
    'X-Content-Type-Options': 'nosniff',
    // nginx buffers proxied responses by default; this header turns that off
    // for this response only, so frames leave the edge as they are written
    'X-Accel-Buffering': 'no',
  });
  const hello = { frame_ms: config.traffic.frameMs, sample_ms: config.traffic.sampleMs, outcomes: OUTCOMES, wires: WIRES };
  res.write(`retry: 3000\nevent: hello\ndata: ${JSON.stringify(hello)}\n\n`);
  const client = { res, ip, dropped: 0, since: Date.now() };
  clients.add(client);
  activate();
  res.on('close', () => {
    clients.delete(client);
    log('info', 'traffic: stream closed', { ip, seconds: Math.round((Date.now() - client.since) / 1000), dropped_frames: client.dropped });
    if (!clients.size) deactivate();
  });
}

// SIGTERM: tell every watcher, end every stream. EventSource reconnects on its
// own once the API is back.
export function closeAll() {
  for (const c of clients) {
    c.res.write('event: bye\ndata: {}\n\n');
    c.res.end();
  }
  deactivate();
}

export function watchers() {
  return clients.size;
}
