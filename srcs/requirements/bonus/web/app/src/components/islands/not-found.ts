// srcs/requirements/bonus/web/app/src/components/islands/not-found.ts
import { api, fmt, type Flight } from '../../lib/api';
import { live } from '../../lib/live';

const m = location.pathname.match(/^\/lab\/flights\/(\d+)\/?$/);
const path = document.getElementById('nf-path');
if (path) path.textContent = location.pathname;
if (m) {
  const id = Number(m[1]);
  const $ = (k: string) => document.getElementById(k)!;
  const show = (f: Flight) => {
    document.title = `${f.callsign} · lab`;
    $('nf-code').textContent = 'flight';
    $('nf-path').textContent = `${f.callsign} · id ${f.id}`;
    $('nf-body').hidden = true; $('nf-flight').hidden = false;
    $('nf-route').textContent = `${f.origin} ─► ${f.destination}`;
    $('nf-status').textContent = f.status; $('nf-status').className = `st st-${f.status}`;
    $('nf-payload').textContent = `${f.payload_kb} kB`;
    $('nf-note').textContent = f.note || '—';
    $('nf-created').textContent = `${fmt.date(f.created_at)} ${fmt.utc(f.created_at)}`;
    $('nf-id').textContent = String(f.id);
  };
  api.flight(id).then(show).catch(() => { /* a real 404: the default text stays */ });
  live.on((ev) => { if (ev.type === 'flights') { const f = ev.flights.find((x) => x.id === id); if (f) show(f); } });
}
