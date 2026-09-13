// srcs/requirements/bonus/api/app/server.js
//
// node:http, a routing table of regexes, no framework.
//
// Cache-Control, per endpoint, and why:
//   GET  /healthz          no-store                    a liveness answer must never be replayed
//   GET  /flights          public, max-age=5           the list changes on every POST; 5 s hides
//                                                      a burst of identical polls, not a new row
//   GET  /flights/:id      public, max-age=30          a flight only changes status on the minute
//   POST /flights          no-store                    a write receipt is for one caller once
//   GET  /stats            no-store                    it is the live signal; replaying it would
//                                                      freeze the machine room
//   GET  /guestbook        no-store                    a visitor must see their own post at once
//   GET  /traffic          no-store                    a live event stream (SSE), see traffic.js
//   POST /guestbook        no-store                    write receipt
//   errors                 no-store                    a cached 429/422 would lie after the fix
// Redis TTLs are a separate concern (see cache.js): they bound how stale the
// *server* may be; these bound how stale a *client* may be.
import http from 'node:http';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { config } from './config.js';
import { log } from './log.js';
import * as db from './db.js';
import { redis, cached, invalidate, rateLimit, keys, TTL } from './cache.js';
import * as stats from './stats.js';
import * as traffic from './traffic.js';

const { counters } = stats;
const here = dirname(fileURLToPath(import.meta.url));

const CABINETS = ['nginx', 'wordpress', 'mariadb', 'redis', 'web', 'api'];

const CC = {
  never: 'no-store',
  list: 'public, max-age=5, must-revalidate',
  one: 'public, max-age=30, must-revalidate',
};

let shutting = false;
let inflight = 0;

// ── response helpers ────────────────────────────────────────────────────────

function send(res, status, body, cacheControl, extra = {}) {
  const buf = Buffer.from(JSON.stringify(body));
  const headers = {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': buf.length,
    'Cache-Control': cacheControl,
    'X-Content-Type-Options': 'nosniff',
    ...extra,
  };
  if (shutting) headers.Connection = 'close';
  // headers given to writeHead are not readable back with getHeader: keep the
  // cache verdict where the request log and the traffic view can see it
  res.cacheVerdict = extra['X-Cache'];
  res.writeHead(status, headers);
  res.end(buf);
}

// One error shape, always. `field` names the offending input when there is one.
function fail(res, status, code, message, field, extra = {}) {
  send(res, status, { error: { code, message, ...(field ? { field } : {}) } }, CC.never, extra);
}

function clientIp(req) {
  // Only nginx can reach this socket; it sets X-Real-IP from the TLS client.
  const h = req.headers['x-real-ip'];
  return (typeof h === 'string' && h) || req.socket.remoteAddress || 'unknown';
}

// ── input ───────────────────────────────────────────────────────────────────

const BODY_LIMIT = 16 * 1024;

function readJson(req) {
  return new Promise((resolve) => {
    const type = String(req.headers['content-type'] || '');
    if (!type.toLowerCase().startsWith('application/json')) {
      resolve({ error: [415, 'unsupported_media_type', 'send application/json'] });
      req.resume();
      return;
    }
    const chunks = [];
    let size = 0;
    req.on('data', (c) => {
      size += c.length;
      if (size > BODY_LIMIT) {
        resolve({ error: [413, 'payload_too_large', `body over ${BODY_LIMIT} bytes`] });
        req.destroy();
        return;
      }
      chunks.push(c);
    });
    req.on('end', () => {
      try {
        resolve({ value: JSON.parse(Buffer.concat(chunks).toString('utf8') || 'null') });
      } catch {
        resolve({ error: [400, 'bad_json', 'body is not valid JSON'] });
      }
    });
    req.on('error', () => resolve({ error: [400, 'bad_request', 'body could not be read'] }));
  });
}

