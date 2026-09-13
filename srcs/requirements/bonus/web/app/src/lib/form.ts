// srcs/requirements/bonus/web/app/src/lib/form.ts
// Shared by the dispatch and guestbook forms: show the API's 422 on the field
// it names, count down a 429's Retry-After on the button.
import { ApiError } from './api';

export function formKit(prefix: string, button: HTMLButtonElement, out: HTMLElement) {
  const label = button.textContent ?? 'send';
  let countdown: ReturnType<typeof setInterval> | undefined;

  function clear() {
    document.querySelectorAll<HTMLElement>(`[id^="${prefix}-"][id$="-err"]`).forEach((e) => { e.hidden = true; e.textContent = ''; });
    document.querySelectorAll<HTMLElement>(`[id^="${prefix}-"][aria-invalid]`).forEach((e) => e.removeAttribute('aria-invalid'));
    out.className = 'mono'; out.textContent = '';
  }
  function say(text: string, cls: 'ok' | 'err' | 'muted') { out.className = `mono ${cls}`; out.textContent = text; }

  function fail(e: unknown) {
    if (!(e instanceof ApiError)) return say(String((e as Error)?.message ?? e), 'err');
    if (e.status === 422 && e.field) {
      const input = document.getElementById(`${prefix}-${e.field}`);
      const err = document.getElementById(`${prefix}-${e.field}-err`);
      if (input) { input.setAttribute('aria-invalid', 'true'); input.focus(); }
      if (err) { err.hidden = false; err.textContent = `${e.code}: ${e.message}`; }
      return say(`422 ${e.code} — ${e.field}`, 'err');
    }
    if (e.status === 429) {
      let left = e.retryAfterS ?? 60;
      button.disabled = true;
      const paint = () => { button.textContent = `retry in ${left}s`; if (left-- <= 0) { clearInterval(countdown); button.disabled = false; button.textContent = label; } };
      if (countdown) clearInterval(countdown);
      paint(); countdown = setInterval(paint, 1000);
      return say(`429 ${e.message}`, 'err');
    }
    return say(e.status ? `${e.status} ${e.code}: ${e.message}` : `the API is unreachable (${e.message})`, 'err');
  }

  async function submit(send: () => Promise<void>) {
    clear();
    button.disabled = true; button.textContent = 'sending…';
    try { await send(); button.disabled = false; button.textContent = label; }
    catch (e) { button.disabled = false; button.textContent = label; fail(e); }
  }
  return { submit, say };
}
