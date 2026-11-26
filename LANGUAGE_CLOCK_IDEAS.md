# Language Clock Ideas

A ranked backlog of programming-language clocks, and below them of clocks that
illustrate mathematical concepts. The language clocks are clocks where a language's own way
of running, or its notation, decides how the time is worked out and shown. Each one
runs real code in the page, shows the program beside its output, and gives the
visitor a way to type in that language. The house rules are in `CLAUDE.md` under
"Language clocks".

Most of the concepts come from the blog post
[Programming-Language Clock Concepts](https://markbolding.blogspot.com/2026/11/programming-language-clock-concepts.html);
the rest were suggested alongside it. The engine checks below were made in November
2026: versions, licences and sizes from the npm registry, licences of GitHub-only
projects from their repositories or the APL Wiki. npm sizes are unpacked package
sizes, much larger than what a page actually downloads.

## Built

- ✅ **J** — `clocks/retro/j_clock.html`, the J Playground's WebAssembly build
- ✅ **BQN** — `clocks/retro/bqn_clock.html`, the reference `bqn.js`
- ✅ **Forth** — `clocks/retro/forth_clock.html`, WAForth
- ✅ **Prolog** — `clocks/retro/prolog_clock.html`, Tau Prolog
- ✅ **Lisp** — `clocks/retro/lisp_clock.html`, BiwaScheme
- ✅ **GLSL** — `clocks/retro/glsl_clock.html`, the browser's own WebGL compiler; every pixel computes its signed distance to the hands from `u_time`, with the distance field to view and the shader to edit; four shaders: classic, ink wash, metaballs and a raymarched brass dial
- ✅ **SQL** — `clocks/retro/sql_clock.html`, sql.js (SQLite in WebAssembly, MIT); three views, the face a recursive CTE over a grid of cells
- ✅ **6502 assembly** — `clocks/retro/mos6502_clock.html`, an emulator and assembler written in the page; a KIM-1-style six-digit LED display, a once-a-second interrupt counted in decimal mode, and the listing replaying each tick
- ✅ **Befunge-93** — `clocks/retro/befunge_clock.html`, an interpreter written in the page; the pointer circles a three-row program that writes the time into its own row 1 with `p`, the seconds row read right to left

## Tier 1: light, no licence questions, or an engine written in the page

These are the next to build. An engine written in the page means no download, no
CDN and nothing to licence, and for the small languages here it is also the best
way to show the machine working.

1. **Logo** — engine: write it. A turtle draws the dial and hands afresh every
   second (`REPEAT 60 [FD 5 BK 5 RT 6]`), with the turtle and its trail visible.
   A small Logo subset is enough.
2. **K** — engine: [oK](https://aplwiki.com/wiki/OK) by John Earnest, a JavaScript
   K5/K6 interpreter, MIT. Not on npm, so load it from a pinned GitHub commit
   through jsDelivr, as `j_clock` does. The concept: the whole clock and a rolling
   tick log (`09:30:00.000`) in about 40 characters.
3. **APL** — engine: [ngn/apl](https://aplwiki.com/wiki/Ngn/apl), JavaScript, MIT
   according to the APL Wiki (licence file not seen); main repository
   `abrudz/ngn-apl`. The concept: `24 60 60 ⊤ ⌊ ⎕TS`, `⍳60` reshaped into `12 5 ⍴`,
   with a toggle between blackboard notation and executable APL. Close kin to the
   J and BQN clocks, so it should look different from both.
4. **Lua** — engine: wasmoon 1.16 (the real Lua compiled to WebAssembly, MIT,
   about 0.5 MB) or Fengari (Lua written in JavaScript, MIT). Lua is PICO-8's
   language, so a PICO-8-style 128 x 128 clock suits it.
5. **Regular expressions** — engine: the browser's own. A clock where the time is
   whatever a regex matches in a long string, with the match highlighted, or a
   regex that only accepts valid times. Nothing to load.
6. **BASIC** — engine: write it. Line numbers, `PRINT`, `GOTO 10`, a cursor
   blinking on a 40-column screen.
7. **Brainfuck** — engine: write it. Eight instructions and a tape; the tape cells
   holding hours, minutes and seconds are shown as the program runs.
8. **PostScript** — engine: write a subset (the operand stack, `moveto`, `lineto`,
    `rotate`, `gsave`/`grestore`, `stroke`) that draws onto a canvas, showing the
    live operand stack and the current transformation matrix for each fresh page.
    The full interpreter, Ghostscript, is AGPL-3.0, so it is not an option.
9. **AWK** — engine: write a subset of `pattern { action }` rules over a stream of
    timestamp lines, highlighting which rules fire on second, minute and hour
    rollovers. The browser builds of GNU awk (gawk-web, awkjs, webawk) are GPL.
10. **Factor** — engine: write a small subset. No browser runtime was found. The
    concept: quotations and `bi`/`tri`/`cleave` turning stack effects into
    pipelines. The most work in this tier, and it overlaps with the Forth clock.

## Tier 2: real engines, but heavy or new

Worth doing for the right concept, after a proper trial of the engine.

- **Smalltalk** — engines: SqueakJS 1.0.31, which runs real Squeak images (MIT by
  its repository; npm lists it as GPL-3.0, so check before using), or Amber 0.32,
  Smalltalk compiled to JavaScript (MIT, 4.2 MB unpacked). A Squeak image is
  megabytes. The concept: every part of the clock (`Hand`, `Dial`, `Tick`) is a
  live object to inspect and message, `secondHand color: Color red`.
- **Erlang / Elixir** — engine: Popcorn 1.0.2 (Elixir on AtomVM in WebAssembly,
  Apache-2.0, about 6 MB unpacked), new as of late 2026. The concept: Hours,
  Minutes and Seconds processes passing tick messages, with a supervisor tree and
  mailbox view. Could be imitated in JavaScript if Popcorn proves too heavy.
- **Python** — engine: Pyodide (MPL-2.0, about 14 MB unpacked). A `datetime` clock
  drawn with turtle-style graphics; recognisable, but a large download.

## Tier 3: not practical as a real-engine clock

- **Elm** — there is no supported in-browser Elm compiler, only experiments
  (Brian Carroll's WebAssembly fork; Ellie moved its compiler back to a server).
  The concept (time as a signal, `Time.every 1000`, piped through pure functions
  into SVG, with a live dataflow graph) would have to be imitated in JavaScript.
- **Ruby** — ruby.wasm is over 100 MB unpacked.

## Mathematical concept clocks

Clocks that show a piece of mathematics working, with the time as its input. They
are not language clocks: most need nothing but plain JavaScript and a canvas, so
they would go in `clocks/simulation/` or `clocks/art/` rather than beside the
interpreters. Several would pair well with a language clock, noted where it fits.
The gallery already covers Fourier series (`epicycle_clock`), differential
equations (`ode_clock`), chaos (`pendulum_clock`), binary (`binary_clock`) and
polar and Cartesian coordinates (`polar_clock`, `coordinate_clock`), so these
avoid them.

Ordered the same way as the tiers above: light and self-contained first.

1. **Times tables on a circle** — modular arithmetic, the clock's own arithmetic.
   Sixty points round the dial; join each point *k* to *k × m* mod 60, where the
   multiplier *m* drifts with the time. At *m* = 2 the chords draw a cardioid, at
   3 a nephroid, and between whole numbers they melt from one into the next. The
   hour sets the multiplier and the minute its fractional part; a sweeping second
   hand still tells the time on top.
2. **Tower of Hanoi** — recursion and the binary reflected Gray code. Seventeen
   discs need 2^17 − 1 = 131,071 moves, the smallest tower that outlasts the day's
   86,400 seconds (sixteen discs run out at 65,535). Move one disc each second
   from midnight. The disc to move on step *k* is given by the trailing zeros of
   *k*, and the whole position can be read off the Gray code of the seconds since
   midnight, so the puzzle's state is the time. A Prolog or Lisp version of the
   recursive solution would fit beside it.
3. **Prime factorisation** — the fundamental theorem of arithmetic. Seconds since
   midnight, factorised every second and drawn as a factorisation diagram: primes
   as rings of dots nested inside each other, so noon, 43,200 seconds, is
   2^6 × 3^3 × 5^2 nested rings, while a prime second is one plain circle of dots. A small counter of the primes passed so far today.
4. **Fibonacci and Zeckendorf** — every whole number is a sum of non-consecutive
   Fibonacci numbers, in exactly one way. Squares of side 1, 1, 2, 3 and 5, after
   Philippe Chrétien's Fibonacci Clock, coloured by whether they count towards the
   hours, the minutes, or both; a strip below writes the seconds since midnight in
   Zeckendorf form.
5. **Permutations and the factorial number system** — 9! = 362,880 is the first
   factorial above 86,400, so every second of the day is a different ordering of
   nine cards. The seconds since midnight, written in factorial base, is the
   Lehmer code of that ordering; the cards reshuffle by the fewest swaps each
   second.
6. **Babylonian sexagesimal** — base 60, the reason there are sixty minutes. The
   time in cuneiform-style wedges, with the place-value columns marked, and the
   same positional idea applied to the fraction of the day elapsed (the
   Babylonians wrote fractions in base 60 too).
7. **Space-filling curve** — the day as one unbroken path through a square. A
   Hilbert curve of order 9 has 4^9 = 262,144 cells, the first order with more
   than 86,400 (order 8 has 65,536), so each second fills a cell and the day fills
   a third of the square, with nearby times always nearby on the page. A Logo
   version, a turtle following the curve's L-system, would pair with it.
8. **Collatz sequences** — the 3n + 1 problem. Start from the seconds since
   midnight and follow the sequence down to 1, drawn as a branching path that
   grows a new twig every second; show the number of steps and the highest value
   reached. Unproved, which is the point.
9. **Continued fractions** — the fraction of the day elapsed, expanded as a
   continued fraction, with its best rational approximations converging on it and
   its path down the Stern–Brocot tree drawn as a sequence of left and right
   turns.
10. **Ulam spiral** — the whole numbers wound outwards in a square spiral, with
    the primes lit. The seconds since midnight walk outwards along it, and the
    diagonal streaks of primes emerge as the day goes on.
11. **Julia sets** — complex dynamics. The constant *c* travels round a circle in
    the complex plane once a day (or once an hour), so the Julia set breathes
    from dust to dendrite and back; the hands are drawn as *c* itself. A natural
    fifth shader for the GLSL clock.
12. **The time in π** — where today's HHMMSS first appears in the decimal digits
    of π. Most six-digit strings first turn up within the first few million
    digits, which a page can't compute every second, so this needs a precomputed
    table of first positions for all 86,400 times, a data file of a few hundred
    kilobytes beside the clock. The heaviest here.

## Before building one

- Check the engine's licence in its own repository, not only on npm; they can differ.
- Pin an exact version or commit, at least two weeks old, and load it from cdnjs
  if it is there, otherwise jsDelivr.
- Test without trusting the CDN: serve the same files locally in Playwright, as
  the Lisp and SQL clocks were tested.
- When one is built, move it to **Built** above, add its notes to `CLAUDE.md` and
  `GEMINI.md`, and give it a row beside the other language clocks in `index.html`.
