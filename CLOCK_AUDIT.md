# Clock Collection Audit

A review pass over all 85 clocks in `clocks/`, covering what could be improved,
what could be archived, and what could be added.

Every count and claim below was verified against the files in the repo at the
time of writing.

**Status:** sections 1 and 2 are done. Section 3 is new work rather than fixes
and is still open. Items are marked inline.

Four findings turned out to be wrong once tested, including one where the right
answer was to keep both clocks rather than retire either. All are corrected in
place below and flagged **Correction**.

The collection stands at 79 clocks, down from 85, with six files in `archive/`
and no concept lost.

**Collection at a glance**

| Metric | Value |
|---|---|
| Clock files | 79 (all 79 linked from `index.html`, no orphans, no dead links) |
| By gallery section | literary 41, art 10, simulation 8, retro 8, nature 5, utility 7 |
| Canvas-based | 23 |
| `requestAnimationFrame` loops | 53 |
| Canvas clocks scaling for HiDPI | 26 of 26 (was 3) |
| Clocks whose decorative motion stands down for `prefers-reduced-motion` | 14 (was 0) |
| Clocks with `aria-*` markup | 22 (was 0) |
| Clocks that follow the OS colour scheme | 4 (was 0) |
| Clocks loading Google Fonts | 65 (all 65 now `preconnect`, was 0) |

---

## 1. Clocks that could be improved

### 1.1 Cross-cutting, worth a single sweep

**HiDPI canvas blur, 23 of 26 canvas clocks. DONE.** All 23 now size their
backing store in device pixels and scale the context once on resize; the shared
pattern is documented in `CLAUDE.md` under "Canvas sizing (HiDPI)". Verified in
headless Chromium at `deviceScaleFactor: 2`: all 23 went from a backing-store to
CSS ratio of 1.0 to 2.0, with no JS errors, including across a viewport resize.
Original finding follows.

Only `desktop_clock`,
`dial_clock` and `utility_clock` touch `devicePixelRatio`. The other 23 size
their backing store to CSS pixels, so every one of them renders soft on a
Retina or 4K display. Affected files include the whole `simulation/` set plus
`art/candide`, `art/coordinate`, `art/deodand`, `art/dune`, `art/dying_sun`,
`art/ghost_in_the_shell`, `art/macbeth`, `art/magic_mountain`,
`art/prehistoric`, `art/snow_country`, `art/solitude`, `retro/ascii` and
`retro/asteroids`. This is the highest value fix in the audit: one shared
6-line resize helper, applied 23 times, visibly sharpens a quarter of the
collection.

**No reduced-motion support anywhere, 0 of 85. DONE, for decorative motion.**
The canvas backdrops in 11 clocks now hold a single frame when reduced motion is
requested, and the `glitch`, `calvino` and `house_of_leaves` CSS animations stand
down (glitch keeps its chromatic split and loses only the movement). Where the
readout is written from inside a frozen loop, it keeps ticking on an interval.
Verified by loading each under both `reducedMotion` settings and diffing the
canvas pixels: decoration static under reduce, moving otherwise, clock ticking in
both. Animations that *carry* the time (a sweeping hand, a turning epicycle) are
deliberately left running, since freezing those stops the clock. Original finding
follows.

 53 clocks run continuous
`requestAnimationFrame` loops, and several are deliberately aggressive
(`glitch_clock`, `house_of_leaves`, `calvino_clock` re-themes itself every 15
seconds, `candide_clock` runs "violent CSS disasters"). None check
`prefers-reduced-motion`. For a collection this animation-heavy that is the
clearest accessibility gap. A reasonable default: keep the clock readable and
correct, drop the decorative motion.

**No screen-reader affordance, 0 of 85. DONE.** 13 backdrop canvases are now
`aria-hidden`, and 10 primary readouts carry `role="timer"` with a label.

**Correction.** The original recommendation here was to add `aria-live="polite"`
to the readout. That is wrong for a clock: a polite live region on an element
that changes every second makes a screen reader announce the time every second,
which is worse than no markup at all. `role="timer"` is the right choice, as it
is a live region whose implicit `aria-live` is `off`, so assistive tech can find
and query the clock without being read it continuously.

