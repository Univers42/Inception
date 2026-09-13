// srcs/requirements/bonus/web/app/src/lib/palette.ts
// A <dialog> with one input. Enter runs a command, Tab completes its name,
// ↑/↓ walk the history, Escape closes (the dialog does that natively, and
// showModal() gives the focus trap for free).
import { findCommand, complete, type Ctx } from './commands';

export function createPalette(opts: { cheatsheet: () => void }) {
  const dlg = document.getElementById('palette') as HTMLDialogElement;
  const form = document.getElementById('palette-form') as HTMLFormElement;
  const input = document.getElementById('palette-input') as HTMLInputElement;
  const out = document.getElementById('palette-out') as HTMLPreElement;
  const history: string[] = [];
  let hIdx = -1;

  const ctx: Ctx = {
    print(line, cls) {
      const el = document.createElement('span');
      if (cls) el.className = cls;
      el.textContent = line + '\n';
      out.append(el);
      out.scrollTop = out.scrollHeight;
    },
    close() { if (dlg.open) dlg.close(); },
    cheatsheet: opts.cheatsheet,
  };

  async function run(raw: string) {
    const line = raw.replace(/^:+/, '').trim();
    if (!line) return;
    history.unshift(line); if (history.length > 50) history.pop(); hIdx = -1;
    const [name, ...args] = line.split(/\s+/);
    ctx.print(`:${line}`, 'attn');
    const cmd = findCommand(name);
    if (!cmd) return ctx.print(`:${name}: command not found`, 'err');
    try { await cmd.run(args, ctx); } catch (e) { ctx.print(String((e as Error)?.message ?? e), 'err'); }
  }

  form.addEventListener('submit', (ev) => { ev.preventDefault(); const v = input.value; input.value = ''; run(v); });
  input.addEventListener('keydown', (ev) => {
    if (ev.key === 'Tab') {
      const [head] = input.value.split(/\s+/);
      const c = complete(head);
      if (input.value === head && c.length === 1) { input.value = c[0] + ' '; ev.preventDefault(); }
      else if (input.value === head && c.length > 1) { ctx.print(c.join('  ')); ev.preventDefault(); }
    } else if (ev.key === 'ArrowUp') { if (hIdx < history.length - 1) { hIdx++; input.value = history[hIdx]; } ev.preventDefault(); }
    else if (ev.key === 'ArrowDown') { hIdx = Math.max(-1, hIdx - 1); input.value = hIdx < 0 ? '' : history[hIdx]; ev.preventDefault(); }
  });
  dlg.addEventListener('click', (ev) => { if (ev.target === dlg) dlg.close(); });

  return {
    open(prefill = '') {
      if (!dlg.open) dlg.showModal();
      input.value = prefill; input.focus(); input.setSelectionRange(prefill.length, prefill.length);
      if (!out.childElementCount) ctx.print('type a command — :help lists them');
    },
    close: ctx.close,
    isOpen: () => dlg.open,
  };
}
