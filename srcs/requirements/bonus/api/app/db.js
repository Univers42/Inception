// srcs/requirements/bonus/api/app/db.js
//
// MariaDB access. One pool of five connections; every statement that carries
// user input goes through `execute` (server-side prepared statement, values
// never concatenated into SQL). `query` with the `VALUES ?` bulk form is used
// only for the counter write-through, whose values are integers we produced.
import mysql from 'mysql2/promise';
import { config } from './config.js';
import { log } from './log.js';

const { host, port, user, password, name: database, poolSize } = config.db;

export const pool = mysql.createPool({
  host,
  port,
  user,
  password,
  database,
  connectionLimit: poolSize,
  waitForConnections: true,
  queueLimit: 100,
  connectTimeout: 3000,
  enableKeepAlive: true,
  timezone: 'Z',
  dateStrings: false,
});

// Observers: onQuery (stats.js) gets request-facing statements only;
// onStatement (traffic.js) gets every statement, internal ones included.
export const hooks = { onQuery: null, onStatement: null };

// Statements this process has completed. traffic.js subtracts it from
// MariaDB's global Questions counter to see what every other client sent.
export const own = { statements: 0 };

const RETRYABLE = new Set([
  'ECONNREFUSED', 'ETIMEDOUT', 'ECONNRESET', 'EHOSTUNREACH', 'ENOTFOUND', 'EAI_AGAIN',
  'PROTOCOL_CONNECTION_LOST', 'ER_CON_COUNT_ERROR', 'ER_SERVER_SHUTDOWN',
]);

const sleep = (ms) => new Promise((r) => { setTimeout(r, ms); });

// Capped exponential backoff on connection refusals: 250 ms doubling to 5 s,
// for at most `maxWaitMs`. Any non-connection error (bad credentials, unknown
// database) is fatal immediately — retrying would only hide it.
export async function waitReady({ maxWaitMs = 90000 } = {}) {
  const t0 = Date.now();
  let delay = 250;
  for (;;) {
    try {
      await pool.query('SELECT 1');
      log('info', 'mariadb ready', { host: config.db.host, database: config.db.name, waited_ms: Date.now() - t0 });
      return;
    } catch (e) {
      const code = e.code || e.errno || 'unknown';
      if (!RETRYABLE.has(code) || Date.now() - t0 > maxWaitMs) throw e;
      log('warn', 'mariadb not ready, retrying', { code, in_ms: delay });
      await sleep(delay);
      delay = Math.min(delay * 2, 5000);
    }
  }
}

function elapsedMs(t0) {
  return Number(process.hrtime.bigint() - t0) / 1e6;
}

// `method` is 'execute' (prepared statement) or 'query'. Internal statements
// (schema, counters, probes) are excluded from the request-facing counters,
// not from the traffic view: they are real load on the database.
async function run(method, sql, params, internal) {
  const t0 = process.hrtime.bigint();
  let failed = false;
  try {
    const [rows] = await pool[method](sql, params);
    return rows;
  } catch (e) {
    failed = true;
    throw e;
  } finally {
    const ms = elapsedMs(t0);
    own.statements += 1;
    hooks.onStatement?.(ms, failed);
    if (!internal) hooks.onQuery?.(ms);
  }
}

// Prepared statement with parameters.
export function execute(sql, params = [], { internal = false } = {}) {
  return run('execute', sql, params, internal);
}

export function query(sql, params = [], { internal = false } = {}) {
  return run('query', sql, params, internal);
}

export async function ping() {
  await query('SELECT 1', [], { internal: true });
  return true;
}

// Runs schema.sql statement by statement. Every statement in that file is
// idempotent (CREATE TABLE IF NOT EXISTS, INSERT IGNORE), so this is safe on
// every boot and needs no marker file.
export async function migrate(sqlText) {
  const statements = sqlText
    .split('\n')
    .filter((l) => !l.trim().startsWith('--'))
    .join('\n')
    .split(/;\s*\n/)
    .map((s) => s.trim())
    .filter(Boolean);
  for (const s of statements) await query(s, [], { internal: true });
  log('info', 'schema applied', { statements: statements.length });
}

export function poolStats() {
  const p = pool.pool;
  return {
    size: p?._allConnections?.length ?? 0,
    idle: p?._freeConnections?.length ?? 0,
    queued: p?._connectionQueue?.length ?? 0,
    limit: config.db.poolSize,
  };
}

export async function close() {
  await pool.end();
  log('info', 'mariadb pool closed');
}
