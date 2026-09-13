// srcs/requirements/bonus/web/app/src/components/hero/Daemons.ts
//
// The machine room engine. One <canvas>, 320×160 logical pixels, scaled by an
// integer factor in device pixels so every pixel stays a square.
//
//   simulation  fixed 60 Hz step inside requestAnimationFrame; a slow tab drops
//               frames, never changes the outcome; at most 1 s is caught up
//   events      every movement is caused by something live.ts reported: a
//               counter delta, a flight status change, a health flip, a probe
//   pause       off screen (IntersectionObserver) or hidden tab: no frames
//   reduced     prefers-reduced-motion: no loop at all; one still frame is
//               drawn whenever the data changes
//   wires       dots in the cable duct under the floor are live traffic from
//               /api/v1/traffic (lib/traffic.ts): one per request, command or
//               statement, or one per N once a wire is busy. Their timing is
//               real; only their crossing speed is slowed for the eye
import { live, type LiveEvent, type ProbeResult } from '../../lib/live';
import { traffic, CROSS_MS, type TrafficFrame } from '../../lib/traffic';
import { WIRES, OUTCOMES, OUTCOME_COLOR, wireFmt } from '../../lib/wires';
import { CABINETS, fmt, type Cabinet, type Flight, type Stats } from '../../lib/api';
import { PAL, sprite, raster, cabinetFrame, boardFrame, drawText, textWidth, type SpriteName } from './sprites';
import snapshotStats from '../../data/stats.json';
import snapshotFlights from '../../data/flights.json';

const W = 320, H = 160, HZ = 60, STEP_MS = 1000 / HZ;
const CAB_TOP = 72, FLOOR_Y = 104, TRUNK_Y = 114, LABEL_Y = 119, FEET_Y = 148;
const CAB_X: Record<Cabinet, number> = { nginx: 16, wordpress: 66, mariadb: 116, redis: 166, web: 216, api: 266 };
// [stripe, light] palette indices per cabinet
const ACCENT: Record<Cabinet, [number, number]> = {
  nginx: [2, 10], wordpress: [1, 9], mariadb: [6, 14], redis: [4, 12], web: [3, 11], api: [5, 13],
};
const BOARD = { x: 191, y: 76 };        // corkboard, in the gap between redis and web
const CLOCK = { x: 100, y: 22 };
const BELL = { x: 114, y: 24 };
const MACHINE = { x: 302, y: FEET_Y - 12 };
const WALLBOARD = { x: 150, y: 22, w: 128, h: 28 };   // the flights that have not landed
const WIREPANEL = { x: 3, y: 21, w: 93, h: 47 };      // req/s, p50 and dot scale per wire
const LANE_Y = [FLOOR_Y + 2, FLOOR_Y + 5, FLOOR_Y + 8]; // the three lanes of the cable duct
const PENDING_MAX = 4000;
const IDLE_STEPS = 20 * HZ;             // 20 s without a notable event
// Requests from other clients per 5 s poll that still count as a quiet room:
// the API's own healthcheck (one per 10 s) and another open copy of this page
// (stats, flights and its probe: at most three per poll) never stop. Counting
// them made the idle gags impossible on a running stack.
const BACKGROUND_REQUESTS = 3;
const ERRAND_COOLDOWN = 20 * HZ;
const cx = (c: Cabinet) => CAB_X[c] + 12;

// ── DOM ───────────────────────────────────────────────────────────────────
const canvas = document.getElementById('room-canvas') as HTMLCanvasElement | null;
const wrap = document.getElementById('room-wrap');
if (canvas && wrap) boot(canvas, wrap);