// Allowlist validation. Unknown fields are refused with the field named and the
// accepted set listed; each rule says what it expected.
function validate(body, schema) {
  const err = (code, message, field) => ({ error: { code, message, field } });
  if (body === null || typeof body !== 'object' || Array.isArray(body)) {
    return err('bad_body', 'expected a JSON object');
  }
  const allowed = Object.keys(schema);
  for (const k of Object.keys(body)) {
    if (!allowed.includes(k)) return err('unknown_field', `unknown field; expected one of: ${allowed.join(', ')}`, k);
  }
  const out = {};
  for (const [k, rule] of Object.entries(schema)) {
    const v = body[k];
    if (v === undefined) {
      if (rule.required) return err('missing_field', `${k} is required: ${rule.desc}`, k);
      if ('default' in rule) out[k] = rule.default;
      continue;
    }
    if (rule.type === 'string') {
      if (typeof v !== 'string') return err('invalid_type', `expected a string: ${rule.desc}`, k);
      const s = v.trim();
      if (s.length < rule.min || s.length > rule.max) {
        return err('invalid_length', `expected ${rule.min}–${rule.max} characters, got ${s.length}`, k);
      }
      if (rule.enum && !rule.enum.includes(s)) return err('invalid_value', `expected one of: ${rule.enum.join(', ')}`, k);
      if (rule.pattern && !rule.pattern.test(s)) return err('invalid_value', rule.desc, k);
      out[k] = s;
    } else if (rule.type === 'int') {
      if (!Number.isInteger(v) || v < rule.min || v > rule.max) {
        return err('invalid_value', `expected an integer between ${rule.min} and ${rule.max}`, k);
      }
      out[k] = v;
    }
  }
  return { value: out };
}

const PRINTABLE = /^[^\p{Cc}]*$/u;

const FLIGHT_SCHEMA = {
  origin: { type: 'string', required: true, min: 1, max: 16, enum: CABINETS, desc: 'a cabinet name' },
  destination: { type: 'string', required: true, min: 1, max: 16, enum: CABINETS, desc: 'a cabinet name' },
  payload_kb: { type: 'int', min: 1, max: 65536, default: 1, desc: 'payload size in KB' },
  note: { type: 'string', min: 0, max: 140, default: '', pattern: PRINTABLE, desc: 'printable text, no control characters' },
};

const GUESTBOOK_SCHEMA = {
  handle: { type: 'string', required: true, min: 2, max: 24, pattern: /^[A-Za-z0-9_.\- ]+$/, desc: 'letters, digits, space, _ . -' },
  message: { type: 'string', required: true, min: 1, max: 280, pattern: PRINTABLE, desc: 'printable text, no control characters' },
};

// ── handlers ────────────────────────────────────────────────────────────────

async function index(req, res) {
  send(res, 200, {
    name: 'inception-lab-api',
    version: config.version,
    endpoints: routes.map((r) => `${r.m} ${r.path}`),
  }, CC.never);
}

async function probe(fn) {
  const t0 = process.hrtime.bigint();
  const ms = () => Math.round(Number(process.hrtime.bigint() - t0) / 1e4) / 100;
  try {
    await Promise.race([fn(), new Promise((_, rej) => { setTimeout(() => rej(new Error('ETIMEDOUT')), 1500); })]);
    return { ok: true, latency_ms: ms() };
  } catch (e) {
    return { ok: false, latency_ms: ms(), error: e.code || e.message || 'unreachable' };
  }
}

async function healthz(req, res) {
  const [mariadb, rd] = await Promise.all([probe(() => db.ping()), probe(() => redis.cmd('PING'))]);
  const ok = mariadb.ok && rd.ok && !shutting;
  send(res, ok ? 200 : 503, {
    ok, mariadb, redis: rd, uptime_s: Math.floor(process.uptime()), draining: shutting,
  }, CC.never);
}

const FLIGHT_COLUMNS = 'id, callsign, origin, destination, status, payload_kb, note, created_at';

