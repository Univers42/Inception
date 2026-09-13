// srcs/requirements/bonus/web/app/src/components/islands/counters.ts
import { live } from '../../lib/live';
import { fmt } from '../../lib/api';

const source = document.getElementById('ctr-source');
const pool = document.getElementById('ctr-pool');
const flights = document.getElementById('ctr-flights');
const meters = new Map([...document.querySelectorAll<HTMLElement>('.meter[data-counter]')].map((m) => [m.dataset.counter!, m]));

live.on((ev) => {
  if (ev.type === 'health' && !ev.ok && source) source.textContent = 'stale';
  if (ev.type !== 'stats') return;
  const { stats, delta } = ev;
  const max = Math.max(1, ...Object.values(stats.counters));
  for (const [name, m] of meters) {
    const v = stats.counters[name] ?? 0;
    m.querySelector('.v')!.textContent = fmt.int(v);
    m.querySelector('.bar')!.textContent = fmt.bar(v, max);
    m.classList.toggle('bump', (delta[name] ?? 0) > 0);
  }
  if (source) source.textContent = stats.source;
  if (pool) pool.textContent = `${stats.gauges.db_pool.size}/${stats.gauges.db_pool.limit}`;
  const f = stats.flights;
  if (flights) flights.textContent = `flights boarding ${f.boarding} · en-route ${f['en-route']} · landed ${f.landed} · diverted ${f.diverted}`;
});
