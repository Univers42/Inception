// srcs/requirements/bonus/web/app/src/lib/rows.ts
// DOM builders for live rows. They produce exactly the markup the .astro
// components render at build time, so a live refresh never changes layout.
// Text goes in through textContent only: nothing from the API is ever HTML.
import { fmt, type Flight, type GuestbookEntry } from './api';

const base = '/lab/';

function el<K extends keyof HTMLElementTagNameMap>(tag: K, cls?: string, text?: string): HTMLElementTagNameMap[K] {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (text !== undefined) e.textContent = text;
  return e;
}

export const flightText = (f: Flight) => `${f.callsign} ${f.origin} ${f.destination} ${f.status} ${f.note ?? ''}`.toLowerCase();

export function flightRow(f: Flight): HTMLTableRowElement {
  const tr = el('tr');
  tr.dataset.id = String(f.id);
  tr.dataset.text = flightText(f);
  const a = el('a', 'mono', f.callsign); a.href = `${base}flights/${f.id}/`;
  const c1 = el('td'); c1.append(a);
  const c2 = el('td'); c2.append(el('span', 'mono', f.origin), ' ', el('span', 'arrow', '─►'), ' ', el('span', 'mono', f.destination));
  const c3 = el('td'); c3.append(el('span', `st st-${f.status}`, f.status));
  tr.append(c1, c2, c3, el('td', 'num', `${f.payload_kb} kB`), el('td', 'wrap', f.note ?? ''), el('td', 'mono muted', fmt.utc(f.created_at)));
  return tr;
}

export function entryItem(e: GuestbookEntry): HTMLLIElement {
  const li = el('li', 'entry');
  li.dataset.id = String(e.id);
  const head = el('div', 'entry-head');
  head.append(el('span', 'mono attn', e.handle), ' ', el('span', 'mono muted', `${fmt.date(e.created_at)} ${fmt.utc(e.created_at)}`));
  li.append(head, el('p', 'entry-msg', e.message));
  return li;
}
