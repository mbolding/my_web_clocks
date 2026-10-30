# To do

## Widget ideas

Common desktop widgets that would sit well beside the ones here. Each would be a new folder and a line in `build.sh`'s `CLOCKS` table. Draw highlights with the shared `accent`, and avoid Swift macros (`@Observable`, `@Entry`, `#Preview`), since the command-line tools can't build them.

- **System Stats.** CPU, memory, battery and network speed as small rings or sparklines, from `host_statistics`, IOKit and `getifaddrs`. No permissions needed.

## Little app ideas

Small apps that are a bit more than widgets: ordinary windowed apps with a menu bar and Dock icon, built like Map Browser (an ordinary SwiftUI `App`, with `LSUIElement` and `DesktopWidget` set to false in its `InfoPlistExtras.xml`), and each a line in `build.sh`'s `CLOCKS` table. The same rule on Swift macros applies.

- **Polyhedra.** Explore the five Platonic solids: pick one and turn it with a drag, show or hide faces, edges and vertices, and read off its faces, edges and vertices (and V − E + F = 2), Schläfli symbol, dihedral angle, and circumradius and inradius for a unit edge. A slider could morph each solid into its dual (cube to octahedron, dodecahedron to icosahedron, the tetrahedron to itself) through the truncations between them. SceneKit draws it without a CDN or macros, or a `Canvas` with its own projection keeps it flat-shaded and light.
- **Stipple.** A native take on [mbolding/stipplegen](https://github.com/mbolding/stipplegen), Evil Mad Scientist's Processing program: drop in an image and get a weighted Voronoi stipple drawing (Secord's method, Lloyd relaxation weighted by darkness), or join the dots into one continuous "TSP art" line (nearest-neighbour then 2-opt). Sliders for dot count and size, white cutoff and iterations, with the dots settling live, and Save as SVG for a pen plotter or PNG for everything else. Write it fresh in Swift rather than translating the code, since StippleGen is LGPL 2.1.

## Future ideas

- **Replicants, after BeOS.** Drag part of a widget (Soma Player's now-playing line, the stopwatch readout) out onto the desktop to make it a small live window of its own, perhaps by a hand-like grip shown on hover; drop one on Widget Bar to dock it there, like the Deskbar's tray. Each piece would be another `DesktopPanel` in the same app, opened when a drag ends outside the window and restored at launch. Unlike Be's, a piece closes when its app quits, since macOS apps can't host each other's views.
- **Dock-only apps.** Apps with no window at all, whose Dock icon is the whole app: draw into `NSApp.dockTile.contentView` and call `display()` when it changes (once a second at most). Dock Clock (`Dock/`) is the first. Next perhaps a CPU or memory graph like Activity Monitor's Dock icon, the moon's phase, or a countdown. Each shows its Dock icon rather than being `LSUIElement` (set in its `InfoPlistExtras.xml`) and only draws while running; a Dock tile plug-in (`NSDockTilePlugIn`, as Calendar uses for its date) to keep drawing when closed can wait. Candidates:
  - *Status:* battery (a ring, with a bolt while charging), network speed, free disk space (in the accent when low), days since the last Time Machine backup.
  - *Time:* moon phase, a countdown to a date set from the Dock menu, the sun's place on a day arc, a second time zone, the week number or day of the year.
  - *Controlled from the icon:* Dock Timer (a wedge counting down, with presets in the Dock menu, bouncing when done) and Dock Stopwatch (click to start and stop).
  - *Dropped onto the icon:* a file shelf with a count badge, an image resizer that writes to the Desktop, and Text Extractor putting the text on the clipboard.
  - *Fun:* a Dock pet that sleeps at night, weather (needs location and a network call), and Soma Player's now playing with a click to pause.
  - Moon Phase and Dock Timer are the easiest next ones.
- **Menu bar items.** SwiftUI's `MenuBarExtra` scene (macOS 13+, not a macro) shows a symbol or short label that opens a menu, or a small window with `.menuBarExtraStyle(.window)`; set `LSUIElement` for a menu-bar-only app, or add one to an existing widget. Keep each item narrow, since items that don't fit on a notched MacBook are hidden, and keep to text and symbols, since the bar is about 22 points tall and drawn in one colour. Candidates:
  - *Readouts:* Dial Timer's time left (or the stopwatch) with presets in its menu, a second time zone ("LON 18:42"), a countdown ("Trip 12d"), a CPU sparkline or memory percentage, and the moon phase from the `moonphase.*` SF Symbols.
  - *Widgets as menus:* Soma Player with play and pause and a station list, Scratch Pad as a drop-down window, and Widget Bar showing and hiding the widgets and flipping Float on Top.
  - Server List was the first, and is now only a menu bar item (`Servers/`). Dial Timer's readout and Soma Player as a menu are the best next tries.
