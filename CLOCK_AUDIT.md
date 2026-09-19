# Clock Collection Audit

A review pass over all 85 clocks in `clocks/`, covering what could be improved,
what could be archived, and what could be added.

Every count and claim below was verified against the files in the repo at the
time of writing.

**Collection at a glance**

| Metric | Value |
|---|---|
| Clock files | 85 (all 85 linked from `index.html`, no orphans, no dead links) |
| By gallery section | literary 41, art 10, simulation 11, retro 8, nature 5, utility 10 |
| Canvas-based | 26 |
| `requestAnimationFrame` loops | 53 |
| Canvas clocks scaling for HiDPI | 3 of 26 |
| Clocks honouring `prefers-reduced-motion` | 0 of 85 |
| Clocks with any `aria-*` attribute | 0 of 85 |
| Clocks honouring `prefers-color-scheme` | 2 of 85 |
| Clocks loading Google Fonts | 67 (none with `preconnect`) |

---

## 1. Clocks that could be improved

### 1.1 Cross-cutting, worth a single sweep

**HiDPI canvas blur, 23 of 26 canvas clocks.** Only `desktop_clock`,
`dial_clock` and `utility_clock` touch `devicePixelRatio`. The other 23 size
their backing store to CSS pixels, so every one of them renders soft on a
Retina or 4K display. Affected files include the whole `simulation/` set plus
`art/candide`, `art/coordinate`, `art/deodand`, `art/dune`, `art/dying_sun`,
`art/ghost_in_the_shell`, `art/macbeth`, `art/magic_mountain`,
`art/prehistoric`, `art/snow_country`, `art/solitude`, `retro/ascii` and
`retro/asteroids`. This is the highest value fix in the audit: one shared
6-line resize helper, applied 23 times, visibly sharpens a quarter of the
collection.

**No reduced-motion support anywhere, 0 of 85.** 53 clocks run continuous
`requestAnimationFrame` loops, and several are deliberately aggressive
(`glitch_clock`, `house_of_leaves`, `calvino_clock` re-themes itself every 15
seconds, `candide_clock` runs "violent CSS disasters"). None check
`prefers-reduced-motion`. For a collection this animation-heavy that is the
clearest accessibility gap. A reasonable default: keep the clock readable and
correct, drop the decorative motion.

**No screen-reader affordance, 0 of 85.** No clock carries an `aria-label`,
`role` or `aria-live` region. Adding `aria-live="polite"` plus a plain-text
time to the readout element would make the collection usable non-visually
without changing any visual design. Worth doing on the utility clocks at
minimum, where people actually depend on the time.

**Google Fonts without `preconnect`, 67 files.** 67 clocks pull webfonts from
`fonts.googleapis.com`, none with a `preconnect` hint to
`fonts.gstatic.com`. Two lines per file removes a round trip on first paint.
Some clocks request three or four families at several weights each, which is
worth trimming where the design does not use them all.

**rAF driving once-per-second text.** 29 DOM-only clocks (no canvas) run an
rAF loop. Many genuinely animate and should stay, but some only repaint whole
seconds. `retro/macos_clock` is the clear-cut case: it calls
`toLocaleDateString` and rewrites two elements 60 times a second to display a
value that changes once a second. `CLAUDE.md` already prescribes the right
pattern for these ("simple digit/text clocks: `setInterval(updateClock, 1000)`").
Worth a quick pass over `bach`, `clarke`, `finnegans_wake`,
`slaughterhouse_five` and `macos` to see which can drop to an interval.

**Dark mode.** Only `ng26_clock` and `ng26_countdown` respond to
`prefers-color-scheme`, and both are archive candidates (see 2.1), which would
take the collection to zero. `CLAUDE.md` is right that literary and art clocks
are intentionally locked to a themed palette, so this is really a note about
the utility and retro tiers: `binary`, `flip`, `latex`, `ascii`,
`conference_clock` and `timeline_clock` are all palette-neutral enough to
support both schemes.

### 1.2 Specific clocks

**`art/xyz_clock.html` needs the most work of any single file.** Four issues:

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

**`retro/macos_clock.html` is described inaccurately in the gallery.**
`index.html` sells it as "A System 6 tribute with draggable windows." The file
contains no `mousedown`, no drag logic and no window chrome at all, just one
static centred `.clock-screen` div. Either build the draggable window (the
better outcome, it is a good idea) or correct the description. It also uses
`background-attachment: fixed`, which iOS Safari ignores.

**The two "life" clocks miscount the grid.** Both `life_clock` and
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

