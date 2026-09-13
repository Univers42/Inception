// srcs/requirements/bonus/api/app/config.js
//
// Every knob the API reads, in one place. Hostnames and names come from the
// environment (compose passes them from srcs/.env). The database password comes
// from a Docker secret file, read exactly once at startup while the process is
// still root, and never enters the environment.
import { readFileSync } from 'node:fs';

function need(name) {
  const v = process.env[name];
  if (!v) throw new Error(`config: ${name} is required`);
  return v;
}

function secretFile(name) {
  const path = `/run/secrets/${name}`;
  let v;
  try {
    v = readFileSync(path, 'utf8').trim();
  } catch (e) {
    throw new Error(`config: cannot read ${path} (${e.code || e.message})`);
  }
  if (!v) throw new Error(`config: ${path} is empty`);
  return v;
}

export const config = {
  port: 3000,
  // the unprivileged account the server switches to once the secret is read
  runAs: 'api',
  db: {
    host: need('API_DB_HOST'),
    port: Number(process.env.API_DB_PORT || 3306),
    name: need('API_DB_NAME'),
    user: need('API_DB_USER'),
    password: secretFile('api_db_password'), // /run/secrets/api_db_password, mounted by compose
    poolSize: 5,
    slowQueryMs: 100,
  },
  redis: {
    host: need('API_REDIS_HOST'),
    port: Number(process.env.API_REDIS_PORT || 6379),
  },
  // fixed-window rate limits: how many writes one client address may make per window
  rateLimit: {
    guestbook: { limit: 5, windowS: 60 },
    flights: { limit: 10, windowS: 60 },
  },
  // the wires in the machine room (traffic.js)
  traffic: {
    frameMs: 200,      // one SSE frame per interval, carrying every event since the last
    sampleMs: 1000,    // php-fpm, Redis and MariaDB counters are read this often
    maxClients: 64,    // open streams, all addresses together
    maxPerAddress: 4,  // open streams from one client address
  },
  // php-fpm's pool status, read over FastCGI for the nginx → wordpress wire
  fpm: {
    host: process.env.API_FPM_HOST || 'wordpress',
    port: Number(process.env.API_FPM_PORT || 9000),
    // nginx forwards PHP with `fastcgi_keep_conn on` and no upstream keepalive
    // pool: it asks php-fpm to keep the connection, then closes it. php-fpm
    // counts the request, then counts again when it starts waiting for the next
    // one on that connection. Measured: 2 per page, 1 for a plain FastCGI
    // request like ours. tests/lab.sh (L26) fails if that ever changes.
    countsPerRequest: 2,
  },
  // milliseconds between counter write-throughs to MariaDB
  statsFlushMs: 2000,
  // how long a SIGTERM waits for in-flight requests before closing sockets
  drainTimeoutMs: 10000,
  version: process.env.npm_package_version || '1.0.0',
};
