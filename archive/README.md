# Archive

Clocks retired from the gallery in `index.html`. The files are kept because they
still work and are worth reading, but they are no longer listed, linked or
counted as part of the collection.

Nothing here is maintained. The conventions in `CLAUDE.md` for adding a clock do
not apply to this directory.

## Contents

### `ng26_clock.html`, `ng26_countdown.html`

Two clocks built for NeuroGateways '26, an event dated April 9 to 10, 2026. Both
hardcode `new Date('2026-04-09T00:00:00')`, so they stopped being useful once
that date passed: the countdown now reads "The conference has begun"
permanently, while the gallery still advertised it as "A countdown timer".

Retired as expired single-event artifacts, not because of any defect.

**Worth borrowing:** these were the only two clocks in the collection that
responded to `prefers-color-scheme`. The pattern, which `CLAUDE.md` documents,
also handles a live scheme change rather than only reading the value once at
load:

```javascript
if (window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches) {
    document.documentElement.classList.add('dark');
}
window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', event => {
    event.matches ? document.documentElement.classList.add('dark') : document.documentElement.classList.remove('dark');
});
```

### `life_clock.html`

The original 4,680-week memento mori grid. `clocks/utility/life_zoom_clock.html`
is a strict superset of it: identical `TOTAL_YEARS`, `WEEKS_PER_YEAR` and
`TOTAL_WEEKS`, the same week arithmetic, the same date input and the same
`localStorage` persistence, plus scroll and pinch zoom, drag-to-pan and per-week
date tooltips. Side by side the two pages are the same design, one of them with a
zoom control row.

Retired because two adjacent gallery rows for the same grid made the visitor
choose between a thing and the same thing with more features.

### `perlin_clock.html`, `predator_clock.html`, `obstacle_clock.html`

Three variations on one boid simulation. All four of the original flocking clocks
shared the same `flockingCanvas` element id, the same `Vector` class, the same
steering code and the same corner readout, and `perlin_clock` and
`obstacle_clock` each carried their own inline copy of the same SimplexNoise
implementation.

They are now modes of `clocks/simulation/flocking_clock.html`, which keeps each
one's time mapping exactly: the Perlin field with the hour setting its strength,
the predator whose speed follows the hour and colour the minute, and the drifting
obstacles. Four of eleven simulation entries being variants of one sim crowded
out the genuinely distinct work in that section.

The consolidated clock also draws the 12-hour dial the flock is steered around,
so the hour can be read from the simulation rather than only from the digital
readout pasted over it.
