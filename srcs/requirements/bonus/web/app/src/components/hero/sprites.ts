// srcs/requirements/bonus/web/app/src/components/hero/sprites.ts
// The sprite sheet, as text. One character per pixel: '.' is transparent,
// 0-9/a-f is a VGA palette index, 'A' is the sprite's accent colour and 'B'
// its light accent (resolved when rasterised). Frames are rasterised once to
// small canvases and cached; no PNG, no fetch, nothing outside the CSP.
export const PAL = [
  '#000000', '#0000aa', '#00aa00', '#00aaaa', '#aa0000', '#aa00aa', '#aa5500', '#aaaaaa',
  '#555555', '#5555ff', '#55ff55', '#55ffff', '#ff5555', '#ff55ff', '#ffff55', '#ffffff',
];
export type Frame = readonly string[];

// ── the 3×5 font (uppercase shapes; lowercase maps onto them) ─────────────
const FONT: Record<string, Frame> = {
  A: ['.#.', '#.#', '###', '#.#', '#.#'], B: ['##.', '#.#', '##.', '#.#', '##.'], C: ['.##', '#..', '#..', '#..', '.##'],
  D: ['##.', '#.#', '#.#', '#.#', '##.'], E: ['###', '#..', '##.', '#..', '###'], F: ['###', '#..', '##.', '#..', '#..'],
  G: ['.##', '#..', '#.#', '#.#', '.##'], H: ['#.#', '#.#', '###', '#.#', '#.#'], I: ['###', '.#.', '.#.', '.#.', '###'],
  J: ['..#', '..#', '..#', '#.#', '.#.'], K: ['#.#', '#.#', '##.', '#.#', '#.#'], L: ['#..', '#..', '#..', '#..', '###'],
  M: ['#.#', '###', '###', '#.#', '#.#'], N: ['##.', '#.#', '#.#', '#.#', '#.#'], O: ['.#.', '#.#', '#.#', '#.#', '.#.'],
  P: ['##.', '#.#', '##.', '#..', '#..'], Q: ['.#.', '#.#', '#.#', '##.', '.##'], R: ['##.', '#.#', '##.', '#.#', '#.#'],
  S: ['.##', '#..', '.#.', '..#', '##.'], T: ['###', '.#.', '.#.', '.#.', '.#.'], U: ['#.#', '#.#', '#.#', '#.#', '.#.'],
  V: ['#.#', '#.#', '#.#', '#.#', '.#.'], W: ['#.#', '#.#', '###', '###', '#.#'], X: ['#.#', '#.#', '.#.', '#.#', '#.#'],
  Y: ['#.#', '#.#', '.#.', '.#.', '.#.'], Z: ['###', '..#', '.#.', '#..', '###'],
  '0': ['###', '#.#', '#.#', '#.#', '###'], '1': ['.#.', '##.', '.#.', '.#.', '###'], '2': ['##.', '..#', '.#.', '#..', '###'],
  '3': ['###', '..#', '.##', '..#', '###'], '4': ['#.#', '#.#', '###', '..#', '..#'], '5': ['###', '#..', '##.', '..#', '##.'],
  '6': ['.##', '#..', '###', '#.#', '###'], '7': ['###', '..#', '.#.', '.#.', '.#.'], '8': ['###', '#.#', '###', '#.#', '###'],
  '9': ['###', '#.#', '###', '..#', '##.'],
  '-': ['...', '...', '###', '...', '...'], '.': ['...', '...', '...', '...', '.#.'], ':': ['...', '.#.', '...', '.#.', '...'],
  '/': ['..#', '..#', '.#.', '#..', '#..'], '%': ['#.#', '..#', '.#.', '#..', '#.#'], '!': ['.#.', '.#.', '.#.', '...', '.#.'],
  '?': ['##.', '..#', '.#.', '...', '.#.'], '>': ['#..', '.#.', '..#', '.#.', '#..'], '<': ['..#', '.#.', '#..', '.#.', '..#'],
  ' ': ['...', '...', '...', '...', '...'],
};

export function textWidth(s: string) { return s.length * 4 - 1; }

export function drawText(ctx: CanvasRenderingContext2D, text: string, x: number, y: number, color: number) {
  ctx.fillStyle = PAL[color];
  let cx = x;
  for (const ch of text.toUpperCase()) {
    const g = FONT[ch] ?? FONT['?'];
    for (let r = 0; r < 5; r++) for (let c = 0; c < 3; c++) if (g[r][c] === '#') ctx.fillRect(cx + c, y + r, 1, 1);
    cx += 4;
  }
}