**`nature/circadian_clock.html` has an undocumented network dependency.** It
POSTs the user's exact coordinates to `nominatim.openstreetmap.org` for
reverse geocoding. The call is correctly wrapped in `.catch()` and degrades to
raw coordinates, so it is not a bug, but it is a third-party service not listed
in `CLAUDE.md`, it sends precise location off-device, and OSM's usage policy is
not really written for anonymous browser traffic from a static site. At minimum
it deserves a line in `CLAUDE.md`; ideally the clock would say where the name is
coming from, or drop the lookup and show coordinates.

**`CLAUDE.md`'s CDN inventory is wrong in two ways.** It states "Three.js +
OrbitControls (3D sundial)". The 3D sundial (`nature/sundial_clock.html`) does
**not** load OrbitControls at all; the only OrbitControls user is
`art/xyz_clock.html`, and it loads it from Skypack rather than the documented
CDN. Three.js is also pinned to r128, which is several major versions behind.
Worth correcting the doc and deciding whether to bump the pin.

**Unoptimised raster assets.** `retro/os6.png` is 398 KB and
`retro/old_clock_face.jpg` is 172 KB, 570 KB of images for two clocks in a repo
whose next-largest file is a 54 KB HTML page. Both compress substantially at no
visible cost; `os6.png` in particular is a flat-colour System 6 desktop that
should be a fraction of that size.

**Thin gallery descriptions.** The literary rows read well ("Meursault's
indifference, the Algerian sun, the murder on the beach"). Much of `art`,
`simulation` and `retro` does not: "A clock that periodically glitches and
distorts", "A particle system based clock", "Time displayed in binary format",
"A simulation of flocking behavior". Because `index.html` builds its search
index from row text, weak descriptions also make those clocks harder to find.
Roughly 20 rows would benefit from a rewrite at the standard the literary
section already sets.

---

## 2. Clocks that could be archived

### 2.1 `utility/ng26_countdown.html` and `utility/ng26_clock.html`, expired

Both are branded "NeuroGateways '26" and hardcode
`new Date('2026-04-09T00:00:00')` for an event dated "April 9–10, 2026". That
was over five months ago. `ng26_countdown` now permanently displays
"The conference has begun", which is the graceful-degradation path but is
simply wrong today, and the gallery advertises it as "A countdown timer".

These are the strongest archive candidates in the collection: single-event
artifacts whose event has passed. Worth noting they are also the only two
clocks with dark mode support, so it is worth lifting that pattern out before
retiring them.

### 2.2 `art/solitude_clock.html` or `art/one_hundred_years_clock.html`, duplicates

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

### 2.3 `utility/life_clock.html`, strict subset

`life_zoom_clock` is a superset: identical `TOTAL_YEARS`/`WEEKS_PER_YEAR`/
`TOTAL_WEEKS` constants, identical week arithmetic, the same date input and the
same `localStorage` persistence, plus scroll and pinch zoom, drag-to-pan, zoom
buttons and per-week date tooltips. There is nothing `life_clock` does that
`life_zoom_clock` does not. Two adjacent gallery rows for the same grid is
mostly a choice the visitor should not have to make.

### 2.4 `art/xyz_clock.html`, superseded concept

Setting aside the bugs in 1.2, the concept is "time mapped to X, Y, Z
coordinates", which `art/coordinate_clock.html` already contains as one mode
among many: it assigns Y/Mo/D/H/Mi/S to axes across Cartesian, polar,
parabolic, elliptic, cylindrical and spherical space, in 969 lines to
`xyz_clock`'s 133. Either retire `xyz_clock`, or give it a reason to exist that
`coordinate_clock` does not cover, namely the 12-hour trail, which is genuinely
distinctive and is currently the broken part.

### 2.5 Consolidate the flocking quartet, four files to one

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

**Net effect if all of the above is actioned:** 85 clocks to 78, with no
concept lost.

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

1. Archive the two expired NG26 clocks (lift their dark mode pattern first).
2. Resolve the three duplicate pairs: the two Márquez clocks, the two life
   clocks, `xyz_clock` against `coordinate_clock`.
3. Consolidate the flocking quartet.
4. Sweep HiDPI scaling across the 23 canvas clocks.
5. Add `prefers-reduced-motion` handling to the 53 animated clocks.
6. Fix the 4,680-week grid arithmetic and the `macos_clock` description.
7. Correct the CDN inventory in `CLAUDE.md` and `GEMINI.md`.
8. Rewrite the ~20 thin gallery descriptions.
9. Then build: World Clock first, it fills the largest gap.
