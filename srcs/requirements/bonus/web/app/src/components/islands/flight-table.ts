// srcs/requirements/bonus/web/app/src/components/islands/flight-table.ts
// Hydrates every departures board on the page: live rows + the filter box.
import { live } from '../../lib/live';
import { flightRow } from '../../lib/rows';

const tables = document.querySelectorAll<HTMLTableElement>('table[data-flights]');
const filter = document.getElementById('flight-filter') as HTMLInputElement | null;
const count = document.getElementById('flight-count');

function applyFilter() {
  const q = (filter?.value ?? '').trim().toLowerCase();
  let shown = 0;
  for (const t of tables) for (const tr of t.tBodies[0].rows) {
    const hit = !q || q.split(/\s+/).every((w) => (tr.dataset.text ?? '').includes(w));
    tr.hidden = !hit; if (hit) shown++;
  }
  if (count) count.textContent = `${shown} shown`;
}
filter?.addEventListener('input', applyFilter);

live.on((ev) => {
  if (ev.type !== 'flights') return;
  const fresh = new Set(ev.added.map((f) => f.id));
  const moved = new Set(ev.changed.map((f) => f.id));
  for (const t of tables) {
    const limit = Number(t.dataset.limit) || 100;
    const rows = ev.flights.slice(0, limit).map((f) => {
      const tr = flightRow(f);
      if (fresh.has(f.id)) tr.classList.add('row-new');
      if (moved.has(f.id)) tr.classList.add('row-moved');
      return tr;
    });
    t.tBodies[0].replaceChildren(...rows);
  }
  applyFilter();
});
