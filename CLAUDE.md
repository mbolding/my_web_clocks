# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a collection of creative, self-contained web clock implementations. Each clock is a single HTML file with embedded CSS and JavaScript — no build process, no npm dependencies. External libraries (Three.js, Matter.js, SunCalc, etc.) are loaded from a CDN only when a specific clock needs them. Clocks open directly in a browser.

## Repository Structure

```
/
├── index.html                 # Landing page: searchable, category-grouped index of all clocks
├── clocks/
│   ├── art/                   # Color/visual concept clocks + the literary clock series
│   ├── nature/                # Sun, moon, circadian, sundial clocks
│   ├── retro/                 # Binary, flip, ASCII, arcade, vintage-style clocks
│   ├── simulation/            # Physics/particle/agent simulation clocks
│   └── utility/                # Countdown timers, dial/desktop clocks, pomodoro
├── LITERARY_CLOCK_IDEAS.md    # Backlog + tracker of literary/thematic clock concepts
├── CLOCK_AUDIT.md             # Collection-wide review: what to improve, archive, add
├── GEMINI.md                  # Equivalent guidance file for the Gemini CLI (keep in sync with this file)
├── archive/                   # Clocks retired from the gallery, kept but unmaintained
├── plate/                     # Standalone installable PWA (QR code generator) — not a clock, not in the gallery
└── wrangler.jsonc             # Cloudflare Workers static-assets config for deployment
```

Each clock file lives in exactly one category directory, e.g. `clocks/retro/binary_clock.html`, `clocks/art/dune_clock.html`. There is no build output — the repo root and `clocks/` are served as-is.

`archive/` holds clocks that have been retired from the gallery, currently the
two expired NeuroGateways '26 event clocks. The files stay in the repo and stay
reachable by direct URL, but they are not listed in `index.html`, not counted in
the collection, and not maintained. Retire a clock by `git mv`-ing it here,
deleting its `.clock-row` from `index.html`, and adding a short entry to
`archive/README.md` saying why. Don't apply the clock-file conventions below to
anything in here.

`plate/` is a separate, self-contained installable PWA (manifest + service worker + icons) unrelated to the clock collection; it lives at the repo root rather than under `clocks/` and isn't part of `index.html`'s gallery. Treat it as its own project — don't apply the clock-file conventions below to it, and don't fold it into `clocks/`.

## Development Workflow

### Viewing clocks
Open `index.html` directly in a browser for the gallery, or open any clock file under `clocks/<category>/` directly.

```bash
xdg-open clocks/retro/binary_clock.html   # Linux
open clocks/retro/binary_clock.html       # macOS

# Or serve locally (needed for clocks that fetch/import cross-origin modules):
python3 -m http.server 8000
# then visit http://localhost:8000/
```

There is no build, lint, or test command in this repo — verify changes by loading the HTML file in a browser and checking the console for errors.

### Deployment
The site deploys as static assets via Cloudflare Workers (see `wrangler.jsonc`: `assets.directory` is `.`, `nodejs_compat` flag enabled). `wrangler deploy` serves the repo root as-is; there's no build step to run first.

## Adding a New Clock

1. Pick the right category directory under `clocks/` (`art`, `nature`, `retro`, `simulation`, `utility`); only create a new one if the clock genuinely doesn't fit an existing category.
2. Name the file `descriptive_clock.html` (snake_case, ends in `_clock.html`).
3. Keep the clock fully self-contained: styles in `<style>`, logic in `<script>`, no build step. Only pull in a CDN library (Three.js, Matter.js, SunCalc, etc.) when the concept genuinely needs it.
4. Add an entry to `index.html`: an `<a class="clock-row">` with `href="clocks/<dir>/<file>.html"`, a `title` attribute holding the full description, and `.clock-name` + `.clock-description` spans. Place it in the `.clock-list` of the matching `<section class="category">` — and for a literary clock, in the `.clock-list` under the right `.group-title` sub-group. Add `data-keywords="<author> <source work>"` so the clock is findable by author as well as by title. Counts in the tabs, headings and tagline are derived from the DOM at load, so there is nothing to bump by hand.
5. If it's part of the literary series, add/update its entry in `LITERARY_CLOCK_IDEAS.md` (move it into "Currently Implemented" with a ✅ and one-line description).
6. Implement responsive sizing with CSS `clamp()`. Add dark mode via `prefers-color-scheme` where it fits — not all clocks use it; many literary/art clocks are intentionally locked to one themed palette.
7. If the change affects overall project structure or conventions, mirror it into `GEMINI.md`, which documents the same architecture for the Gemini CLI.

## Common Implementation Patterns