async function listFlights(req, res) {
  const { value, hit } = await cached(keys.flightsAll, TTL.flightsAll, () => db.execute(
    `SELECT ${FLIGHT_COLUMNS} FROM flights ORDER BY id DESC LIMIT 100`,
  ));
  counters.incr(hit ? 'cache_hit' : 'cache_miss');
  send(res, 200, { flights: value, count: value.length, cached: hit }, CC.list, { 'X-Cache': hit ? 'HIT' : 'MISS' });
}

async function getFlight(req, res, [id]) {
  const { value, hit } = await cached(keys.flight(id), TTL.flight, async () => {
    const rows = await db.execute(`SELECT ${FLIGHT_COLUMNS} FROM flights WHERE id = ?`, [id]);
    return rows[0] ?? null;
  });
  counters.incr(hit ? 'cache_hit' : 'cache_miss');
  if (!value) return fail(res, 404, 'not_found', `no flight with id ${id}`);
  return send(res, 200, { flight: value, cached: hit }, CC.one, { 'X-Cache': hit ? 'HIT' : 'MISS' });
}

function callsign() {
  return `PKT-${Math.floor(Math.random() * 0xffff).toString(16).toUpperCase().padStart(4, '0')}`;
}

async function createFlight(req, res) {
  const rl = await rateLimit('flights', clientIp(req));
  if (rl.limited) {
    counters.incr('rate_limited');
    return fail(res, 429, 'rate_limited', `${rl.limit} flights per ${rl.windowS} s per address; retry in ${rl.retryAfter} s`, undefined, { 'Retry-After': rl.retryAfter });
  }
  const body = await readJson(req);
  if (body.error) return fail(res, ...body.error);
  const v = validate(body.value, FLIGHT_SCHEMA);
  if (v.error) return fail(res, 422, v.error.code, v.error.message, v.error.field);
  const f = v.value;
  if (f.origin === f.destination) return fail(res, 422, 'invalid_value', 'destination must differ from origin', 'destination');
  // A flight to redis while redis is down is diverted at the gate — a real
  // status from a real probe, not a random one.
  const status = f.destination === 'redis' && !redis.connected ? 'diverted' : 'boarding';

  let id = null;
  for (let attempt = 0; attempt < 5 && id === null; attempt += 1) {
    try {
      const r = await db.execute(
        'INSERT INTO flights (callsign, origin, destination, status, payload_kb, note) VALUES (?, ?, ?, ?, ?, ?)',
        [callsign(), f.origin, f.destination, status, f.payload_kb, f.note],
      );
      id = r.insertId;
    } catch (e) {
      if (e.code !== 'ER_DUP_ENTRY') throw e;
    }
  }
  if (id === null) return fail(res, 503, 'try_again', 'could not allocate a callsign');
  // Exactly the two keys that can now be stale: the list, and this id (a
  // stale 404 could have been cached only if null results were cached; they
  // are not, so the DEL is a documented no-op on a fresh id).
  await invalidate(keys.flightsAll, keys.flight(id), keys.statsTables);
  counters.incr('flight_created');
  const rows = await db.execute(`SELECT ${FLIGHT_COLUMNS} FROM flights WHERE id = ?`, [id]);
  return send(res, 201, { flight: rows[0] }, CC.never, { Location: `/api/v1/flights/${id}` });
}

async function getStats(req, res) {
  send(res, 200, await stats.snapshot(), CC.never);
}

// The wires in the machine room: Server-Sent Events, one frame per 200 ms.
// A stream is not "in flight" for the drain on SIGTERM; closeAll ends it.
async function trafficStream(req, res) {
  const ip = clientIp(req);
  const refused = traffic.admit(ip);
  if (refused) return fail(res, refused.status, refused.code, refused.message, undefined, { 'Retry-After': refused.retryAfter });
  if (req.method === 'HEAD' || shutting) {
    return send(res, shutting ? 503 : 200, { stream: 'text/event-stream', open: traffic.watchers() }, CC.never);
  }
  res.stream = true;
  inflight -= 1;
  stats.setInflight(inflight);
  traffic.attach(req, res, ip);
  traffic.request('ok', null);
}