**Google Fonts without `preconnect`, 67 files. DONE** for all 65 in the
gallery; the two in `archive/` are left alone as unmaintained. Original finding
follows.

 67 clocks pull webfonts from
`fonts.googleapis.com`, none with a `preconnect` hint to
`fonts.gstatic.com`. Two lines per file removes a round trip on first paint.
Some clocks request three or four families at several weights each, which is
worth trimming where the design does not use them all.

**rAF driving once-per-second text. DONE.** The pass suggested below was run.
`macos_clock`, `finnegans_wake` and `slaughterhouse_five` were pure 1Hz text and
now use `setInterval`. `clarke_clock` gates everything on the second changing, so
it polls at 10Hz instead of 60. `bach_clock` keeps its rAF loop: it uses
milliseconds to sweep its hands smoothly, so the frame rate is doing real work.
Original finding follows.

 29 DOM-only clocks (no canvas) run an
rAF loop. Many genuinely animate and should stay, but some only repaint whole
seconds. `retro/macos_clock` is the clear-cut case: it calls
`toLocaleDateString` and rewrites two elements 60 times a second to display a
value that changes once a second. `CLAUDE.md` already prescribes the right
pattern for these ("simple digit/text clocks: `setInterval(updateClock, 1000)`").
Worth a quick pass over `bach`, `clarke`, `finnegans_wake`,
`slaughterhouse_five` and `macos` to see which can drop to an interval.

**Dark mode. DONE for the utility tier.** Four clocks now follow the system
setting: `conference_clock` and `timeline_clock` gained a dark palette keyed off
`prefers-color-scheme`, and `dial_clock` and `utility_clock` now seed their
existing theme from it.

**Correction.** The original finding said only the two NG26 clocks responded to
`prefers-color-scheme`, which was true but missed the more interesting case:
`utility_clock` and `dial_clock` already had complete dark palettes and a manual
toggle button, they just never consulted the OS, and their toggle icon always
started on the sun whatever the theme. Layering a `prefers-color-scheme` palette
over that would have created two competing systems, with the component-level
`.dark` rules firing in only one of them. They now start from the system
preference and keep following it until the button is used.

`desktop_clock` is deliberately left light: its gallery entry names light mode as
part of the design. The literary and art clocks stay locked to their palettes, as
`CLAUDE.md` intends. Original finding follows.

Only `ng26_clock` and `ng26_countdown` respond to
`prefers-color-scheme`, and both are archive candidates (see 2.1), which would
take the collection to zero. `CLAUDE.md` is right that literary and art clocks
are intentionally locked to a themed palette, so this is really a note about
the utility and retro tiers: `binary`, `flip`, `latex`, `ascii`,
`conference_clock` and `timeline_clock` are all palette-neutral enough to
support both schemes.

### 1.2 Specific clocks

**`art/xyz_clock.html` needs the most work of any single file. DONE, all four.**
It now carries a small inline orbit control, so nothing is loaded from Skypack
and only one copy of Three.js is fetched; the trail is chronological and seeded
with the preceding 12 hours at load, fading from dim to bright so the direction
of time reads; and the readout uses `clamp()`.

**Correction** to point 2 below: the wrap really did misorder the buffer, and
replaying it past capacity shows all 43,200 slots rotated the moment it wraps,
which the fix removes. But calling the result a visible "spurious segment
straight across the box" overstated it. The mapping already jumps the full width
of the cube 720 times in 12 hours, whenever the minute rolls over, and once a day
at midnight, so one more arbitrary segment was not distinguishable. The valuable
part of this fix is the dependency removal and the seeding, not the wrap.

Original finding follows. Four issues:

1. It loads Three.js r128 as a global script from cdnjs, then imports
   `OrbitControls` from `cdn.skypack.dev/three@0.128.0`. Skypack resolves
   OrbitControls' own `three` import, so the page pulls a **second** copy of
   Three.js. Skypack is also the only use of that CDN in the repo and is not
   among the CDNs `CLAUDE.md` sanctions.
2. The trail is a ring buffer of 43,200 points drawn as a single `THREE.Line`.
   Once it wraps at the 12-hour mark, index 0 holds the newest point while
   index 1 holds the oldest, so the line draws a spurious segment straight
   across the box. The artifact is permanent after 12 hours of uptime.
