# The machine room — design

`https://dlesieur.42.fr/lab/` is a live pixel-art diorama of the Inception stack. Every
cabinet on the floor is a real container; every light, packet and little daemon is driven by
numbers that `/api/v1/stats` actually returned in the last five seconds. Nothing on the screen
is decorative fiction: if Redis stops answering, the imp on the Redis cabinet goes dark, and the
status bar says so.

This document is the contract the implementation is measured against. Wireframe first, then the
rules that are not negotiable, then a self-critique of the one cliché this concept is closest to.

## 1. Home page wireframe

```
┌ status ─────────────────────────────────────────────────────────────────────────────────┐
│ [1:room] 2:flights 3:guestbook 4:about      api ● ok redis   req 1 204   hit 97%   18:54 │
└──────────────────────────────────────────────────────────────────────────────────────────┘
╔═ machine room ═ live ═ wires live ═ next tick 00:48 ═══════════════════════════════════════╗
║                                                                                          ║
║   ┌────────┐      ┌──────────┐      ┌──────────┐         ┌────────┐     ┌────────┐       ║
║   │ nginx  │ ──►  │wordpress │ ──►  │ mariadb  │         │  web   │     │  api   │       ║
║   │ ▪▪▪▪   │      │ ▪▪▪▪     │      │ ▪▪▪▪     │  ┌─────►│ ▪▪     │     │ ▪▪▪    │       ║
║   │ 1.28.3 │      │ php 8.4  │      │ 11.x     │  │      │        │     │ node24 │       ║
║   └────────┘      └──────────┘      └────┬─────┘  │      └────────┘     └───┬────┘       ║
║       │ 443              ▲               │        │                          │           ║
║       └──────────────────┼───────────────┼────────┘   ┌──────────┐           │           ║
║                          └───────────────┼────────────│  redis   │◄──────────┘           ║
║          ☺ ═►  packet PKT-0012           │            │ ▪▪ imp   │                       ║
║                                          ▼            └──────────┘                       ║
║   ────────────────────────────── floor ──────────────────────────────────────────────    ║
╚══════════════════════════════════════════════════════════════════════════════════════════╝
┌ cabinets ────────────────────────────┐ ┌ counters ─────────────────────────────────────┐
│ nginx     ● 1.28.3   443/tcp   edge  │ │ http_requests   1 204   ████████████░░░  +12/s │
│ wordpress ● php 8.4  fpm :9000       │ │ cache_hit         867   ██████████░░░░░        │
│ mariadb   ● 11.x     :3306  lab db   │ │ cache_miss         37   █░░░░░░░░░░░░░░        │
│ redis     ● 8.4.2    :6379  hot keys │ │ db_query           41   █░░░░░░░░░░░░░░        │
│ web       ● nginx    :8080  /lab/    │ │ rate_limited        0                          │
│ api       ● node 24  :3000  /api/v1/ │ │ flights  boarding 1  en-route 2  landed 9      │
└──────────────────────────────────────┘ └────────────────────────────────────────────────┘
┌ departures ──────────────────────────────────────────────────────────────────────────────┐
│ PKT-0012  api ─► redis     en-route   1 kB   "counters hydrated"            18:53:10     │
│ PKT-0011  nginx ─► web     boarding  27 kB   "static bytes off disk"        18:53:02     │
│ …  :flights for the full board, :dispatch <from> <to> [kb] to launch one                 │
└──────────────────────────────────────────────────────────────────────────────────────────┘
```

Width is 8 px cells. On a narrow viewport the two mid panels stack, the diorama scales down
by integer factors only (3×, 2×, 1×), and the status bar keeps the four tab numbers and the
api dot, dropping the counters.

## 2. Title bars carry real values

Box-drawing is the chrome, not a decoration, so the characters mean something:

- **single line** `┌─┐` frames content that was rendered at build time from the committed
  snapshot (`src/data/*.json`);
- **double line** `╔═╗` frames a region that is being updated live by the browser.

Every title bar embeds the current value of the thing it frames, in the bar itself:

