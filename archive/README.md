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
