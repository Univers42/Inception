// srcs/requirements/bonus/web/app/src/components/islands/dispatch.ts
import { api } from '../../lib/api';
import { live } from '../../lib/live';
import { formKit } from '../../lib/form';

const form = document.getElementById('dispatch') as HTMLFormElement | null;
if (form) {
  const kit = formKit('d', document.getElementById('d-send') as HTMLButtonElement, document.getElementById('d-out')!);
  form.addEventListener('submit', (ev) => {
    ev.preventDefault();
    const data = new FormData(form);
    // sent as typed: the API, not this page, decides what is valid
    const kb = String(data.get('payload_kb') ?? '').trim();
    const body: Record<string, unknown> = { origin: data.get('origin'), destination: data.get('destination') };
    if (kb) body.payload_kb = /^\d+$/.test(kb) ? Number(kb) : kb;
    const note = String(data.get('note') ?? '');
    if (note) body.note = note;
    kit.submit(async () => {
      const f = await api.dispatch(body as any);
      kit.say(`201 ${f.callsign} ${f.status} at ${f.origin} for ${f.destination}, ${f.payload_kb} kB (id ${f.id})`, 'ok');
      live.refreshFlights();
    });
  });
}