function boot(canvas: HTMLCanvasElement, wrap: HTMLElement) {
  const ctx = canvas.getContext('2d', { alpha: false })!;
  const stateEl = document.getElementById('room-state');
  const tickEl = document.getElementById('room-tick');
  const captionEl = document.getElementById('room-caption');
  const pollbar = document.getElementById('pollbar');
  const motion = matchMedia('(prefers-reduced-motion: reduce)');
  let reduced = motion.matches;

  // ── world state ─────────────────────────────────────────────────────────
  let stats: Stats = snapshotStats as unknown as Stats;
  let flights: Flight[] = (snapshotFlights as unknown as { flights: Flight[] }).flights;
  let statsAt = 0;                     // browser time the stats arrived (0 = snapshot)
  let online: boolean | undefined;     // undefined until the first poll answers
  let offlineSince = 0;
  let probe: ProbeResult | undefined;
  let step = 0, lastNotable = 0, lastIdleGag = 0, lastErrand = -ERRAND_COOLDOWN, gagIndex = 0;
  let bellT = 0, notesShown = Math.min(6, stats.guestbook_entries);

  type Pose = 'stand' | 'walk' | 'sit' | 'arms' | 'lookup' | 'tap' | 'nap' | 'duck';
  type Task = { walk: number } | { pose: Pose; steps: number } | { run: () => void };
  interface Actor {
    kind: 'daemon' | 'imp' | 'seal' | 'cat'; accent: number;
    x: number; y: number; home: number; speed: number; facing: 1 | -1;
    pose: Pose; t: number; walkT: number; tasks: Task[]; carry?: SpriteName; gone?: boolean;
  }
  const actor = (kind: Actor['kind'], accent: number, x: number, y: number, speed = 1): Actor =>
    ({ kind, accent, x, y, home: x, speed, facing: 1, pose: 'stand', t: 0, walkT: 0, tasks: [] });
  const keeper: Record<'nginx' | 'wordpress' | 'web' | 'api', Actor> = {
    nginx: actor('daemon', ACCENT.nginx[1], CAB_X.nginx + 8, FEET_Y),
    wordpress: actor('daemon', ACCENT.wordpress[1], CAB_X.wordpress + 8, FEET_Y),
    web: actor('daemon', ACCENT.web[1], CAB_X.web + 8, FEET_Y),
    api: actor('daemon', ACCENT.api[1], CAB_X.api + 8, FEET_Y),
  };
  const imp = actor('imp', 4, CAB_X.redis + 8, CAB_TOP);
  const seal = actor('seal', 7, CAB_X.mariadb + 6, CAB_TOP);
  const actors: Actor[] = [keeper.nginx, keeper.wordpress, keeper.web, keeper.api, imp, seal];

  interface Fx { kind: 'smoke' | 'spark' | 'z' | 'stamp' | 'bubble'; x: number; y: number; t: number; life: number; text?: string; color?: number; on?: Actor }
  const fx: Fx[] = [];
  const addFx = (f: Omit<Fx, 't'>) => { fx.push({ ...f, t: f.life }); if (fx.length > 40) fx.shift(); };

  // LED activity: each cabinet has four activity LEDs (slots 1..4); pulses
  // wait in a queue and light a free slot for 18 steps.
  const leds: Record<Cabinet, { queue: number[]; slots: { color: number; t: number }[]; last?: number }> =
    Object.fromEntries(CABINETS.map((c) => [c, { queue: [], slots: [0, 1, 2, 3].map(() => ({ color: 0, t: 0 })) }])) as any;
  const pulse = (c: Cabinet, n: number, color: number) => {
    const l = leds[c]; l.last = color;
    for (let i = 0; i < Math.min(n, 8); i++) if (l.queue.length < 16) l.queue.push(color);
  };
  const launches = new Map<number, number>(); // flight id → launch steps left

  // ── background: everything that does not move, drawn once per lighting ──
  const bg = document.createElement('canvas');
  bg.width = W; bg.height = H;
  function paintBackground() {
    const g = bg.getContext('2d')!;
    const lit = online !== false;
    g.fillStyle = PAL[0]; g.fillRect(0, 0, W, FLOOR_Y);
    g.fillStyle = PAL[1];
    for (let y = 8; y < FLOOR_Y - 8; y += 8) for (let x = 4; x < W; x += 8) g.fillRect(x, y, 1, 1);
    g.fillStyle = PAL[8]; g.fillRect(0, FLOOR_Y - 4, W, 4);                 // skirting
    g.fillStyle = PAL[lit ? 8 : 0]; g.fillRect(0, FLOOR_Y, W, H - FLOOR_Y);  // floor
    g.fillStyle = PAL[lit ? 0 : 8];
    for (let y = FLOOR_Y + 16; y < H; y += 16) g.fillRect(0, y, W, 1);
    for (let y = FLOOR_Y; y < H; y += 16) for (let x = (y / 16) % 2 ? 0 : 16; x < W; x += 32) g.fillRect(x, y, 1, 16);
    // cable duct: three lanes of live traffic, under the drops and above the flight trunk
    g.fillStyle = PAL[0]; g.fillRect(cx('nginx') - 3, FLOOR_Y + 1, cx('api') - cx('nginx') + 7, 9);
    // cable trunk and the drop from every cabinet
    g.fillStyle = PAL[lit ? 3 : 8];
    g.fillRect(cx('nginx'), TRUNK_Y, cx('api') - cx('nginx') + 1, 1);
    for (const c of CABINETS) g.fillRect(cx(c), FLOOR_Y, 1, TRUNK_Y - FLOOR_Y);
    for (const c of CABINETS) {
      const [stripe, light] = ACCENT[c];
      g.drawImage(raster(`cab-${lit}`, cabinetFrame(), lit ? stripe : 8), CAB_X[c], CAB_TOP);
      const w = textWidth(c);
      g.fillStyle = PAL[0]; g.fillRect(cx(c) - Math.ceil(w / 2) - 2, LABEL_Y - 2, w + 4, 9);
      drawText(g, c, cx(c) - Math.ceil(w / 2), LABEL_Y, lit ? light : 8);
    }
    g.drawImage(raster('board', boardFrame()), BOARD.x, BOARD.y);
    g.drawImage(sprite('clock'), CLOCK.x, CLOCK.y);
    g.drawImage(sprite('machine'), MACHINE.x, MACHINE.y);
    drawText(g, 'machine room', 4, 4, 11);
    g.fillStyle = PAL[8]; g.fillRect(WALLBOARD.x, WALLBOARD.y, WALLBOARD.w, WALLBOARD.h);
    g.fillStyle = PAL[0]; g.fillRect(WALLBOARD.x + 1, WALLBOARD.y + 1, WALLBOARD.w - 2, WALLBOARD.h - 2);
    drawText(g, 'departures', WALLBOARD.x + 3, WALLBOARD.y + 3, lit ? 14 : 8);
    g.fillStyle = PAL[8]; g.fillRect(WIREPANEL.x, WIREPANEL.y, WIREPANEL.w, WIREPANEL.h);
    g.fillStyle = PAL[0]; g.fillRect(WIREPANEL.x + 1, WIREPANEL.y + 1, WIREPANEL.w - 2, WIREPANEL.h - 2);
    drawText(g, 'wires', WIREPANEL.x + 3, WIREPANEL.y + 3, lit ? 14 : 8);
    drawText(g, '/s', wireCol(11, '/s'), WIREPANEL.y + 3, 8);
    drawText(g, 'ms', wireCol(16, 'ms'), WIREPANEL.y + 3, 8);
    drawText(g, 'dot', wireCol(21, 'dot'), WIREPANEL.y + 3, 8);
  }
  // x for text right-aligned so that its last character sits in column `end`
  function wireCol(end: number, text: string) { return WIREPANEL.x + 3 + (end + 1 - text.length) * 4; }

  // ── events → actions ────────────────────────────────────────────────────
  const busy = (a: Actor) => a.tasks.length > 0 || a.t > 0;
  const bubble = (on: Actor, text: string, color: number, life = 90) => addFx({ kind: 'bubble', x: 0, y: 0, text, color, life, on });

  function onStats(s: Stats, d: Record<string, number>, first: boolean) {
    stats = s; statsAt = Date.now();
    notesShown = Math.min(notesShown, 6, s.guestbook_entries);
    if (first) { notesShown = Math.min(6, s.guestbook_entries); return; }
    if (d.http_requests) { pulse('nginx', d.http_requests, 10); pulse('api', d.http_requests, 10); }
    if (d.cache_hit) { pulse('redis', d.cache_hit, 10); if (!busy(imp)) imp.tasks.push({ pose: 'tap', steps: 36 }); }
    if (d.db_query) pulse('mariadb', d.db_query, 11);
    if (d.cache_miss) { pulse('redis', d.cache_miss, 14); errand(); }
    if (d.db_slow) {
      addFx({ kind: 'smoke', x: CAB_X.mariadb + 16, y: CAB_TOP - 8, life: 48 });
      seal.tasks = [{ pose: 'duck', steps: 60 }];
    }
    if (d.http_errors) {
      pulse('nginx', d.http_errors, 12);
      addFx({ kind: 'spark', x: CAB_X.nginx + 18, y: CAB_TOP - 4, life: 24 });
      if (!busy(keeper.nginx)) keeper.nginx.tasks.push({ pose: 'lookup', steps: 40 });
    }
    if (d.rate_limited) {
      pulse('api', 6, 14);
      if (!busy(keeper.api)) keeper.api.tasks.push({ pose: 'arms', steps: 90 });
      bubble(keeper.api, '429', 14);
    }
    if (d.minute_ticks) {
      bellT = 48;
      for (const a of Object.values(keeper)) if (!busy(a)) a.tasks.push({ pose: 'lookup', steps: 40 });
    }
    if (d.guestbook_post) pinNote(s.guestbook_entries);
    if (d.flight_created || d.guestbook_post || d.rate_limited || d.db_slow || d.http_errors || d.foreign_requests > BACKGROUND_REQUESTS) lastNotable = step;
  }

  // a cache miss: the api daemon walks to MariaDB and hauls the rowset back to
  // Redis. At most one errand per 20 s; the other misses show as LEDs.
  function errand() {
    const a = keeper.api;
    if (busy(a) || online === false || step - lastErrand < ERRAND_COOLDOWN) return;
    lastErrand = step;
    a.tasks.push(
      { walk: CAB_X.redis + 8 }, { pose: 'lookup', steps: 12 },
      { walk: CAB_X.mariadb + 8 }, { pose: 'tap', steps: 24 },
      { run: () => { seal.tasks = [{ pose: 'duck', steps: 10 }]; pulse('mariadb', 3, 11); a.carry = 'crate'; } },
      { walk: CAB_X.redis + 8 },
      { run: () => { a.carry = undefined; pulse('redis', 2, 10); imp.tasks = [{ pose: 'tap', steps: 30 }]; } },
      { walk: a.home },
    );
  }

  function pinNote(total: number) {
    const a = keeper.web;
    a.tasks.push(
      { walk: BOARD.x + 8 }, { pose: 'lookup', steps: 24 },
      { run: () => { notesShown = Math.min(6, total); } },
      { pose: 'stand', steps: 8 }, { walk: a.home },
    );
  }

  function onFlights(list: Flight[], added: Flight[], changed: Flight[], first: boolean) {
    flights = list;
    if (first) return;
    for (const f of added) { launches.set(f.id, 30); pulse(f.origin, 2, 11); lastNotable = step; }
    for (const f of changed) {
      if (f.status === 'landed') {
        addFx({ kind: 'stamp', x: cx(f.destination), y: TRUNK_Y - 12, life: 90, text: f.callsign.slice(4), color: 10 });
        pulse(f.destination, 3, 10);
      } else if (f.status === 'diverted') {
        addFx({ kind: 'spark', x: cx(f.origin) - 3, y: TRUNK_Y - 6, life: 24 });
      }
    }
  }

  function onHealth(ok: boolean) {
    const was = online;
    online = ok;
    if (!ok && was !== false) offlineSince = Date.now();
    if (was !== ok) {
      paintBackground();
      for (const a of actors) { a.tasks = []; a.t = 0; a.carry = undefined; }
    }
  }

  function idleGag() {
    const g = gagIndex++ % 3;
    if (g === 0) {
      imp.tasks.push({ pose: 'nap', steps: 240 });
      for (let i = 0; i < 3; i++) addFx({ kind: 'z', x: imp.x + 8 + i * 3, y: imp.y - 12 - i * 4, life: 80 + i * 40 });
    } else if (g === 1) {
      const cat = actor('cat', 0, -14, FEET_Y + 8, 0.75);
      cat.tasks.push({ walk: W + 14 }, { run: () => { cat.gone = true; } });
      actors.push(cat);
    } else {
      const a = keeper.wordpress;
      if (busy(a)) return;
      a.tasks.push(
        { walk: MACHINE.x - 9 }, { pose: 'tap', steps: 40 }, { run: () => { a.carry = 'coffee'; } },
        { walk: a.home }, { pose: 'stand', steps: 90 }, { run: () => { a.carry = undefined; } },
      );
    }
  }

  // ── wires: frames → dots ────────────────────────────────────────────────
  // A dot is scheduled at the time its request happened (the frame's arrival
  // plus the event's offset in the frame), or spread evenly over the window
  // when the frame carries counts only. With one dot per `per` requests, each
  // outcome carries its own remainder, so colours keep their true proportions
  // and a rare error still shows up, a little later.
  interface Dot { w: number; o: number; at: number }
  let pending: Dot[] = [];
  let dots: Dot[] = [];
  let carry = WIRES.map(() => [0, 0, 0, 0, 0]);
  const wireX = WIRES.map((w) => [cx(w.from), cx(w.to)]);

  function onTraffic(frame: TrafficFrame, at: number) {
    if (reduced || !running) return;
    const added: Dot[] = [];
    WIRES.forEach((w, i) => {
      const lf = frame.links[w.id];
      if (!lf || lf.err || !lf.n) return;
      const per = traffic.wires[w.id].per, c = carry[i];
      if (lf.e && lf.e.length === lf.n) {
        for (const code of lf.e) {
          const o = code & 7;
          if (++c[o] >= per) { c[o] -= per; added.push({ w: i, o, at: at + (code >> 3) }); }
        }
        return;
      }
      const dt = lf.dt ?? 200;
      OUTCOMES.forEach((name, o) => {
        const total = c[o] + (lf.k?.[name] ?? 0);
        const d = Math.floor(total / per);
        c[o] = total - d * per;
        for (let j = 0; j < d; j++) added.push({ w: i, o, at: at + ((j + 0.5) / d) * dt });
      });
    });
    if (!added.length) return;
    pending = pending.concat(added).sort((a, b) => a.at - b.at);
    if (pending.length > PENDING_MAX) pending = pending.slice(-PENDING_MAX);
  }

  function clearDots() { pending = []; dots = []; carry = WIRES.map(() => [0, 0, 0, 0, 0]); }

  function drawDots(now: number) {
    let due = 0;
    while (due < pending.length && pending[due].at <= now) due++;
    if (due) dots = dots.concat(pending.splice(0, due));
    let keep = 0;
    for (const d of dots) if (now - d.at < CROSS_MS) dots[keep++] = d;
    dots.length = keep;
    if (!dots.length) return;
    for (let o = 0; o < OUTCOMES.length; o++) {
      ctx.fillStyle = PAL[OUTCOME_COLOR[o]];
      for (const d of dots) {
        if (d.o !== o) continue;
        const [x0, x1] = wireX[d.w];
        ctx.fillRect(Math.round(x0 + ((x1 - x0) * (now - d.at)) / CROSS_MS) - 1, LANE_Y[WIRES[d.w].lane], 2, 1);
      }
    }
  }

  function drawWirePanel(lit: boolean) {
    const on = traffic.state === 'live';
    WIRES.forEach((w, i) => {
      const y = WIREPANEL.y + 3 + 6 * (i + 1);
      const s = traffic.wires[w.id];
      drawText(ctx, w.short, WIREPANEL.x + 3, y, !lit ? 8 : w.sampled ? 3 : 11);
      const r = !on ? '-' : s.err ? 'down' : wireFmt.rate(s.rate);
      drawText(ctx, r, wireCol(11, r), y, !lit || !on ? 8 : s.err ? 12 : 15);
      const ms = w.sampled ? '1s' : on ? wireFmt.ms(s.p50) : '-';
      drawText(ctx, ms, wireCol(16, ms), y, !lit || w.sampled ? 8 : 10);
      const per = on ? wireFmt.per(s.per) : '';
      if (per) drawText(ctx, per, wireCol(21, per), y, lit ? 14 : 8);
    });
  }

  // ── simulation step ─────────────────────────────────────────────────────
  function restPose(a: Actor): Pose {
    if (online !== false || a.kind === 'cat') return 'stand';
    return a.kind === 'daemon' ? 'sit' : a.kind === 'imp' ? 'nap' : 'duck';
  }
  function stepActor(a: Actor) {
    if (a.t > 0) { a.t--; return; }
    const task = a.tasks[0];
    if (!task) { a.pose = restPose(a); return; }
    if ('walk' in task) {
      const dx = task.walk - a.x;
      if (Math.abs(dx) <= a.speed) { a.x = task.walk; a.tasks.shift(); a.pose = restPose(a); }
      else { a.x += Math.sign(dx) * a.speed; a.facing = dx > 0 ? 1 : -1; a.pose = 'walk'; a.walkT++; }
    } else if ('pose' in task) { a.pose = task.pose; a.t = task.steps; a.tasks.shift(); }
    else { a.tasks.shift(); task.run(); }
  }
  function update() {
    step++;
    for (const a of actors) stepActor(a);
    for (let i = actors.length - 1; i >= 0; i--) if (actors[i].gone) actors.splice(i, 1);
    for (const f of fx) f.t--;
    for (let i = fx.length - 1; i >= 0; i--) if (fx[i].t <= 0) fx.splice(i, 1);
    for (const c of CABINETS) {
      const l = leds[c];
      for (const s of l.slots) {
        if (s.t > 0) s.t--;
        else if (l.queue.length) { s.color = l.queue.shift()!; s.t = 18; }
      }
    }
    for (const [id, t] of launches) { if (t <= 1) launches.delete(id); else launches.set(id, t - 1); }
    if (bellT > 0) bellT--;
    if (online && step - lastNotable > IDLE_STEPS && step - lastIdleGag > IDLE_STEPS) { lastIdleGag = step; idleGag(); }
  }

  // ── rendering ───────────────────────────────────────────────────────────
  function blit(img: HTMLCanvasElement, x: number, y: number, flip = false) {
    x = Math.round(x); y = Math.round(y);
    if (!flip) { ctx.drawImage(img, x, y); return; }
    ctx.save(); ctx.translate(x + img.width, y); ctx.scale(-1, 1); ctx.drawImage(img, 0, 0); ctx.restore();
  }
  function px(x: number, y: number, w: number, h: number, color: number) { ctx.fillStyle = PAL[color]; ctx.fillRect(x, y, w, h); }

  function windowText(c: Cabinet): string {
    const k = stats.counters;
    switch (c) {
      case 'nginx': return fmt.compact(k.http_requests ?? 0);
      case 'wordpress': return probe ? (probe.wordpress >= 200 && probe.wordpress < 400 ? 'FPM' : String(probe.wordpress || 'DOWN')) : 'FPM';
      case 'mariadb': return fmt.compact(k.db_query ?? 0);
      case 'redis': { const t = (k.cache_hit ?? 0) + (k.cache_miss ?? 0); return t ? Math.round((100 * k.cache_hit) / t) + '%' : '--'; }
      case 'web': return probe ? String(probe.web || 'DOWN') : 'HTML';
      case 'api': return stats.gauges.inflight > 1 ? String(stats.gauges.inflight) : fmt.compact(stats.gauges.uptime_s) + 'S';
    }
  }
  function healthOf(c: Cabinet): number {
    if (online === undefined) return 8;
    if (!online) return c === 'nginx' || c === 'web' ? 14 : 12;
    const h = probe?.health;
    switch (c) {
      case 'mariadb': return h ? (h.mariadb.ok ? 10 : 12) : 10;
      case 'redis': return h ? (h.redis.ok ? 10 : 12) : (stats.gauges.redis_connected ? 10 : 12);
      case 'wordpress': return probe ? (probe.wordpress >= 200 && probe.wordpress < 400 ? 10 : 12) : 8;
      case 'web': return probe ? (probe.web === 200 ? 10 : 12) : 10;
      default: return 10;
    }
  }

  function actorFrame(a: Actor): [SpriteName, number] {
    const walk = (every: number) => (Math.floor(a.walkT / every) % 2) + 1;
    switch (a.kind) {
      case 'daemon': return ['daemon', a.pose === 'walk' ? walk(8) : a.pose === 'sit' ? 3 : a.pose === 'arms' ? 4
        : a.pose === 'lookup' ? 5 : a.pose === 'tap' ? (Math.floor(step / 6) % 2 ? 5 : 0) : 0];
      case 'imp': return ['imp', a.pose === 'nap' ? 2 : a.pose === 'tap' ? Math.floor(step / 6) % 2 : 0];
      case 'seal': return ['seal', a.pose === 'duck' ? 1 : 0];
      case 'cat': return ['cat', Math.floor(a.walkT / 10) % 2];
    }
  }

  function render() {
    const lit = online !== false;
    const now = live.now();
    ctx.drawImage(bg, 0, 0);

    // wall: API state, uptime extrapolated between polls, the clock
    const up = stats.gauges.uptime_s + (statsAt ? (Date.now() - statsAt) / 1000 : 0);
    const state = online === undefined ? 'waiting' : online ? `api ok ${stats.source}` : `offline ${fmt.mmss((Date.now() - offlineSince) / 1000)}`;
    const sw = textWidth(state);
    drawText(ctx, state, W - sw - 4, 4, online === undefined ? 7 : online ? 10 : 12);
    const us = statsAt ? `up ${fmt.uptime(up)}` : 'snapshot';
    drawText(ctx, us, W - textWidth(us) - 4, 12, 7);
    const secIntoMinute = 60 - stats.next_minute_tick_s + (statsAt ? (Date.now() - statsAt) / 1000 : 0);
    const ang = ((secIntoMinute % 60) / 60) * Math.PI * 2;
    for (let r = 1; r <= 4; r++) px(CLOCK.x + 5 + Math.round(Math.sin(ang) * r), CLOCK.y + 6 - Math.round(Math.cos(ang) * r), 1, 1, 12);
    blit(sprite('bell', bellT > 0 && !reduced ? Math.floor(bellT / 6) % 2 : 0), BELL.x, BELL.y);

    // wall departures board: newest two flights still in the air or at the gate
    const open = flights.filter((f) => f.status !== 'landed').slice(0, 2);
    if (!open.length) drawText(ctx, 'all landed', WALLBOARD.x + 3, WALLBOARD.y + 11, 8);
    open.forEach((f, i) => {
      const y = WALLBOARD.y + 11 + i * 8;
      drawText(ctx, `${f.callsign.slice(4)} ${f.origin.slice(0, 5)}>${f.destination.slice(0, 5)}`, WALLBOARD.x + 3, y, lit ? 15 : 8);
      const st = f.status === 'en-route' ? 'enrt' : f.status === 'boarding' ? 'brd' : 'div';
      drawText(ctx, st, WALLBOARD.x + WALLBOARD.w - 3 - textWidth(st), y, !lit ? 8 : f.status === 'en-route' ? 10 : f.status === 'boarding' ? 14 : 12);
    });

    // cabinet windows and LEDs
    for (const c of CABINETS) {
      const t = windowText(c).slice(0, 5);
      drawText(ctx, t, CAB_X[c] + 2 + Math.floor((20 - textWidth(t)) / 2), CAB_TOP + 5, lit ? 10 : 8);
      px(CAB_X[c] + 3, CAB_TOP + 13, 2, 2, healthOf(c));
      const l = leds[c];
      for (let u = 1; u <= 4; u++) {
        const s = l.slots[u - 1];
        const on = reduced ? u === 1 && l.last !== undefined : s.t > 6;
        px(CAB_X[c] + 3, CAB_TOP + 13 + 3 * u, 2, 2, lit && on ? (reduced ? l.last! : s.color) : 0);
      }
    }

    // notes on the corkboard, one per guestbook entry (the board holds six)
    for (let i = 0; i < notesShown; i++) blit(sprite('note'), BOARD.x + 2 + (i % 3) * 7, BOARD.y + 1 + Math.floor(i / 3) * 6);

    // live traffic in the duct, under the flight packets
    if (!reduced && running) drawDots(performance.now());
    drawWirePanel(lit);

    // packets: where the flight really is, from its status and its timestamps
    const parked = new Map<Cabinet, number>();
    for (const f of flights) {
      if (f.status === 'landed') continue;
      const o = cx(f.origin), d = cx(f.destination), dir = d >= o ? 1 : -1;
      const img = sprite('packet', 0, f.status === 'diverted' ? 12 : ACCENT[f.origin][1]);
      if (f.status === 'en-route') {
        const p = Math.min(1, Math.max(0, (now - Date.parse(f.created_at) - 30000) / 150000));
        const x = o + (d - o) * p - 4;
        blit(img, x, TRUNK_Y - 2);
        drawText(ctx, f.callsign.slice(4), Math.round(x) - 2, TRUNK_Y - 9, 11);
        continue;
      }
      const k = parked.get(f.origin) ?? 0; parked.set(f.origin, k + 1);
      if (k > 3) continue;
      const lt = launches.get(f.id);
      if (lt !== undefined && !reduced) { blit(img, o - 4, TRUNK_Y - 2 - (lt / 30) * 20); continue; }
      const dim = f.status === 'boarding' && !reduced && Math.floor(step / 30) % 2 === 1;
      const x = o - 4 + dir * (8 + k * 10);
      blit(dim ? sprite('packet', 0, 8) : img, x, TRUNK_Y - 2);
      if (f.status === 'diverted') drawText(ctx, 'x', x + 10, TRUNK_Y - 2, 12);
    }

    // actors, back to front
    for (const a of [...actors].sort((p, q) => p.y - q.y)) {
      const [name, frame] = actorFrame(a);
      const img = sprite(name, frame, a.accent);
      const top = a.y - img.height;
      blit(img, a.x, top, a.kind === 'cat' ? a.facing === 1 : false);
      if (a.carry) blit(sprite(a.carry, Math.floor(step / 20) % 2), a.x + 1, top - 7);
    }

    // effects
    if (!reduced) for (const f of fx) {
      const age = f.life - f.t;
      switch (f.kind) {
        case 'smoke': blit(sprite('smoke', Math.min(3, Math.floor((age / f.life) * 4))), f.x, f.y - age / 6); break;
        case 'spark': blit(sprite('spark', Math.floor(age / 4) % 2), f.x, f.y); break;
        case 'z': if (age > 0) drawText(ctx, 'z', f.x + Math.floor(age / 20), f.y - Math.floor(age / 8), 15); break;
        case 'stamp': if (Math.floor(age / 8) % 2 === 0) drawText(ctx, f.text!, f.x - 7, f.y, f.color!); break;
        case 'bubble': {
          if (!f.on) break;
          const w = textWidth(f.text!) + 4, bx = Math.round(f.on.x + 4 - w / 2), by = Math.round(f.on.y - 22);
          px(bx, by, w, 9, 15); px(bx + 1, by + 1, w - 2, 7, 0); drawText(ctx, f.text!, bx + 2, by + 2, f.color!);
          break;
        }
      }
    }
  }

  // ── text around the canvas ──────────────────────────────────────────────
  function describe() {
    const f = stats.flights;
    const api = online === undefined ? 'waiting for the API' : online ? 'API reachable' : 'API offline';
    const text = `Machine room: six cabinets. ${api}. ${f.boarding} boarding, ${f['en-route']} en route, ${f.landed} landed` +
      `${f.diverted ? `, ${f.diverted} diverted` : ''}. ${fmt.int(stats.counters.http_requests ?? 0)} API requests, ` +
      `cache hit rate ${fmt.pct(stats.counters.cache_hit ?? 0, (stats.counters.cache_hit ?? 0) + (stats.counters.cache_miss ?? 0))}.`;
    canvas.setAttribute('aria-label', `${text} Dots on the wires under the floor are live traffic; the wires table below gives the numbers.`);
    if (captionEl) captionEl.textContent = statsAt ? `${text} Last poll ${new Date(statsAt).toTimeString().slice(0, 8)}.` : text + ' (build-time snapshot)';
  }
  function titleBar() {
    if (stateEl) stateEl.textContent = online === undefined ? 'waiting' : online ? 'live' : `stale ${fmt.mmss((Date.now() - live.lastGoodAt) / 1000)}`;
    if (tickEl) tickEl.textContent = fmt.mmss(stats.next_minute_tick_s - (statsAt ? (Date.now() - statsAt) / 1000 : 0));
  }
  setInterval(titleBar, 1000);

  // ── sizing: integer device-pixel scale ─────────────────────────────────
  let scale = 0;
  function resize() {
    const dpr = window.devicePixelRatio || 1;
    const s = Math.max(1, Math.floor((wrap.clientWidth * dpr) / W));
    if (s === scale && canvas.width === W * s) return;
    scale = s;
    canvas.width = W * s; canvas.height = H * s;
    canvas.style.width = `${(W * s) / dpr}px`; canvas.style.height = `${(H * s) / dpr}px`;
    ctx.setTransform(s, 0, 0, s, 0, 0);
    ctx.imageSmoothingEnabled = false;
    // shown only once it has its final size: appearing is not a layout shift, growing is
    canvas.hidden = false;
    render();
  }

  // ── loop ────────────────────────────────────────────────────────────────
  let running = false, raf = 0, last = 0, acc = 0, inView = true;
  function frame(ts: number) {
    if (!running) return;
    if (!last) last = ts;
    acc += ts - last; last = ts;
    let n = 0;
    while (acc >= STEP_MS && n < HZ) { update(); acc -= STEP_MS; n++; }
    if (n === HZ) acc = 0;           // more than a second behind: old events are not news
    render();
    raf = requestAnimationFrame(frame);
  }
  // The stream is held while any of the room panel is on screen (the canvas,
  // or the wires table under it), reduced motion included: the labels still
  // need it, only the dots do not. The animation needs the canvas itself.
  let lease: (() => void) | undefined;
  let panelInView = true;
  function sync() {
    const shown = document.visibilityState === 'visible';
    if (shown && panelInView && !lease) lease = traffic.acquire();
    else if (!(shown && panelInView) && lease) { lease(); lease = undefined; }
    const want = !reduced && inView && shown;
    if (want === running) return;
    running = want;
    clearDots();
    if (running) { last = 0; acc = 0; raf = requestAnimationFrame(frame); } else { cancelAnimationFrame(raf); render(); }
  }

  new IntersectionObserver((es) => { inView = es.some((e) => e.isIntersecting); sync(); }).observe(canvas);
  const panel = document.getElementById('room');
  if (panel) new IntersectionObserver((es) => { panelInView = es.some((e) => e.isIntersecting); sync(); }).observe(panel);
  document.addEventListener('visibilitychange', sync);
  motion.addEventListener('change', () => { reduced = motion.matches; sync(); render(); });
  new ResizeObserver(resize).observe(wrap);

  // clicking a cabinet opens the palette ready to dispatch from it
  const cabinetAt = (ev: MouseEvent): Cabinet | undefined => {
    const r = canvas.getBoundingClientRect();
    const x = ((ev.clientX - r.left) / r.width) * W, y = ((ev.clientY - r.top) / r.height) * H;
    if (y < CAB_TOP - 12 || y > LABEL_Y + 6) return undefined;
    return CABINETS.find((c) => x >= CAB_X[c] && x <= CAB_X[c] + 24);
  };
  canvas.addEventListener('click', (ev) => {
    const c = cabinetAt(ev);
    if (c) document.dispatchEvent(new CustomEvent('lab:palette', { detail: `dispatch ${c} ` }));
  });
  canvas.addEventListener('mousemove', (ev) => { canvas.style.cursor = cabinetAt(ev) ? 'pointer' : 'default'; });

  // ── the wires table under the canvas, once a second ─────────────────────
  const wiresEl = document.getElementById('room-wires');
  const wireCells = WIRES.map((w) => {
    const row = document.querySelector<HTMLTableRowElement>(`tr[data-wire="${w.id}"]`);
    return { w, rate: row?.querySelector<HTMLElement>('[data-rate]'), p50: row?.querySelector<HTMLElement>('[data-p50]'), per: row?.querySelector<HTMLElement>('[data-per]') };
  });
  function wireTable() {
    const on = traffic.state === 'live';
    if (wiresEl) wiresEl.textContent = traffic.state === 'connecting' ? 'connecting' : traffic.state;
    for (const { w, rate, p50, per } of wireCells) {
      const s = traffic.wires[w.id];
      if (rate) {
        rate.textContent = !on ? '—' : s.err ? 'down' : fmt.int(s.rate);
        rate.title = s.err ? `sample failed: ${s.err}` : '';
      }
      if (p50 && !w.sampled) p50.textContent = on && s.p50 !== null ? `${wireFmt.ms(s.p50)} ms` : '—';
      if (per) per.textContent = on ? fmt.int(s.per) : '—';
    }
  }
  setInterval(wireTable, 1000);

  let lastStill = 0;
  traffic.on((ev) => {
    if (ev.type === 'frame') onTraffic(ev.frame, ev.at);
    else { wireTable(); if (ev.state !== 'live') clearDots(); }
    // not animating (reduced motion): a still frame with fresh labels, at most once a second
    if (!running && (ev.type === 'state' || performance.now() - lastStill > 1000)) { lastStill = performance.now(); render(); }
  });

  live.on((ev: LiveEvent) => {
    if (ev.type === 'stats') {
      onStats(ev.stats, ev.delta, ev.first);
      if (pollbar && !reduced) { pollbar.classList.remove('run'); void pollbar.offsetWidth; pollbar.classList.add('run'); }
    } else if (ev.type === 'flights') onFlights(ev.flights, ev.added, ev.changed, ev.first);
    else if (ev.type === 'probe') probe = ev.probe;
    else if (ev.type === 'health') onHealth(ev.ok);
    describe(); titleBar();
    if (!running) render();
  });

  paintBackground();
  resize();
  describe(); titleBar();
  sync();
}
