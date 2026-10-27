# Web Clocks

A growing collection of creative, self-contained web clock implementations — each one a single HTML file with embedded CSS and JavaScript, no build step and no dependencies beyond the occasional CDN library.

**Live site:** https://web-clocks.mark-bolding.workers.dev

## What's here

84 clocks across five categories:

| Category | What it covers |
| --- | --- |
| `clocks/art/` | Color/visual concept clocks, plus a large ongoing **literary clock series** (Kafka, Dante, Ulysses, Hamlet, The Tempest, The Dispossessed, Dune, and dozens more) |
| `clocks/nature/` | Sun, moon, circadian, and sundial clocks |
| `clocks/retro/` | Binary, flip, ASCII, arcade, and other vintage-style clocks |
| `clocks/simulation/` | Physics, particle, and agent simulation clocks (gravity, flocking, epicycles, a chaotic double pendulum, ...) |
| `clocks/utility/` | Countdown timers, dial/desktop clocks, pomodoro timers, and other practical tools |

`games/` holds standalone games rather than clocks — currently `chasm.html`, an original cavern flyer written to the Atari 2600's hardware limits, which does tell the time, in the same pixel font it draws everything else with. Games are listed under "Other Apps" at the foot of the gallery, not among the clocks.

`brain/` is Brain Explorer, a three-plane MNI152 brain viewer with eight public atlases (Harvard-Oxford, Schaefer/Yeo, FreeSurfer aseg, DKT, thalamic nuclei). Click anywhere to read every atlas's label at that point, and drop in your own NIfTI maps as overlays. It needs to be served rather than opened from disk; see [`brain/README.md`](./brain/README.md).

`desktop_widget/` holds native macOS apps rather than web pages: an analog clock and a word clock that float on the desktop, Command Bar (a small floating shell you can drop folders onto), Soma Player (a SomaFM radio), and Dial Timer (a round, drag-to-set timer). They build with one script and need an Apple Silicon Mac on macOS 14 or newer; see [`desktop_widget/README.md`](./desktop_widget/README.md) for install steps.

`plate/` is a separate, standalone installable PWA (a QR code generator) hosted alongside the clocks but unrelated to the collection — it isn't part of the gallery.

## Viewing it

Open `index.html` directly in a browser for the full gallery, or open any clock file under `clocks/<category>/` directly — every clock works standalone.

```bash
xdg-open clocks/retro/binary_clock.html   # Linux
open clocks/retro/binary_clock.html       # macOS

# Or serve locally (needed for clocks that fetch/import cross-origin modules):
python3 -m http.server 8000
# then visit http://localhost:8000/
```

There's no build, lint, or test command — everything runs directly in the browser.

## Adding a clock

Pick the category directory that fits (or a new one, if it genuinely doesn't fit an existing category), name the file `descriptive_clock.html`, keep it fully self-contained, and add a card to `index.html`'s gallery grid. See [`CLAUDE.md`](./CLAUDE.md) for the full conventions — responsive sizing, dark mode, date formatting, and the literary series backlog in [`LITERARY_CLOCK_IDEAS.md`](./LITERARY_CLOCK_IDEAS.md).

## Deployment

Deploys as static assets via Cloudflare Workers (see `wrangler.jsonc`) — the repo root is served as-is, with no build step.

## For AI coding assistants

This repo includes [`CLAUDE.md`](./CLAUDE.md) and [`GEMINI.md`](./GEMINI.md), which document the architecture and conventions for Claude Code and the Gemini CLI respectively. Keep them in sync when project structure or conventions change.

## License

[MIT](./LICENSE)
