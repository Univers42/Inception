// srcs/requirements/bonus/web/app/src/components/islands/guestbook.ts
import { api, ApiError, fmt } from '../../lib/api';
import { entryItem } from '../../lib/rows';
import { formKit } from '../../lib/form';

const list = document.getElementById('gb-list');
const state = document.getElementById('gb-state');
const form = document.getElementById('guestbook') as HTMLFormElement | null;
let timer: ReturnType<typeof setTimeout> | undefined;

async function load() {
  if (timer) clearTimeout(timer);
  if (document.visibilityState === 'visible') {
    try {
      const entries = await api.guestbook();
      list?.replaceChildren(...entries.map(entryItem));
      if (state) state.textContent = entries.length ? `${entries.length} most recent · read ${fmt.clock(new Date())}` : 'nobody has signed yet';
    } catch (e) {
      if (state) state.textContent = `could not read the guestbook: ${e instanceof ApiError ? `${e.status || 'offline'} ${e.code}` : e}`;
    }
  }
  timer = setTimeout(load, 10000);
}
document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') load(); });
if (list) load();

if (form) {
  const kit = formKit('g', document.getElementById('g-send') as HTMLButtonElement, document.getElementById('g-out')!);
  form.addEventListener('submit', (ev) => {
    ev.preventDefault();
    const data = new FormData(form);
    kit.submit(async () => {
      const e = await api.sign({ handle: String(data.get('handle') ?? ''), message: String(data.get('message') ?? '') });
      kit.say(`201 signed as ${e.handle} (entry ${e.id})`, 'ok');
      (form.elements.namedItem('message') as HTMLTextAreaElement).value = '';
      load();
    });
  });
}
