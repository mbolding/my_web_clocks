# Language Clock Ideas

A ranked backlog of programming-language clocks: clocks where a language's own way
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
- ✅ **GLSL** — `clocks/retro/glsl_clock.html`, the browser's own WebGL compiler; every pixel computes its signed distance to the hands from `u_time`, with the distance field to view and the shader to edit
- ✅ **SQL** — `clocks/retro/sql_clock.html`, sql.js (SQLite in WebAssembly, MIT); three views, the face a recursive CTE over a grid of cells
- ✅ **6502 assembly** — `clocks/retro/mos6502_clock.html`, an emulator and assembler written in the page; a KIM-1-style six-digit LED display, a once-a-second interrupt counted in decimal mode, and the listing replaying each tick

## Tier 1: light, no licence questions, or an engine written in the page

These are the next to build. An engine written in the page means no download, no
CDN and nothing to licence, and for the small languages here it is also the best
way to show the machine working.

1. **Befunge-93** — engine: write it. Watch the instruction pointer walk an ASCII
   grid (`>`, `v`, `<`, `^`) on a torus to count the time. The interpreter is tiny,
   and the page has to draw the moving pointer anyway. npm has `befunge93` (ISC)
   and `befunge` (MIT), but writing one is easier than adapting them.
2. **Logo** — engine: write it. A turtle draws the dial and hands afresh every
   second (`REPEAT 60 [FD 5 BK 5 RT 6]`), with the turtle and its trail visible.
   A small Logo subset is enough.
3. **K** — engine: [oK](https://aplwiki.com/wiki/OK) by John Earnest, a JavaScript
   K5/K6 interpreter, MIT. Not on npm, so load it from a pinned GitHub commit
   through jsDelivr, as `j_clock` does. The concept: the whole clock and a rolling
   tick log (`09:30:00.000`) in about 40 characters.
4. **APL** — engine: [ngn/apl](https://aplwiki.com/wiki/Ngn/apl), JavaScript, MIT
   according to the APL Wiki (licence file not seen); main repository
   `abrudz/ngn-apl`. The concept: `24 60 60 ⊤ ⌊ ⎕TS`, `⍳60` reshaped into `12 5 ⍴`,
   with a toggle between blackboard notation and executable APL. Close kin to the
   J and BQN clocks, so it should look different from both.
5. **Lua** — engine: wasmoon 1.16 (the real Lua compiled to WebAssembly, MIT,
   about 0.5 MB) or Fengari (Lua written in JavaScript, MIT). Lua is PICO-8's
   language, so a PICO-8-style 128 x 128 clock suits it.
6. **Regular expressions** — engine: the browser's own. A clock where the time is
   whatever a regex matches in a long string, with the match highlighted, or a
   regex that only accepts valid times. Nothing to load.
7. **BASIC** — engine: write it. Line numbers, `PRINT`, `GOTO 10`, a cursor
   blinking on a 40-column screen.
8. **Brainfuck** — engine: write it. Eight instructions and a tape; the tape cells
   holding hours, minutes and seconds are shown as the program runs.
9. **PostScript** — engine: write a subset (the operand stack, `moveto`, `lineto`,
    `rotate`, `gsave`/`grestore`, `stroke`) that draws onto a canvas, showing the
    live operand stack and the current transformation matrix for each fresh page.
    The full interpreter, Ghostscript, is AGPL-3.0, so it is not an option.
10. **AWK** — engine: write a subset of `pattern { action }` rules over a stream of
    timestamp lines, highlighting which rules fire on second, minute and hour
    rollovers. The browser builds of GNU awk (gawk-web, awkjs, webawk) are GPL.
11. **Factor** — engine: write a small subset. No browser runtime was found. The
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

## Before building one

- Check the engine's licence in its own repository, not only on npm; they can differ.
- Pin an exact version or commit, at least two weeks old, and load it from cdnjs
  if it is there, otherwise jsDelivr.
- Test without trusting the CDN: serve the same files locally in Playwright, as
  the Lisp and SQL clocks were tested.
- When one is built, move it to **Built** above, add its notes to `CLAUDE.md` and
  `GEMINI.md`, and give it a row beside the other language clocks in `index.html`.