async function listGuestbook(req, res) {
  const { value, hit } = await cached(keys.guestbookRecent, TTL.guestbookRecent, () => db.execute(
    'SELECT id, handle, message, created_at FROM guestbook ORDER BY id DESC LIMIT 50',
  ));
  counters.incr(hit ? 'cache_hit' : 'cache_miss');
  send(res, 200, { entries: value, count: value.length, cached: hit }, CC.never, { 'X-Cache': hit ? 'HIT' : 'MISS' });
}

async function createGuestbook(req, res) {
  const rl = await rateLimit('guestbook', clientIp(req));
  if (rl.limited) {
    counters.incr('rate_limited');
    return fail(res, 429, 'rate_limited', `${rl.limit} posts per ${rl.windowS} s per address; retry in ${rl.retryAfter} s`, undefined, { 'Retry-After': rl.retryAfter });
  }
  const body = await readJson(req);
  if (body.error) return fail(res, ...body.error);
  const v = validate(body.value, GUESTBOOK_SCHEMA);
  if (v.error) return fail(res, 422, v.error.code, v.error.message, v.error.field);
  const r = await db.execute('INSERT INTO guestbook (handle, message) VALUES (?, ?)', [v.value.handle, v.value.message]);
  await invalidate(keys.guestbookRecent, keys.statsTables);
  counters.incr('guestbook_post');
  const rows = await db.execute('SELECT id, handle, message, created_at FROM guestbook WHERE id = ?', [r.insertId]);
  return send(res, 201, { entry: rows[0] }, CC.never);
}

// ── routing ─────────────────────────────────────────────────────────────────

const routes = [
  { m: 'GET', path: '/api/v1/', re: /^\/api\/v1\/?$/, h: index },
  { m: 'GET', path: '/api/v1/healthz', re: /^\/api\/v1\/healthz\/?$/, h: healthz },
  { m: 'GET', path: '/api/v1/flights', re: /^\/api\/v1\/flights\/?$/, h: listFlights },
  { m: 'POST', path: '/api/v1/flights', re: /^\/api\/v1\/flights\/?$/, h: createFlight },
  { m: 'GET', path: '/api/v1/flights/:id', re: /^\/api\/v1\/flights\/(\d{1,9})\/?$/, h: getFlight },
  { m: 'GET', path: '/api/v1/stats', re: /^\/api\/v1\/stats\/?$/, h: getStats },
  { m: 'GET', path: '/api/v1/guestbook', re: /^\/api\/v1\/guestbook\/?$/, h: listGuestbook },
  { m: 'GET', path: '/api/v1/traffic', re: /^\/api\/v1\/traffic\/?$/, h: trafficStream },
  { m: 'POST', path: '/api/v1/guestbook', re: /^\/api\/v1\/guestbook\/?$/, h: createGuestbook },
];

async function dispatch(req, res) {
  const url = new URL(req.url, 'http://api');
  const path = url.pathname;
  let allowed = [];
  for (const r of routes) {
    const m = path.match(r.re);
    if (!m) continue;
    if (r.m === req.method || (req.method === 'HEAD' && r.m === 'GET')) return r.h(req, res, m.slice(1));
    allowed.push(r.m);
  }
  if (allowed.length) {
    allowed = [...new Set(allowed)];
    return fail(res, 405, 'method_not_allowed', `${req.method} is not allowed here; try ${allowed.join(', ')}`, undefined, { Allow: allowed.join(', ') });
  }
  return fail(res, 404, 'not_found', `no route for ${req.method} ${path}`);
}

