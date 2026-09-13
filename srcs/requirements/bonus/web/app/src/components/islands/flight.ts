// srcs/requirements/bonus/web/app/src/components/islands/flight.ts
// Keeps one flight's status live: from the list the poll loop already
// fetches, or from GET /flights/:id when this flight fell out of the list.
import { api, type Flight } from '../../lib/api';
import { live } from '../../lib/live';

const host = document.querySelector<HTMLElement>('[data-flight-id]');
if (host) {
  const id = Number(host.dataset.flightId);
  const title = document.getElementById('fl-status');
  const cell = document.getElementById('fl-status-cell');
  const source = document.getElementById('fl-source');
  const show = (f: Flight, from: string) => {
    if (title) title.textContent = f.status;
    if (cell) { cell.textContent = f.status; cell.className = `st st-${f.status}`; }
    if (source) source.textContent = `${from} · ${new Date().toTimeString().slice(0, 8)}`;
  };
  live.on(async (ev) => {
    if (ev.type !== 'flights') return;
    const f = ev.flights.find((x) => x.id === id);
    if (f) return show(f, 'live list');
    try { show(await api.flight(id), 'GET /flights/' + id); } catch { if (source) source.textContent = 'not found in the API'; }
  });
}
