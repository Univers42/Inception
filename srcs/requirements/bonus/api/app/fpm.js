// srcs/requirements/bonus/api/app/fpm.js
//
// Reads php-fpm's pool status (pm.status_path = /fpm-status in www.conf) by
// speaking FastCGI to wordpress:9000 directly — the same protocol nginx uses,
// so no HTTP endpoint has to exist for it. One request, one connection, then
// closed. Used once a second by traffic.js, and only while someone watches.
//
// FastCGI, for the record: every message is a record with an 8-byte header
//   version(1) type(1) requestId(2) contentLength(2) paddingLength(1) reserved(1)
// A request is BEGIN_REQUEST, PARAMS (name-value pairs) closed by an empty
// PARAMS, then an empty STDIN. The answer is STDOUT records (a CGI header
// block, a blank line, the body) ended by END_REQUEST.
import net from 'node:net';

const BEGIN_REQUEST = 1, END_REQUEST = 3, PARAMS = 4, STDIN = 5, STDOUT = 6;
const RESPONDER = 1;

function record(type, content = Buffer.alloc(0)) {
  const pad = (8 - (content.length % 8)) % 8;
  const h = Buffer.alloc(8);
  h[0] = 1;                        // version
  h[1] = type;
  h.writeUInt16BE(1, 2);           // requestId: one request per connection
  h.writeUInt16BE(content.length, 4);
  h[6] = pad;
  return Buffer.concat([h, content, Buffer.alloc(pad)]);
}

// A length is one byte below 128, else four bytes with the top bit set.
function len(n) {
  if (n < 128) return Buffer.from([n]);
  const b = Buffer.alloc(4);
  b.writeUInt32BE((n | 0x80000000) >>> 0);
  return b;
}

function pairs(obj) {
  return Buffer.concat(Object.entries(obj).map(([k, v]) => {
    const kb = Buffer.from(k), vb = Buffer.from(String(v));
    return Buffer.concat([len(kb.length), len(vb.length), kb, vb]);
  }));
}

// → the status document as an object ({ 'accepted conn': 123, … }).
export function status({ host, port, path = '/fpm-status', timeoutMs = 1000 }) {
  return new Promise((resolve, reject) => {
    const sock = net.createConnection({ host, port });
    const chunks = [];
    let buf = Buffer.alloc(0);
    let done = false;
    const finish = (err, value) => {
      if (done) return;
      done = true;
      sock.destroy();
      if (err) reject(err); else resolve(value);
    };
    sock.setTimeout(timeoutMs, () => finish(new Error('fpm: timeout')));
    sock.on('error', (e) => finish(e));
    sock.on('close', () => finish(new Error('fpm: closed before END_REQUEST')));
    sock.on('connect', () => {
      const begin = Buffer.alloc(8);
      begin.writeUInt16BE(RESPONDER, 0);
      sock.write(Buffer.concat([
        record(BEGIN_REQUEST, begin),
        record(PARAMS, pairs({
          REQUEST_METHOD: 'GET',
          SCRIPT_NAME: path,
          SCRIPT_FILENAME: path,
          REQUEST_URI: `${path}?json`,
          QUERY_STRING: 'json',
          SERVER_PROTOCOL: 'HTTP/1.1',
          GATEWAY_INTERFACE: 'CGI/1.1',
        })),
        record(PARAMS),
        record(STDIN),
      ]));
    });
    sock.on('data', (chunk) => {
      buf = Buffer.concat([buf, chunk]);
      while (buf.length >= 8) {
        const type = buf[1], n = buf.readUInt16BE(4), pad = buf[6];
        if (buf.length < 8 + n + pad) break;
        if (type === STDOUT) chunks.push(buf.subarray(8, 8 + n));
        buf = buf.subarray(8 + n + pad);
        if (type === END_REQUEST) {
          const text = Buffer.concat(chunks).toString('utf8');
          const body = text.slice(text.indexOf('\r\n\r\n') + 4);
          try {
            finish(null, JSON.parse(body));
          } catch {
            finish(new Error(`fpm: not a status document: ${text.slice(0, 80)}`));
          }
          return;
        }
      }
    });
  });
}
