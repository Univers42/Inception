// srcs/requirements/bonus/api/app/redis.js
//
// A Redis client written on node:net — no dependency. RESP2 only, which is what
// every command this API uses speaks.
//
// Wire format, for the record. Redis accepts two request encodings:
//   inline:  `GET lab:x\r\n`  — space-separated, no way to carry a space, a
//            quote or a newline inside an argument;
//   RESP2 array:  `*2\r\n$3\r\nGET\r\n$5\r\nlab:x\r\n`  — every argument is
//            length-prefixed, so any byte sequence is one argument, full stop.
// We always send the array form: a guestbook message containing "\r\nFLUSHALL"
// is data, not a second command. Replies are parsed by type byte:
//   +simple string   -error   :integer   $bulk string (-1 = nil)   *array
//
// Commands are pipelined naturally: each call appends its resolver to a queue
// and writes; replies come back in order and pop the queue. A dropped
// connection rejects every queued call (callers fall through to MariaDB) and
// reconnects with capped exponential backoff.
import net from 'node:net';
import { log } from './log.js';

export class RedisError extends Error {
  constructor(message) {
    super(message);
    this.name = 'RedisError';
  }
}

const CRLF = Buffer.from('\r\n');

function encode(args) {
  const parts = [Buffer.from(`*${args.length}\r\n`)];
  for (const a of args) {
    const b = Buffer.from(String(a));
    parts.push(Buffer.from(`$${b.length}\r\n`), b, CRLF);
  }
  return Buffer.concat(parts);
}

// Parse one reply starting at `off`. Returns [value, nextOffset], or null when
// the buffer does not yet hold a complete reply.
function parse(buf, off) {
  if (off >= buf.length) return null;
  const type = buf[off];
  const eol = buf.indexOf('\r\n', off + 1, 'latin1');
  if (eol === -1) return null;
  const line = buf.toString('utf8', off + 1, eol);
  const next = eol + 2;
  switch (type) {
    case 0x2b: // +
      return [line, next];
    case 0x2d: // -
      return [new RedisError(line), next];
    case 0x3a: // :
      return [Number(line), next];
    case 0x24: { // $
      const n = Number(line);
      if (n === -1) return [null, next];
      if (buf.length < next + n + 2) return null;
      return [buf.toString('utf8', next, next + n), next + n + 2];
    }
    case 0x2a: { // *
      const n = Number(line);
      if (n === -1) return [null, next];
      const items = [];
      let p = next;
      for (let i = 0; i < n; i += 1) {
        const r = parse(buf, p);
        if (!r) return null;
        items.push(r[0]);
        p = r[1];
      }
      return [items, p];
    }
    default:
      throw new Error(`unexpected reply type byte 0x${type.toString(16)}`);
  }
}

export class Redis {
  #sock = null;
  #buf = Buffer.alloc(0);
  #queue = [];
  #closing = false;
  #backoffMs = 200;
  #timer = null;

  connected = false;

  // Replies received so far, and the keyspace lookups among them counted the
  // way Redis counts keyspace_hits/misses (GET, MGET per key, TTL; writes do
  // not count). traffic.js subtracts these from INFO to see what every other
  // client of this Redis did.
  own = { replies: 0, hits: 0, misses: 0 };

  // (outcome, ms) for every command that completes or is lost: 'hit' | 'miss'
  // for GET, 'err' for an error reply or a dropped connection, else 'ok'.
  onCommand = null;

  constructor({ host, port, onConnect }) {
    this.host = host;
    this.port = port;
    this.onConnect = onConnect;
  }

  connect() {
    if (this.#closing) return;
    const s = net.createConnection({ host: this.host, port: this.port });
    s.setNoDelay(true);
    s.on('connect', () => {
      this.connected = true;
      this.#backoffMs = 200;
      log('info', 'redis connected', { host: this.host, port: this.port });
      this.onConnect?.();
    });
    s.on('data', (chunk) => this.#onData(chunk));
    s.on('error', (e) => log('warn', 'redis socket error', { error: e.code || e.message }));
    s.on('close', () => {
      const was = this.connected;
      this.connected = false;
      this.#buf = Buffer.alloc(0);
      for (const p of this.#queue.splice(0)) {
        this.onCommand?.('err', performance.now() - p.t0);
        p.reject(new Error('redis: connection closed'));
      }
      if (this.#closing) return;
      if (was) log('warn', 'redis disconnected, reconnecting', { in_ms: this.#backoffMs });
      this.#timer = setTimeout(() => this.connect(), this.#backoffMs);
      this.#timer.unref();
      this.#backoffMs = Math.min(this.#backoffMs * 2, 5000);
    });
    this.#sock = s;
  }

  #onData(chunk) {
    this.#buf = this.#buf.length ? Buffer.concat([this.#buf, chunk]) : chunk;
    let off = 0;
    for (;;) {
      let r;
      try {
        r = parse(this.#buf, off);
      } catch (e) {
        log('error', 'redis protocol error', { error: e.message });
        this.#sock.destroy();
        return;
      }
      if (!r) break;
      off = r[1];
      const p = this.#queue.shift();
      if (p) {
        const v = r[0];
        // an INFO asked with snap sees our counters as they stood just before it ran
        const before = p.snap ? { ...this.own } : null;
        const outcome = this.#account(p.name, v);
        this.onCommand?.(outcome, performance.now() - p.t0);
        if (v instanceof RedisError) p.reject(v);
        else p.resolve(before ? { value: v, own: before } : v);
      }
    }
    this.#buf = off ? this.#buf.subarray(off) : this.#buf;
  }

  #account(name, v) {
    const o = this.own;
    o.replies += 1;
    if (v instanceof RedisError) return 'err';
    if (name === 'GET') {
      if (v === null) { o.misses += 1; return 'miss'; }
      o.hits += 1;
      return 'hit';
    }
    if (name === 'MGET') for (const x of v) { if (x === null) o.misses += 1; else o.hits += 1; }
    else if (name === 'TTL') { if (v === -2) o.misses += 1; else o.hits += 1; }
    return 'ok';
  }

  #send(args, snap) {
    if (!this.connected) return Promise.reject(new Error('redis: not connected'));
    return new Promise((resolve, reject) => {
      // commands are pipelined in order, so replies pop this queue in order
      this.#queue.push({ resolve, reject, name: args[0], t0: performance.now(), snap });
      this.#sock.write(encode(args));
    });
  }

  cmd(...args) {
    return this.#send(args, false);
  }

  // INFO <section>, resolved as { value, own }: `own` is this client's counters
  // as they stood when Redis executed the INFO. Replies come back in the order
  // commands were sent, so every command counted in `own` ran before the INFO,
  // and every command INFO reports as processed that is not in `own` came
  // from another client.
  info(section) {
    return this.#send(['INFO', section], true);
  }

  async quit() {
    this.#closing = true;
    clearTimeout(this.#timer);
    if (this.connected) {
      try { await this.cmd('QUIT'); } catch { /* already gone */ }
    }
    this.#sock?.destroy();
  }
}
