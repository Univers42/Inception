// srcs/requirements/bonus/web/app/src/components/islands/cabinets.ts
// The LEDs of the cabinets table, from the latest probe: healthz for MariaDB
// and Redis, a HEAD through the edge for WordPress and the static site, and
// "the API answered" for nginx and api themselves.
import { live } from '../../lib/live';
import type { Cabinet } from '../../lib/api';

const rows = new Map([...document.querySelectorAll<HTMLElement>('tr[data-cab]')].map((r) => [r.dataset.cab as Cabinet, r]));
const probeAt = document.getElementById('cab-probe');

function set(c: Cabinet, state: 'ok' | 'down' | 'warn' | 'unknown', note?: string) {
  const r = rows.get(c); if (!r) return;
  const led = r.querySelector<HTMLElement>('[data-led]')!;
  led.className = 'led' + (state === 'unknown' ? '' : ` led--${state}`);
  led.title = state;
  if (note !== undefined) r.querySelector('[data-note]')!.textContent = note;
}

live.on((ev) => {
  if (ev.type === 'health') {
    set('api', ev.ok ? 'ok' : 'down'); set('nginx', ev.ok ? 'ok' : 'warn');
  } else if (ev.type === 'probe') {
    const { health, wordpress, web } = ev.probe;
    const wpOk = wordpress >= 200 && wordpress < 400;
    set('nginx', 'ok');
    set('api', health?.ok ? 'ok' : health ? 'warn' : 'down', health ? `json api · up ${Math.floor(health.uptime_s / 60)} min` : 'json api · no answer');
    set('mariadb', health?.mariadb.ok ? 'ok' : 'down', health?.mariadb.ok ? `database · ping ${health.mariadb.latency_ms} ms` : `database · ${health?.mariadb.error ?? 'unknown'}`);
    set('redis', health?.redis.ok ? 'ok' : 'down', health?.redis.ok ? `cache · ping ${health.redis.latency_ms} ms` : `cache · ${health?.redis.error ?? 'unknown'}`);
    set('wordpress', wpOk ? 'ok' : 'down', `php-fpm · HEAD / → ${wordpress || 'no answer'}`);
    set('web', web === 200 ? 'ok' : 'down', `static site · HEAD /lab/ → ${web || 'no answer'}`);
    if (probeAt) probeAt.textContent = new Date(ev.probe.at).toTimeString().slice(0, 8);
  }
});
