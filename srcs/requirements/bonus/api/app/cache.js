// srcs/requirements/bonus/api/app/cache.js
//
// Cache-aside on Redis. MariaDB is the source of truth; Redis is a hot copy
// that is allowed to be missing, stale within its TTL, or down.
//
// Key scheme:  lab:<entity>:<id>:v<schema_version>
//
//   lab:flights:all:v1         JSON list of flights          TTL  60 s
//   lab:flights:<id>:v1        JSON flight                   TTL 300 s
//   lab:guestbook:recent:v1    JSON list of entries          TTL  10 s
//   lab:stats:tables:v1        JSON row counts for /stats    TTL   5 s
//   lab:stats:<counter>        integer, INCRBY               no TTL (durable copy in MariaDB)
//   lab:rl:<bucket>:<ip>       integer, INCR                 TTL = window (fixed-window rate limit)
//
// TTL is per entity, never global: a single flight changes rarely (300 s); the
// list changes on every POST, so it is short (60 s) and also invalidated
// explicitly; the guestbook must feel live (10 s); counters and rate-limit
// buckets are not caches, so they carry no cache TTL at all. The "v1" suffix
// is the schema version of the cached shape — bump it when the JSON changes
// and old entries become unreachable instead of wrong.
//
// The "lab:" prefix keeps these keys apart from the WordPress object cache,
// which shares this Redis instance under its own prefix.
import { AsyncLocalStorage } from 'node:async_hooks';
import { Redis } from './redis.js';
import { config } from './config.js';

export const redis = new Redis({ host: config.redis.host, port: config.redis.port });

export const keys = {
  flightsAll: 'lab:flights:all:v1',
  flight: (id) => `lab:flights:${id}:v1`,
  guestbookRecent: 'lab:guestbook:recent:v1',
  statsTables: 'lab:stats:tables:v1',
  counter: (name) => `lab:stats:${name}`,
  rateLimit: (bucket, ip) => `lab:rl:${bucket}:${ip}`,
};

// Set while a cache miss is being loaded from MariaDB, so the traffic view can
// colour those statements as misses: the key of the entry being loaded.
export const loading = new AsyncLocalStorage();

export const TTL = {
  flightsAll: 60,
  flight: 300,
  guestbookRecent: 10,
  statsTables: 5,
};

// Read-through: return the cached value, or run `loader`, store its result and
// return it. A `null` result is never cached (a 404 must not outlive the row's
// creation). Every Redis failure degrades to a plain database read.
export async function cached(key, ttl, loader) {
  try {
    const hit = await redis.cmd('GET', key);
    if (hit !== null) return { value: JSON.parse(hit), hit: true };
  } catch { /* redis down or key missing: fall through */ }
  const value = await loading.run(key, loader);
  if (value !== null && value !== undefined) {
    redis.cmd('SET', key, JSON.stringify(value), 'EX', ttl).catch(() => {});
  }
  return { value, hit: false };
}

export async function invalidate(...ks) {
  if (!ks.length) return 0;
  try {
    return await redis.cmd('DEL', ...ks);
  } catch {
    return 0;
  }
}

// Fixed window: INCR the bucket, set its expiry on first hit, refuse past the
// limit with the seconds left in the window. If Redis is unreachable the limit
// fails open — a demo guestbook that refuses every post because its cache is
// down would be the wrong failure.
export async function rateLimit(bucket, ip) {
  const { limit, windowS } = config.rateLimit[bucket];
  const key = keys.rateLimit(bucket, ip);
  try {
    const n = await redis.cmd('INCR', key);
    if (n === 1) await redis.cmd('EXPIRE', key, windowS);
    if (n > limit) {
      const ttl = await redis.cmd('TTL', key);
      return { limited: true, retryAfter: Math.max(1, ttl), limit, windowS };
    }
    return { limited: false, remaining: limit - n, limit, windowS };
  } catch {
    return { limited: false, degraded: true, limit, windowS };
  }
}