const server = http.createServer({ keepAliveTimeout: 5000 }, (req, res) => {
  const t0 = process.hrtime.bigint();
  inflight += 1;
  stats.setInflight(inflight);
  counters.incr('http_requests');
  res.on('finish', () => {
    const ms = Math.round(Number(process.hrtime.bigint() - t0) / 1e4) / 100;
    if (!res.stream) {
      inflight -= 1;
      stats.setInflight(inflight);
      const xc = res.cacheVerdict;
      traffic.request(res.statusCode >= 400 ? 'err' : xc === 'HIT' ? 'hit' : xc === 'MISS' ? 'miss' : 'ok', ms);
    }
    if (res.statusCode >= 500) counters.incr('http_errors');
    log('info', 'request', {
      method: req.method,
      path: req.url,
      status: res.statusCode,
      ms,
      ip: clientIp(req),
      cache: res.cacheVerdict,
    });
  });
  res.on('close', () => {
    if (!res.writableFinished && !res.stream) {
      inflight -= 1;
      stats.setInflight(inflight);
    }
  });
  dispatch(req, res).catch((e) => {
    // The client gets the shape and a code; the stack and any SQL stay in the log.
    log('error', 'unhandled', { method: req.method, path: req.url, error: e.message, code: e.code, stack: e.stack });
    if (!res.headersSent) fail(res, 500, 'internal', 'internal error');
    else res.destroy();
  });
});

// ── lifecycle ───────────────────────────────────────────────────────────────

// The container starts as root so that /run/secrets (mode 0400, owned by root)
// is readable. config.js has read the secret by now; drop to the 'api' user
// before a single socket is opened.
function dropPrivileges() {
  if (typeof process.getuid !== 'function' || process.getuid() !== 0) return;
  try {
    process.initgroups(config.runAs, config.runAs);
    process.setgid(config.runAs);
    process.setuid(config.runAs);
    log('info', 'privileges dropped', { user: config.runAs, uid: process.getuid(), gid: process.getgid() });
  } catch (e) {
    log('error', 'cannot drop privileges', { error: e.message });
    process.exit(1);
  }
}

const sleep = (ms) => new Promise((r) => { setTimeout(r, ms); });

// SIGTERM: stop accepting, let in-flight requests finish (bounded), flush the
// counters, close both backends, exit 0. Docker's default grace is 10 s; ours
// is config.drainTimeoutMs, kept just under it.
async function shutdown(signal) {
  if (shutting) return;
  shutting = true;
  log('info', 'shutdown: stop accepting', { signal, inflight, streams: traffic.watchers() });
  traffic.closeAll();
  server.close(() => log('info', 'shutdown: listener closed'));
  server.closeIdleConnections();
  const deadline = Date.now() + config.drainTimeoutMs;
  while (inflight > 0 && Date.now() < deadline) await sleep(50);
  if (inflight > 0) {
    log('warn', 'shutdown: drain timeout, closing remaining connections', { inflight });
    server.closeAllConnections();
  }
  stats.stop();
  await stats.flush();
  await Promise.allSettled([db.close(), redis.quit()]);
  log('info', 'shutdown: complete', { drained: inflight === 0 });
  process.exit(0);
}

process.on('SIGTERM', () => { shutdown('SIGTERM'); });
process.on('SIGINT', () => { shutdown('SIGINT'); });
process.on('unhandledRejection', (e) => {
  log('error', 'unhandled rejection', { error: e?.message || String(e), stack: e?.stack });
});

async function main() {
  dropPrivileges();
  await db.waitReady();
  await db.migrate(readFileSync(join(here, 'schema.sql'), 'utf8'));
  redis.connect();
  stats.start();
  await new Promise((resolve) => { server.listen(config.port, '0.0.0.0', resolve); });
  log('info', 'listening', { port: config.port, pid: process.pid, node: process.version });
}

main().catch((e) => {
  log('error', 'fatal at startup', { error: e.message, code: e.code });
  process.exit(1);
});