3. On load the trail is empty, so a first-time visitor sees a single dot in a
   wireframe cube. Because the mapping is purely a function of the clock, the
   previous 12 hours could be seeded at startup and the concept would land
   immediately.
4. No `clamp()`; the readout is a fixed `1.5rem`.

**`retro/macos_clock.html` is described inaccurately in the gallery. DONE.**
It now has the window: a striped System 6 title bar with a close box and resize
grip, dragging anywhere on the desktop and clamped so the title bar stays
reachable. The gallery description is true as written. Original finding follows.


`index.html` sells it as "A System 6 tribute with draggable windows." The file
contains no `mousedown`, no drag logic and no window chrome at all, just one
static centred `.clock-screen` div. Either build the draggable window (the
better outcome, it is a good idea) or correct the description. It also uses
`background-attachment: fixed`, which iOS Safari ignores.

**The two "life" clocks miscount the grid. DONE.** Rows are years of life, so
the fill now follows birthdays while the headline stats follow real elapsed time.
At 90-minus-16-weeks the grid reads 4,664 of 4,680 with 16 weeks remaining, where
before it read full with none left. The zoom clock's tooltips and current-week
shading use the same per-year basis. Original finding follows.

 Both `life_clock` and
`life_zoom_clock` build a 4,680-box grid from `TOTAL_YEARS * 52`, but compute
progress as real elapsed time (`msAlive / 604800000`). Ninety real years is
about 4,696 weeks, so the grid runs out roughly 15 weeks before the person's
actual 90th birthday: the "weeks remaining" figure reaches zero early and the
grid saturates. In a memento mori clock the number is the entire point, so
this is worth fixing (either 4,696 boxes, or derive the grid from real
birthday anniversaries).

**The flocking clocks do not actually tell the time.** `flocking`, `perlin`,
`predator` and `obstacle` all map the time onto simulation *parameters*
(cohesion factor, max speed, predator colour) and then print the real time
with `now.toLocaleTimeString()` in a corner div. The simulation is decorative;
remove the div and the clock is unreadable. Compare `epicycle_clock` or
`pendulum_clock`, where the geometry itself carries the time. Making at least
one of them legible as a clock, for instance boids settling into digit shapes
or the flock's centroid acting as an hour hand, would lift the whole group.

**The four flocking clocks never handle window resize. DONE.** All four now
register a resize handler. Original finding follows.

 Surfaced while doing
the HiDPI sweep: `flocking`, `perlin`, `predator` and `obstacle` size their
canvas once at load and register no `resize` listener, so the drawing area stays
at its original dimensions when the window changes and the boids wrap against
invisible edges. Left as-is by the HiDPI work, which deliberately preserved
existing resize behaviour. Best fixed as part of consolidating them (2.5).

**`nature/circadian_clock.html` has an undocumented network dependency. DONE**,
in the sense asked for: it is now documented in `CLAUDE.md` and `GEMINI.md`, with
a note not to copy the pattern. The call itself is left in place, since removing
it would cost the place name for no correctness gain. Original finding follows.

 It
POSTs the user's exact coordinates to `nominatim.openstreetmap.org` for
reverse geocoding. The call is correctly wrapped in `.catch()` and degrades to
raw coordinates, so it is not a bug, but it is a third-party service not listed
in `CLAUDE.md`, it sends precise location off-device, and OSM's usage policy is
not really written for anonymous browser traffic from a static site. At minimum
it deserves a line in `CLAUDE.md`; ideally the clock would say where the name is
coming from, or drop the lookup and show coordinates.

**`CLAUDE.md`'s CDN inventory is wrong in two ways. DONE.** Both files now list
the real consumers of each library and note that neither Three.js clock uses
OrbitControls. Original finding follows.

 It states "Three.js +
OrbitControls (3D sundial)". The 3D sundial (`nature/sundial_clock.html`) does
**not** load OrbitControls at all; the only OrbitControls user is
`art/xyz_clock.html`, and it loads it from Skypack rather than the documented
CDN. Three.js is also pinned to r128, which is several major versions behind.
Worth correcting the doc and deciding whether to bump the pin.

