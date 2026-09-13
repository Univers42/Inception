// srcs/requirements/bonus/api/app/log.js
//
// One JSON object per line on stdout. Docker keeps it; nothing is written to a
// file inside the container. `level` is one of debug/info/warn/error.
export function log(level, msg, fields = {}) {
  process.stdout.write(`${JSON.stringify({ ts: new Date().toISOString(), level, msg, ...fields })}\n`);
}
