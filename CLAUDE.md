# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a collection of creative, self-contained web clock implementations. Each clock is a single HTML file with embedded CSS and JavaScript — no build process, no npm dependencies. External libraries (Three.js, Matter.js, SunCalc, etc.) are loaded from a CDN only when a specific clock needs them. Clocks open directly in a browser.

## Repository Structure

```
/
├── index.html                 # Landing page: tabbed/filterable gallery of all clocks
├── clocks/
│   ├── art/                   # Color/visual concept clocks + the literary clock series
│   ├── nature/                # Sun, moon, circadian, sundial clocks
│   ├── retro/                 # Binary, flip, ASCII, arcade, vintage-style clocks
│   ├── simulation/            # Physics/particle/agent simulation clocks
│   └── utility/                # Countdown timers, dial/desktop clocks, pomodoro
├── LITERARY_CLOCK_IDEAS.md    # Backlog + tracker of literary/thematic clock concepts
├── GEMINI.md                  # Equivalent guidance file for the Gemini CLI (keep in sync with this file)
└── wrangler.jsonc             # Cloudflare Workers static-assets config for deployment
```

Each clock file lives in exactly one category directory, e.g. `clocks/retro/binary_clock.html`, `clocks/art/dune_clock.html`. There is no build output — the repo root and `clocks/` are served as-is.

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
4. Add an entry to `index.html`'s `.clock-grid`: an `<a>` with `href="clocks/<category>/<file>.html"`, `class="clock-card"`, and `data-category="<category>"` matching one of the nav tab filters, containing `.clock-name`, `.clock-description`, and `.clock-tag` children. Place it under the matching `<!-- Category -->` comment block so the file stays organized.
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

**`index.html` gallery** — a single static file with a `.tabs` nav (`data-filter` per button) and a `.clock-grid` of `.clock-card` links (`data-category` per card). An inline `<script>` toggles a `.hidden` class client-side by matching the active tab's `data-filter` against each card's `data-category`. When adding a card, match the existing markup exactly so filtering keeps working.

**CDN libraries in use** — Three.js + OrbitControls (3D sundial), Matter.js (physics/gravity clocks), SunCalc (sun/moon position clocks). Prefer these over adding a new dependency unless a clock's concept requires something else.

## Literary Clock Series

`clocks/art/` contains a large, ongoing series of literature-themed clocks (Kafka, Dante, Ulysses, Infinite Jest, Dune, Hamlet, etc.), each reinterpreting a source work's structure or themes as a timekeeping device. `LITERARY_CLOCK_IDEAS.md` is the running backlog/tracker for this series — check it before starting a new literary clock to avoid duplicating a concept, and update it once a listed idea is implemented.