**Time updates**
- Simple digit/text clocks: `setInterval(updateClock, 1000)`.
- Smooth/physics/canvas animations: `requestAnimationFrame(animate)` loop.

**Responsive sizing**
```css
font-size: clamp(min, preferred, max);
```

**Canvas sizing (HiDPI)** — size the backing store in device pixels and scale the
context once, so the canvas stays sharp on Retina and 4K displays. Keep CSS-pixel
`width`/`height` variables for the drawing code to use; reading `canvas.width`
after this returns device pixels, not layout pixels.
```javascript
function resizeCanvas() {
    const dpr = window.devicePixelRatio || 1;
    width = window.innerWidth;
    height = window.innerHeight;
    canvas.style.width = width + 'px';
    canvas.style.height = height + 'px';
    canvas.width = Math.round(width * dpr);
    canvas.height = Math.round(height * dpr);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
}
```
Read `devicePixelRatio` inside the handler rather than once at load, so dragging
the window to a display with a different ratio re-scales correctly.

**Dark mode** (where used)
```javascript
if (window.matchMedia('(prefers-color-scheme: dark)').matches) {
    document.documentElement.classList.add('dark');
}
```

**Date formatting** — most clocks spell out day/month names locally rather than relying on `Intl`:
```javascript
const days = ['Sunday', 'Monday', ...];
const months = ['January', 'February', ...];
```

**`index.html` gallery** — a single static file. A sticky `.controls` bar holds a `#search` box and a `.tabs` nav (`data-filter` per button). Below it sits one `<section class="category" data-category="...">` per category, each holding one or more `.clock-list` grids of `.clock-row` links. The Literary section splits its list into sub-groups, each introduced by a `.group-title` `<h3>` immediately before its `.clock-list`.

The inline `<script>` builds a cached search index per row from the row text, its `data-keywords`, its group heading and its category heading — so "kafka" finds The Trial and "shakespeare" finds all three plays. It then toggles a `.hidden` class on non-matching rows, and on any group heading, list or category left empty. The tab filter and the search box combine with AND. `/` focuses the search box and Escape clears it. Descriptions are truncated to a single line in CSS; the full text stays in the DOM (so search still matches it) and in `title=` for hover.

**Gallery category vs. directory** — these are deliberately not the same. `clocks/art/` holds both the literary series and the abstract/colour clocks; in the gallery the literary ones appear under the `literary` section and the rest under `art`. The directory is where a file lives; the section is how it is browsed. Don't move files to make the two line up.

**CDN libraries in use** — Three.js (`sundial_clock`, `xyz_clock`), Matter.js (`gravity_clock`), SunCalc (`sun_moon_clock`, `timeline_clock`), all from cdnjs. Prefer these over adding a new dependency unless a clock's concept requires something else, and load them from cdnjs so there is one CDN to trust. Neither Three.js clock uses OrbitControls: `xyz_clock` carries a small inline orbit control instead, which avoids pulling a second copy of Three.js through a module CDN.

**Other network calls** — `circadian_clock` reverse-geocodes the browser's coordinates through `nominatim.openstreetmap.org` to name the user's location. It is the only clock that sends location data off-device, it degrades to plain coordinates when the call fails, and OpenStreetMap's usage policy is not written for anonymous static-site traffic. Don't copy the pattern into new clocks without a reason.

**Reduced motion** — clocks whose motion is decorative rather than timekeeping should hold still when the visitor asks them to. For a canvas layer, stop scheduling the loop so one frame stays on screen; where the readout is written from inside that loop, keep it ticking on an interval.
```javascript
const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
function animateSnow() {
    // ...
    if (!reduceMotion.matches) requestAnimationFrame(animateSnow);
}
```
Animations that carry the time (a sweeping second hand, a turning epicycle) are not decoration and should keep running.

## Literary Clock Series

`clocks/art/` contains a large, ongoing series of literature-themed clocks (Kafka, Dante, Ulysses, Infinite Jest, Dune, Hamlet, etc.), each reinterpreting a source work's structure or themes as a timekeeping device. `LITERARY_CLOCK_IDEAS.md` is the running backlog/tracker for this series — check it before starting a new literary clock to avoid duplicating a concept, and update it once a listed idea is implemented. One entry, `slow_post_clock.html` (The Slow Post), is original fiction rather than a reinterpretation: a hypertext novella of about ten thousand words that is also the clock, where the real date governs which letters have arrived and the hour governs the light. It is the only clock in the collection that stores reader state across visits (`localStorage`, key `slow_post_v2`) and changes its own text on reread, so treat its passage graph as load-bearing: `clocks/art/slow_post_clock.html` is generated from a passage table, and edits to the prose must preserve every lexia target.