**Unoptimised raster assets. DONE for the PNG.** `os6.png` turned out to be a
3066x2050 RGBA image holding exactly two distinct colours over a fully opaque
alpha channel. Re-encoded as 1-bit it is pixel-identical to the original and
drops from 398 KB to 8.8 KB, a 97.8% saving for no visible change at all.

**Correction.** The original claim that *both* files compress substantially at no
visible cost was wrong. `old_clock_face.jpg` is a photograph and is already
sensibly encoded: re-encoding at quality 90 saves about 15% while adding
generational loss (PSNR 38.7 dB), and higher quality settings make the file
larger than the original. It is left as it is.

**Thin gallery descriptions. DONE.** All 29 rows under 62 characters were
rewritten against what the clock actually does, not what its name suggested.
Original finding follows.

 The literary rows read well ("Meursault's
indifference, the Algerian sun, the murder on the beach"). Much of `art`,
`simulation` and `retro` does not: "A clock that periodically glitches and
distorts", "A particle system based clock", "Time displayed in binary format",
"A simulation of flocking behavior". Because `index.html` builds its search
index from row text, weak descriptions also make those clocks harder to find.
Roughly 20 rows would benefit from a rewrite at the standard the literary
section already sets.

---

## 2. Clocks that could be archived

### 2.1 `utility/ng26_countdown.html` and `utility/ng26_clock.html`, expired. DONE

Both moved to `archive/` and removed from the gallery. The dark-mode pattern they
carried is preserved in `archive/README.md`. Original finding follows.


Both are branded "NeuroGateways '26" and hardcode
`new Date('2026-04-09T00:00:00')` for an event dated "April 9–10, 2026". That
was over five months ago. `ng26_countdown` now permanently displays
"The conference has begun", which is the graceful-degradation path but is
simply wrong today, and the gallery advertises it as "A countdown timer".

These are the strongest archive candidates in the collection: single-event
artifacts whose event has passed. Worth noting they are also the only two
clocks with dark mode support, so it is worth lifting that pattern out before
retiring them.

### 2.2 The two García Márquez clocks. CORRECTED, both kept

**Correction.** This finding was wrong, and looking at the two clocks rendered
rather than at their file sizes is what showed it. They are not duplicates, they
are two different devices built from one novel. `solitude_clock` is the
atmospheric reading: the time blurs and dissolves into memory under the yellow
butterflies, with the famous opening line beneath. `one_hundred_years_clock` is
the structural one: Macondo's circular time drawn as concentric rings, naming
which generation of Buendías the hour belongs to. Retiring either would have
thrown away a distinct piece of work on the strength of a shared author and a
shared motif.

What was actually wrong is that nothing said so. Both rows now name which reading
they are, they share keywords so either search finds both, and
`LITERARY_CLOCK_IDEAS.md` records them as one novel implemented twice on purpose
rather than as two unrelated ticks. Original finding follows.


Two clocks for the same novel. `solitude_clock` is "100 Years of Solitude"
(sepia palette, yellow butterflies); `one_hundred_years_clock` is
"Cien Años de Soledad" (parchment palette, yellow butterflies). They sit in
different gallery sub-groups, so the duplication is easy to miss while
browsing.

This looks like drift rather than intent: `LITERARY_CLOCK_IDEAS.md` tracks
them as two separate completed entries, "✅ Cien Años de Soledad" under
Modernist Literature and "✅ 100 Years of Solitude" under Other Literary &
Thematic Works. Keep the stronger one (`one_hundred_years_clock` is the more
developed at 422 lines versus 244), fold across anything worth keeping, and
collapse the tracker to one entry.

### 2.3 `utility/life_clock.html`, strict subset. DONE

Archived. Seen side by side the two pages are the same design, one of them with a
zoom control row. Fixing the grid arithmetic in both (1.2) also surfaced a small
bug in the survivor: `.zoom-controls button` forced a 32px width on every button,
clipping the text-labelled Reset to "Res". Original finding follows.


`life_zoom_clock` is a superset: identical `TOTAL_YEARS`/`WEEKS_PER_YEAR`/
`TOTAL_WEEKS` constants, identical week arithmetic, the same date input and the
same `localStorage` persistence, plus scroll and pinch zoom, drag-to-pan, zoom
buttons and per-week date tooltips. There is nothing `life_clock` does that
`life_zoom_clock` does not. Two adjacent gallery rows for the same grid is
mostly a choice the visitor should not have to make.

### 2.4 `art/xyz_clock.html`, superseded concept. RESOLVED BY FIXING IT

The finding offered a choice: retire it, or give it the reason to exist that
`coordinate_clock` does not cover, namely the 12-hour trail. The trail was
rebuilt and seeded, so it now does something `coordinate_clock` does not, and the
clock earns its place. Original finding follows.


Setting aside the bugs in 1.2, the concept is "time mapped to X, Y, Z
coordinates", which `art/coordinate_clock.html` already contains as one mode
among many: it assigns Y/Mo/D/H/Mi/S to axes across Cartesian, polar,
parabolic, elliptic, cylindrical and spherical space, in 969 lines to
`xyz_clock`'s 133. Either retire `xyz_clock`, or give it a reason to exist that
`coordinate_clock` does not cover, namely the 12-hour trail, which is genuinely
distinctive and is currently the broken part.

### 2.5 Consolidate the flocking quartet, four files to one. DONE

`flocking_clock.html` now carries all four as modes, each keeping the exact time
mapping it had as a standalone file, with one shared copy of SimplexNoise instead
of two inline duplicates. `perlin`, `predator` and `obstacle` are archived, and
the gallery row keeps all four names as keywords so anyone looking for "the
predator one" still finds it.

While consolidating, the deeper complaint in 1.2 was also addressed: the clock
now draws the 12-hour dial the flock is steered around, so the hour reads off the
simulation instead of only off the digital readout pasted over it. Verified in
all four modes, in both motion settings, at `deviceScaleFactor: 2`. Original
finding follows.


`flocking`, `perlin`, `predator` and `obstacle` are one clock with four
settings. All four share the same `flockingCanvas` element id, the same
`Vector` class, the same boid steering code and the same `digitalTime` div;
`perlin` and `obstacle` each carry their own inline copy of the same
SimplexNoise implementation. The gallery descriptions say as much: "A
simulation of flocking behavior", "A flocking simulation guided by a noise
field", "A flocking simulation where a predator chases the flock", "A flocking
simulation with moving obstacles".

Four of eleven simulation entries being variants of one sim crowds out the
genuinely distinct work in that section (`epicycle`, `pendulum`,
`state_machine`, `oscilloscope`). `coordinate_clock` is the precedent for the
fix: one clock, a mode switch for noise field, predator and obstacles.

**Net effect:** 85 clocks to 79, with no concept lost. The estimate of 78
assumed one of the Márquez pair would go; it stayed, correctly.

---

## 3. Clocks that could be added

`LITERARY_CLOCK_IDEAS.md` already holds a deep literary backlog (The Castle,
Cloud Atlas, Orlando, Tristram Shandy, Pedro Páramo, The Master and Margarita,
Gravity's Rainbow, the Japanese and Russian sets, three more Shakespeares, four
more Hemingways). That list does not need extending. The suggestions below are
gaps in the *collection's* coverage rather than in its reading list.

### 3.1 The biggest gap: no clock handles a timezone other than the viewer's

All 85 clocks call `new Date()` and render local time. For a collection called
"web clocks" that is a conspicuous hole, and it is the one thing on this list
people would use daily.

- **World Clock.** Several cities at once, `Intl.DateTimeFormat` with explicit
  `timeZone`, ideally with the day/night terminator. Natural fit for
  `utility/`.
- **Meeting Overlap Clock.** Pick two or three zones, see the working-hours
  band where they intersect. `timeline_clock` already has the scrollable-ruler
  mechanic to build on.

### 3.2 Alternative time systems, strong fit for the repo's sensibility

The collection is full of invented time systems for fictional worlds
(`cutz_chronometer`'s Grand Chimes and Sestinas, `dune_clock`'s Arrakis
Standard Time, `dispossessed_clock`'s communal decads) but contains no real
one, which is an odd absence given the aesthetic.

- **French Republican Decimal Clock.** 10-hour days, 100-minute hours,
  Revolutionary calendar with its Vendémiaire and Brumaire month names and a
  plant, animal or tool assigned to every day of the year. Visually rich, real,
  and the closest thing history has to the invented systems already here.
- **Swatch Internet Time (.beat).** 1,000 beats a day, no timezones, Biel
  Meridian. A genuine artifact of 1998 web culture, which makes it the most
  on-theme retro idea available for a web clock collection.
- **Calendar Clock.** The same instant in Gregorian, Hebrew, Islamic, Persian
  and Chinese calendars. `Intl.DateTimeFormat` supports all of these natively,
  so the implementation is mostly typography.
- **Unix Epoch Clock.** Seconds since 1970 as the primary readout, counting
  down to the 2038 signed-32-bit rollover. Pairs well with `latex_clock` and
  `binary_clock` in the retro/technical tier.

### 3.3 `nature/` is the thinnest section, 5 clocks

It also has the highest ratio of real-world usefulness to file count, and the
repo already loads SunCalc.

- **Tide Clock.** The traditional ~12h25m lunar-tidal dial. The most requested
  real-world clock type absent here.
- **Moon Phase Clock.** `sun_moon_clock` plots sky position but not the
  synodic cycle. A lunation clock, with phase, libration and the next full
  moon, is a distinct and attractive piece. SunCalc already exposes the data.
- **Season / Solstice Clock.** The year as a dial, with solstices, equinoxes
  and current daylight length, driven by the same geolocation already in use.

### 3.4 `retro/` gaps not already in the backlog

The backlog lists Space Invaders, Windows 95 and NeXTSTEP. Not listed:

- **Nixie Tube Clock.** The single most iconic retro clock form, and currently
  absent. Warm cathode glow, the stacked-digit parallax, the characteristic
  layering.
- **Split-Flap Departure Board.** Distinct from `flip_clock`: a Solari board
  clatters through the whole character set to land on each glyph. The audio and
  the settling cascade are the point.
- **Teletext / Ceefax Clock.** The BBC test-page aesthetic, chunky blocky
  graphics, a fixed 40x25 grid. Sits naturally beside `ascii_clock`.

### 3.5 One conceptual clock

- **Time Dilation Clock.** Two clocks side by side, one stationary, one at a
  velocity you control with a slider, drifting apart by the Lorentz factor. The
  collection has deep time (`prehistoric_clock`), a lifetime (`life_clock`) and
  cyclical time (`one_hundred_years_clock`), but nothing on relative time.

### 3.6 Two notes on the existing backlog

- **The Hobbit** entry lists "second breakfast; elevenses" as its hook, which
  `nature/mealtime_clock.html` already implements ("Tells time by Second
  Breakfast, Elevenses, and more"). Worth steering the Hobbit clock toward the
  journey structure, Shire to Rivendell to Erebor and back, and the moon-letter
  runes instead.
- **Tea Timer Clock** and **Espresso Clock** overlap each other and
  `mealtime_clock`. Probably one "beverage ritual" clock rather than three.

---

## Suggested order of work

1. ~~Archive the two expired NG26 clocks (lift their dark mode pattern first).~~ Done.
2. ~~Resolve the three duplicate pairs: the two Márquez clocks, the two life
   clocks, `xyz_clock` against `coordinate_clock`.~~ Done: the life clocks
   collapsed to one, `xyz_clock` earned its place by being fixed, and the Márquez
   pair turned out not to be a duplicate at all.
3. ~~Consolidate the flocking quartet.~~ Done, four modes in one clock.
4. ~~Sweep HiDPI scaling across the 23 canvas clocks.~~ Done.
5. ~~Add `prefers-reduced-motion` handling to the animated clocks.~~ Done for
   decorative motion.
6. ~~Fix the 4,680-week grid arithmetic and the `macos_clock` description.~~ Done.
7. ~~Correct the CDN inventory in `CLAUDE.md` and `GEMINI.md`.~~ Done.
8. ~~Rewrite the ~20 thin gallery descriptions.~~ Done, 29 of them.
9. ~~Give the collection a dark-mode-aware clock again, starting with the
   palette-neutral utility tier.~~ Done, four of them.
10. Then build: World Clock first, it fills the largest gap.
