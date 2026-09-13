// srcs/requirements/bonus/web/app/src/lib/wires.ts
// The six wires the machine room draws, and what a dot's colour means. The ids
// are the API's (traffic.js). Pure data: imported at build time by the table
// under the canvas and at run time by the engine.
import type { Cabinet } from './api';

export const OUTCOMES = ['ok', 'hit', 'miss', 'slow', 'err'] as const;
export type Outcome = (typeof OUTCOMES)[number];
// VGA palette indices, in OUTCOMES order
export const OUTCOME_COLOR = [15, 11, 14, 13, 12];
export const OUTCOME_LABEL: Record<Outcome, string> = {
  ok: 'answered',
  hit: 'cache hit',
  miss: 'cache miss, went to MariaDB',
  slow: 'query over 100 ms',
  err: 'error or 429',
};

export interface Wire {
  id: string; from: Cabinet; to: Cabinet;
  short: string;       // ≤ 7 characters, for the pixel label on the wall
  lane: 0 | 1 | 2;     // which lane of the cable duct under the floor
  sampled: boolean;    // a count read once a second, not individual requests
  measured: string;
}

// Lanes are shared only by wires whose spans do not overlap, so every dot on
// a lane belongs to one wire at any x.
export const WIRES: readonly Wire[] = [
  { id: 'nginx>api', from: 'nginx', to: 'api', short: 'ngx>api', lane: 2, sampled: false, measured: 'every request, by the API' },
  { id: 'api>redis', from: 'api', to: 'redis', short: 'api>rds', lane: 1, sampled: false, measured: 'every command, by the API' },
  { id: 'api>mariadb', from: 'api', to: 'mariadb', short: 'api>mdb', lane: 0, sampled: false, measured: 'every statement, by the API' },
  { id: 'nginx>wordpress', from: 'nginx', to: 'wordpress', short: 'ngx>wp', lane: 0, sampled: true, measured: 'php-fpm request counter, each second' },
  { id: 'wordpress>redis', from: 'wordpress', to: 'redis', short: 'wp>rds', lane: 1, sampled: true, measured: 'Redis INFO minus the API, each second' },
  { id: 'wordpress>mariadb', from: 'wordpress', to: 'mariadb', short: 'wp>mdb', lane: 0, sampled: true, measured: 'MariaDB Questions minus the API, each second' },
];

// Formatting shared by the pixel labels and the HTML table.
export const wireFmt = {
  // ≤ 5 characters
  rate: (r: number) => r < 1000 ? String(Math.round(r)) : r < 1e4 ? (r / 1e3).toFixed(1) + 'k' : r < 1e6 ? Math.round(r / 1e3) + 'k' : (r / 1e6).toFixed(1) + 'm',
  // ≤ 4 characters, in ms
  ms: (v: number | null) => v === null ? '-' : v < 10 ? v.toFixed(2) : v < 100 ? v.toFixed(1) : String(Math.round(v)),
  // how many requests one dot stands for; '' when it is one
  per: (p: number) => p === 1 ? '' : p < 1000 ? `x${p}` : `x${p / 1000}k`,
};