| bar | text (values are live where the bar is double) |
|---|---|
| status | `api ● ok redis` — the word is `stats.source`, where the counters were read (Redis, or MariaDB when Redis is down), `req 1 204` from `counters.http_requests`, `hit 97%` = hit/(hit+miss) |
| machine room | `wires live` (the traffic stream's state: off, connecting, live, down), `next tick 00:48` from `next_minute_tick_s`, counting down between polls |
| cabinets | daemon version strings baked at build time: nginx 1.28.3, php 8.4, mariadb 11.x, redis 8.4.2, node 24 |
| counters | each row is a counter name exactly as the API spells it; bars are relative to the largest counter |
| departures | the last five flights from the snapshot, replaced by the live list on load |

If a value cannot be shown honestly it is not shown: before the first poll succeeds the
double bars read `═ live ═ waiting ═` and the counters show the snapshot with a `snapshot`
tag, never a zero pretending to be live.

## 3. The status bar

Always visible, fixed at the top, one row of 8 px cells (24 px tall).

Contents, left to right:

1. `[1:room] 2:flights 3:guestbook 4:about` — the four pages, `Alt+1..4`; the current one is
   bracketed and inverted (black on cyan).
2. `api ● ok redis` — the dot is the health of the last poll; the word says where the
   counters came from. MariaDB and Redis latencies are in the cabinets table and `:health`.
3. `req N` and `hit P%` — from the last successful poll.
4. `HH:MM` — the browser's clock, so the bar is never fully static even offline.

**Poll cadence.** `GET /api/v1/stats` every 5 s, aligned to the API's own 5 s cache TTL so
polling faster would only return the same cached document. The poll is skipped while the tab is
hidden and resumed immediately on `visibilitychange`.

**Offline state.** Three consecutive failures (network error, non-2xx, or > 4 s) flip the bar:
the dot turns red, the text becomes `api ● offline — retrying 10s`, the machine-room bar
degrades to `═ live ═ stale 00:37 ═` counting how old the last good data is, and the floor
lights dim to the dark-grey palette entry. Backoff is 5 → 10 → 20 → 40 s, capped, reset on the
first success. Nothing else changes: the snapshot-rendered content is still correct content.

## 4. Motion doctrine

**Only things that happened move.** Every animation on the page is caused by an event with a
name in the API: a counter delta between two polls, a flight status change, a health flip, a
key press. The diorama has no "ambient" loop of packets flying for atmosphere; if the stack is
idle, the daemons idle (they still breathe, blink and occasionally do a gag — that is the one
exception, and it is tied to the *absence* of events for 20 s, which is itself a fact).

**Timing.** The simulation steps at a fixed 60 Hz inside `requestAnimationFrame`; rendering
happens once per frame from the last simulated state, so a slow tab drops frames but never
changes the outcome. Walk cycles are 4 frames at 8 fps, LEDs blink at 2 Hz, a packet crosses
between adjacent cabinets in 900 ms. Nothing eases with a bezier: pixel art snaps between
frames, and the CSS transitions on the page use `steps()` for the same reason.

**Event → gag table** (the ≥ 6 the brief asks for, all tied to a real counter):

| API event | what the floor does |
|---|---|
| `cache_hit` delta | the Redis imp taps its cabinet, a green LED pulses once per hit (batched above 5) |
| `cache_miss` delta | the api daemon walks to MariaDB, knocks, and hauls a rowset crate back to Redis — at most one errand per 20 s, the other misses show as LED pulses |
| `flight_created` / a new flight in the list | a packet rises from the origin cabinet onto the cable; `boarding` waits beside it (blinking dim/bright), `en-route` sits where its timestamps say it is between the two cabinets, `landed` flashes its callsign at the destination; the wall departures board lists the two newest flights still in the air |
| `rate_limited` delta | the api cabinet's amber light strobes and the daemon at the door crosses its arms; a `429` speech bubble |
| `db_slow` delta | MariaDB cabinet exhales a 6-frame smoke puff; the dolphin on the cabinet ducks |
| `http_errors` delta | a spark on the nginx cabinet, the LED goes red for one blink |
| `minute_ticks` delta | the wall clock's bell rings, all daemons look up for 8 frames |
| `guestbook_post` delta | the web daemon walks to the corkboard between Redis and web and pins a note (the board shows up to six) |
| health flip to offline | the floor lights go dark grey, every daemon sits down |
| idle 20 s (no event above, and at most 3 requests per poll from other clients: the API's healthcheck and other open copies of the page are background) | one of, in turn: the Redis imp naps (zzz), a cat crosses the floor, the wordpress daemon refills its coffee |
| a frame on `/api/v1/traffic` (every 200 ms) | a dot runs along each wire in the cable duct for every request, command or statement, at the moment it happened, crossing in 500 ms; cyan hit, yellow miss, magenta slow, red error, white otherwise; past 60 dots on a wire a dot stands for 2, 5, 10 … and the wall panel says ×N. Mechanics and measurements: DEV_DOC §13.5 |

**Reduced motion.** With `prefers-reduced-motion: reduce` the canvas renders exactly one frame
(the current state: cabinets, lights at their steady colour, packets parked at their status
position) and re-renders only when a poll changes the state — no `requestAnimationFrame` loop
at all. LEDs do not blink; they are on or off. The page transitions become instant, the
scroll-driven SVG draw shows its final state, `steps()` transitions are removed. The status bar
still updates its text. Nothing is hidden from reduced-motion users; they see the same
information, standing still.

**Pausing.** The loop stops when the canvas leaves the viewport (`IntersectionObserver`,
0 px threshold) and when the document is hidden, and catches up by simulating at most one
second of missed events on resume — the rest is dropped, since old events are not news.

## 5. Three principles

1. **Live means live.** A double border, a green dot or a moving sprite is a claim that the
   browser has fresh data. The claim is either true or the element says `stale`/`offline`. No
   placeholder ever pretends.
2. **The keyboard is the primary input.** Every action has a key, the keys are shown in the
   chrome (`?` opens the full sheet), and the mouse is a courtesy. The palette knows only real
   commands; a wrong one gets `:foo: command not found`, like a shell, not a fuzzy guess.
3. **Sixteen colours, one grid, one font pair.** VGA palette, 8 px cell, Departure Mono for
   display and IBM Plex Mono for reading. Colour has meaning: cyan is structure, yellow is
   attention, red is an error, green is a healthy light. Nothing is red for style.

## 6. Self-critique: this is one step from a fake terminal

The nearest cliché is the "hacker terminal" page: green text, blinking cursor, typewriter
effect, fake `$ whoami` output, a boot sequence that means nothing. Everything about this
concept — monospace fonts, box drawing, a `:` palette, VGA colours — is that cliché's
wardrobe, and the risk is real. What keeps it honest:

- **No typewriter effects, no fake prompts, no boot log.** Text appears as text. The only
  "terminal" behaviour is the palette, and it is a real command line for real actions
  (`:dispatch` performs a POST that creates a row in MariaDB).
- **Nothing is emulated.** There is no cursor blink, no scanline shader, no CRT curvature
  filter. The pixel art is a diorama on a canvas, not a screen inside a screen.
- **Chrome carries data.** Box-drawing borders are used only where a title bar has a value to
  hold; a panel with nothing live to say gets a single line and no theatrics.
- **The keyboard model is vim's, not a shell's.** `gg`, `G`, `/`, `:` are navigation, chosen
  because they are muscle memory for the audience, not because they look like hacking.
- **The daemons are BSD's, WordPress's dolphin is MariaDB's sea lion, the imp is Redis's** —
  the mascots are the real projects' mascots, drawn in 16 colours, which is affection, not
  cosplay.

Where it still risks tipping over: the `:q` easter egg, the `zzz` nap gag, and the bell on the
minute tick are pure charm with no data. They stay because each is ≤ 1 s and rate-limited to
the idle state; if they ever start feeling like a screensaver, they go.

## 7. Deviations from the brief, stated once

- **Sprites are rasterised at runtime from ASCII art in `sprites.ts`**, not loaded from a
  `sprites.png`. The art is diffable, reviewable in a code review, and the CSP stays
  `img-src 'self' data:` without an extra asset. Cost: ~4 KB of source instead of a PNG.
- **No `:cache flush`.** The API has no endpoint for it on purpose: an anonymous visitor must
  not be able to evict Redis. `:health` and `:stats` are the read-only equivalents.
- **`GET /api/v1/guestbook` was added** so the guestbook island can list before it posts.
- **View transitions are the CSS cross-document kind** (`@view-transition { navigation: auto }`),
  not Astro's `<ClientRouter>`: zero JavaScript, and the status bar persists across pages via
  `view-transition-name`. Browsers without support get a normal navigation.
- **Islands are `<script>` modules per component**, not framework islands with `client:*`
  directives, because the site ships no framework. The equivalence is documented in
  the "what runs in the browser" panel on `/lab/about/` and in DEV_DOC §13.4.