// ── hand-drawn sprites ─────────────────────────────────────────────────────
// daemon: 8×12. Frames: idle, walk1, walk2, sit, arms (crossed), lookup
const DAEMON_HEAD = ['.A....A.', '.AA..AA.', '..AAAA..', '.AffffA.', '.Af0f0A.', '..AAAA..'];
const DAEMON_BODY = ['.AAAAAA.', 'AAAAAAAA', '.AAAAAA.'];
const daemon = (legs: Frame, head: Frame = DAEMON_HEAD, body: Frame = DAEMON_BODY): Frame => [...head, ...body, ...legs];
export const SHEET = {
  daemon: [
    daemon(['..A..A..', '..A..A..', '.AA..AA.']),                        // 0 idle
    daemon(['..A.A...', '.A...A..', 'AA...AA.']),                        // 1 walk
    daemon(['...A.A..', '..A...A.', '.AA...AA']),                        // 2 walk
    daemon(['AAAAAAAA', 'A......A', '........'], DAEMON_HEAD, ['.AAAAAA.', 'AAAAAAAA', 'AAAAAAAA']), // 3 sit
    daemon(['..A..A..', '..A..A..', '.AA..AA.'], DAEMON_HEAD, ['.AAAAAA.', '.A4AA4A.', '.AAAAAA.']), // 4 arms crossed
    daemon(['..A..A..', '..A..A..', '.AA..AA.'], ['.A....A.', '.AA..AA.', '..AAAA..', '.Af0f0A.', '.AffffA.', '..AAAA..']), // 5 look up
  ],
  // redis imp: 8×10 — idle, tap, nap
  imp: [
    ['.c....c.', '..cccc..', '.ceeceec', '.cccccc.', '..cccc..', '.cccccc.', 'c.cccc.c', '..c..c..', '..c..c..', '.cc..cc.'],
    ['.c....c.', '..cccc.c', '.ceeceec', '.cccccc.', '..ccccc.', '.cccccc.', 'c.cccc..', '..c..c..', '..c..c..', '.cc..cc.'],
    ['.c....c.', '..cccc..', '.cccccc.', '.c00c00.', '..cccc..', '.cccccc.', 'c.cccc.c', '..c..c..', '..c..c..', '.cc..cc.'],
  ],
  // mariadb sea lion: 12×6 — up, duck
  seal: [
    ['.....777....', '....77f7....', '.777777777..', '7777777777..', '.77777777.7.', '..77..77.77.'],
    ['............', '............', '....7777....', '.777777777..', '7777777777..', '.7777777777.'],
  ],
  // packet: 8×5 (stamp is 'A' so a flight can carry its origin colour)
  packet: [['88888888', '8ff77fA8', '8f7ff7f8', '8ffffff8', '88888888']],
  // rowset crate the daemon hauls back from mariadb: 8×6
  crate: [['66666666', '6ee66ee6', '66666666', '6ee66ee6', '66666666', '8......8']],
  // cat crossing the floor: 12×6, two frames (tail)
  cat: [
    ['0.0........0', '000.......0.', 'fff0.....0..', '0000000000..', '.00000000...', '.0.0..0.0...'],
    ['0.0.........', '000.......00', 'fff0.....0..', '0000000000..', '.00000000...', '.0.0..0.0...'],
  ],
  // smoke puff 8×8, four frames rising
  smoke: [
    ['........', '........', '........', '........', '........', '...77...', '..7777..', '...77...'],
    ['........', '........', '........', '...8....', '..787...', '.77777..', '..777...', '........'],
    ['........', '..8.....', '.787....', '.7787...', '..777...', '...7....', '........', '........'],
    ['.8..8...', '8.78....', '.787....', '..7.....', '........', '........', '........', '........'],
  ],
  // spark 6×6, two frames
  spark: [
    ['..e...', '.eee..', 'eefee.', '.eee..', '..e...', '......'],
    ['e..e.e', '.e.e..', '..f...', '.e.e..', 'e..e.e', '......'],
  ],
  // note pinned on the corkboard 6×6
  note: [['ceeeee', 'eeeeee', 'e8888e', 'eeeeee', 'e888ee', 'eeeeee']],
  // bell 6×7, two frames (ring)
  bell: [
    ['..ee..', '.eeee.', '.eeee.', '.eeee.', 'eeeeee', '..66..', '......'],
    ['..ee..', '.eeee.', 'eeeee.', 'eeeee.', 'eeeeee', '...66.', '......'],
  ],
  // coffee cup 6×7, two frames (steam)
  coffee: [
    ['.7..7.', '..7...', 'ffffff', 'f6666f', 'f6666ff', '.ffff.', '......'],
    ['..7.7.', '.7....', 'ffffff', 'f6666f', 'f6666ff', '.ffff.', '......'],
  ],
  // wall clock 12×12
  clock: [['...ffffff...', '..f......f..', '.f...8....f.', 'f....0.....f', 'f....0.....f', 'f....0.....f',
    'f....000...f', 'f..........f', '.f........f.', '..f......f..', '...ffffff...', '............']],
  // coffee machine 10×12
  machine: [['8888888888', '8777777778', '8700000078', '8700000078', '8777777778', '87777e7778', '8777777778',
    '8777ff7778', '8777ff7778', '8777777778', '8888888888', '.8......8.']],
} satisfies Record<string, Frame[]>;

