// srcs/requirements/bonus/web/app/src/lib/keymap.ts
// vim-shaped navigation. Nothing fires while an input has focus (Escape blurs
// it instead), Alt+1..4 always work, and 'g' waits 600 ms for the second 'g'.
export type KeyHandlers = {
  palette: (prefill?: string) => void;
  cheatsheet: () => void;
  closeAll: () => boolean; // returns true if something was open
};

const PAGES = ['', 'flights/', 'guestbook/', 'about/'];
const base = '/lab/';

export function isEditable(el: EventTarget | null): boolean {
  const e = el as HTMLElement | null;
  if (!e || !e.tagName) return false;
  const t = e.tagName;
  return t === 'INPUT' || t === 'TEXTAREA' || t === 'SELECT' || e.isContentEditable;
}

export function installKeymap(h: KeyHandlers) {
  let pendingG = 0;
  document.addEventListener('keydown', (ev) => {
    if (ev.ctrlKey || ev.metaKey) return;
    // Alt+1..4 (and plain 1..4 outside inputs): the four pages
    if (ev.key >= '1' && ev.key <= '4' && (ev.altKey || !isEditable(ev.target))) {
      if (document.querySelector('dialog[open]')) return;
      ev.preventDefault();
      const target = base + PAGES[Number(ev.key) - 1];
      if (location.pathname !== target) location.assign(target);
      return;
    }
    if (ev.altKey) return;
    if (isEditable(ev.target)) {
      if (ev.key === 'Escape') (ev.target as HTMLElement).blur();
      return;
    }
    if (document.querySelector('dialog[open]')) {
      if (ev.key === 'Escape') { h.closeAll(); }
      return; // dialogs own their keys
    }
    switch (ev.key) {
      case ':': ev.preventDefault(); h.palette(''); break;
      case '/': {
        ev.preventDefault();
        const search = document.querySelector<HTMLInputElement>('input[data-search]');
        if (search) { search.focus(); search.select(); } else h.palette('goto ');
        break;
      }
      case '?': ev.preventDefault(); h.cheatsheet(); break;
      case 'g': {
        const now = Date.now();
        if (now - pendingG < 600) { pendingG = 0; window.scrollTo({ top: 0 }); ev.preventDefault(); }
        else pendingG = now;
        break;
      }
      case 'G': ev.preventDefault(); window.scrollTo({ top: document.documentElement.scrollHeight }); break;
      case 'j': ev.preventDefault(); window.scrollBy({ top: 48 }); break;
      case 'k': ev.preventDefault(); window.scrollBy({ top: -48 }); break;
      case 'Escape': h.closeAll(); break;
      default: return;
    }
  });
}
