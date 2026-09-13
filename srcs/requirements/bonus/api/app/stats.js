// srcs/requirements/bonus/api/app/stats.js
//
// Counters that drive the machine room. Redis holds the hot value (INCRBY on
// every event); MariaDB holds the durable one. Every `flushMs` the deltas
// accumulated in this process are added to the MariaDB row, then Redis is
// reconciled upward from MariaDB — so a Redis restart or an LRU eviction can
// only ever make a counter *briefly* lower, never permanently.
//
// Nothing here is invented: every counter is incremented by the handler that
// saw the event, and every gauge is read from the process or the pool.
import { config } from './config.js';
import { log } from './log.js';
import * as db from './db.js';
import { redis, keys, cached, TTL, invalidate } from './cache.js';

export const COUNTERS = [
  'http_requests',   // every request that reached the API (through nginx)
  'http_errors',     // responses with status >= 500
  'cache_hit',       // served from Redis
  'cache_miss',      // loaded from MariaDB and stored
  'db_query',        // request-facing statements
  'db_slow',         // of which slower than config.db.slowQueryMs
  'flight_created',  // POST /flights accepted
  'guestbook_post',  // POST /guestbook accepted
  'rate_limited',    // 429 returned
  'minute_ticks',    // the API's own cron: flight statuses advanced
];

const local = Object.fromEntries(COUNTERS.map((n) => [n, 0]));
const gauges = { inflight: 0 };
let flushTimer = null;
let minuteTimer = null;
let started = Date.now();

export const counters = {
  incr(name, n = 1) {
    if (!(name in local)) throw new Error(`unknown counter ${name}`);
    local[name] += n;
    redis.cmd('INCRBY', keys.counter(name), n).catch(() => {});
  },
};

export function setInflight(n) {
  gauges.inflight = n;
}

db.hooks.onQuery = (ms) => {
  counters.incr('db_query');
  if (ms > config.db.slowQueryMs) counters.incr('db_slow');
};

// Deltas → MariaDB, then MariaDB → Redis where Redis is behind.
export async function flush() {
  const rows = COUNTERS.filter((n) => local[n] > 0).map((n) => {
    const v = local[n];
    local[n] = 0;
    return [n, v];
  });
  try {
    if (rows.length) {
      await db.query(
        'INSERT INTO stats (name, value) VALUES ? ON DUPLICATE KEY UPDATE value = value + VALUES(value)',
        [rows],
        { internal: true },
      );
    }
    const durable = await db.query('SELECT name, value FROM stats', [], { internal: true });
    if (redis.connected && durable.length) {
      const names = durable.map((r) => r.name).filter((n) => COUNTERS.includes(n));
      const hot = await redis.cmd('MGET', ...names.map((n) => keys.counter(n)));
      const fixes = [];
      names.forEach((n, i) => {
        const want = Number(durable.find((r) => r.name === n).value);
        if (Number(hot[i] ?? 0) < want) fixes.push(keys.counter(n), want);
      });
      if (fixes.length) {
        await redis.cmd('MSET', ...fixes);
        log('info', 'counters re-hydrated into redis', { keys: fixes.length / 2 });
      }
    }
  } catch (e) {
    // put the deltas back so nothing is lost; next tick retries
    for (const [n, v] of rows) local[n] += v;
    log('warn', 'stats flush failed', { error: e.code || e.message });
  }
}

// The API's own cron: on every minute boundary, flights age from boarding to
// en-route to landed. The machine room rings its bell on it.
async function minuteTick() {
  try {
    // Read which rows are about to move first: each has its own cached copy
    // (lab:flights:<id>:v1, TTL 300 s) that must go with the list, or a
    // flight page would show the old status for up to five minutes.
    const moving = await db.execute(
      `SELECT id FROM flights
        WHERE (status = 'boarding' AND created_at < NOW() - INTERVAL 30 SECOND)
           OR (status = 'en-route' AND created_at < NOW() - INTERVAL 3 MINUTE)`,
      [], { internal: true },
    );
    const a = await db.execute(
      "UPDATE flights SET status = 'en-route' WHERE status = 'boarding' AND created_at < NOW() - INTERVAL 30 SECOND",
      [], { internal: true },
    );
    const b = await db.execute(
      "UPDATE flights SET status = 'landed' WHERE status = 'en-route' AND created_at < NOW() - INTERVAL 3 MINUTE",
      [], { internal: true },
    );
    const changed = (a.affectedRows || 0) + (b.affectedRows || 0);
    if (changed || moving.length) {
      await invalidate(keys.flightsAll, keys.statsTables, ...moving.map((r) => keys.flight(r.id)));
    }
    counters.incr('minute_ticks');
    log('info', 'minute tick', { flights_advanced: changed });
  } catch (e) {
    log('warn', 'minute tick failed', { error: e.code || e.message });
  }
}

export function start() {
  started = Date.now();
  flushTimer = setInterval(() => { flush(); }, config.statsFlushMs);
  const toBoundary = 60000 - (Date.now() % 60000);
  minuteTimer = setTimeout(() => {
    minuteTick();
    minuteTimer = setInterval(minuteTick, 60000);
  }, toBoundary);
  redis.onConnect = () => { flush(); };
}

export function stop() {
  clearInterval(flushTimer);
  clearTimeout(minuteTimer);
  clearInterval(minuteTimer);
}

async function counterValues() {
  if (redis.connected) {
    try {
      const hot = await redis.cmd('MGET', ...COUNTERS.map((n) => keys.counter(n)));
      return { source: 'redis', values: Object.fromEntries(COUNTERS.map((n, i) => [n, Number(hot[i] ?? 0)])) };
    } catch { /* fall through */ }
  }
  const durable = await db.query('SELECT name, value FROM stats', [], { internal: true });
  const values = Object.fromEntries(COUNTERS.map((n) => [n, 0]));
  for (const r of durable) if (r.name in values) values[r.name] = Number(r.value);
  for (const n of COUNTERS) values[n] += local[n];
  return { source: 'mariadb', values };
}

async function tableCounts() {
  const { value } = await cached(keys.statsTables, TTL.statsTables, async () => {
    const byStatus = await db.query('SELECT status, COUNT(*) AS n FROM flights GROUP BY status', [], { internal: true });
    const gb = await db.query('SELECT COUNT(*) AS n FROM guestbook', [], { internal: true });
    const flights = { boarding: 0, 'en-route': 0, landed: 0, diverted: 0 };
    for (const r of byStatus) flights[r.status] = Number(r.n);
    return { flights, guestbook: Number(gb[0]?.n ?? 0) };
  });
  return value;
}

export async function snapshot() {
  const [{ source, values }, tables] = await Promise.all([counterValues(), tableCounts()]);
  const mem = process.memoryUsage();
  return {
    ts: new Date().toISOString(),
    source,
    counters: values,
    gauges: {
      inflight: gauges.inflight,
      uptime_s: Math.floor(process.uptime()),
      started_at: new Date(started).toISOString(),
      rss_mb: Math.round(mem.rss / 1048576),
      heap_mb: Math.round(mem.heapUsed / 1048576),
      redis_connected: redis.connected,
      db_pool: db.poolStats(),
    },
    flights: tables.flights,
    guestbook_entries: tables.guestbook,
    next_minute_tick_s: Math.ceil((60000 - (Date.now() % 60000)) / 1000),
  };
}