export type SpriteName = keyof typeof SHEET;

// ── generated sprites ──────────────────────────────────────────────────────
// A rack cabinet 24×32. Rows: border, accent stripe (2), grey, a 7-row black
// display window the engine writes digits into, grey, five 3-row slots (a
// separator, a slit, a face the LED sits on), grey, border, feet (2).
//   LED of slot u sits at (3, 13 + 3u), 2×2 px.
export function cabinetFrame(): Frame {
  const rows: string[] = [];
  const line = (inner: string) => '.8' + inner + '8.';
  rows.push('.' + '8'.repeat(22) + '.');
  rows.push(line('A'.repeat(20)), line('A'.repeat(20)));
  rows.push(line('7'.repeat(20)));
  for (let i = 0; i < 7; i++) rows.push(line('0'.repeat(20)));
  rows.push(line('7'.repeat(20)));
  for (let u = 0; u < 5; u++) {
    rows.push(line('8'.repeat(20)));
    rows.push(line('7'.repeat(5) + '0'.repeat(12) + '7'.repeat(3)));
    rows.push(line('7'.repeat(20)));
  }
  rows.push(line('7'.repeat(20)), line('7'.repeat(20)));
  rows.push('.' + '8'.repeat(22) + '.');
  rows.push('.88' + '.'.repeat(18) + '88.', '.88' + '.'.repeat(18) + '88.');
  return rows;
}

// The corkboard 24×14: brown frame, grey cork, notes are drawn on it live.
export function boardFrame(): Frame {
  const rows: string[] = ['666666666666666666666666'];
  for (let i = 0; i < 12; i++) rows.push('6' + '7'.repeat(22) + '6');
  rows.push('666666666666666666666666');
  return rows;
}

// ── rasteriser ─────────────────────────────────────────────────────────────
const cache = new Map<string, HTMLCanvasElement>();

export function raster(key: string, frame: Frame, accent = 7, accentLight = 15): HTMLCanvasElement {
  const k = `${key}:${accent}:${accentLight}`;
  const hit = cache.get(k);
  if (hit) return hit;
  const w = Math.max(...frame.map((r) => r.length)), h = frame.length;
  const cv = document.createElement('canvas');
  cv.width = w; cv.height = h;
  const ctx = cv.getContext('2d')!;
  for (let y = 0; y < h; y++) {
    const row = frame[y];
    for (let x = 0; x < row.length; x++) {
      const ch = row[x];
      if (ch === '.') continue;
      const idx = ch === 'A' ? accent : ch === 'B' ? accentLight : ch === '#' ? 15 : parseInt(ch, 16);
      ctx.fillStyle = PAL[idx];
      ctx.fillRect(x, y, 1, 1);
    }
  }
  cache.set(k, cv);
  return cv;
}

export function sprite(name: SpriteName, frame = 0, accent = 7, accentLight = 15): HTMLCanvasElement {
  const frames = SHEET[name] as Frame[];
  const f = frames[Math.min(frame, frames.length - 1)];
  return raster(`${name}#${frame}`, f, accent, accentLight);
}
