# To do

## Widget ideas

Common desktop widgets that would sit well beside the ones here. Each would be a new folder and a line in `build.sh`'s `CLOCKS` table. Draw highlights with the shared `accent`, and avoid Swift macros (`@Observable`, `@Entry`, `#Preview`), since the command-line tools can't build them.

- **System Stats.** CPU, memory, battery and network speed as small rings or sparklines, from `host_statistics`, IOKit and `getifaddrs`. No permissions needed.

## Little app ideas

Small apps that are a bit more than widgets: ordinary windowed apps with a menu bar and Dock icon, built like Map Browser (an ordinary SwiftUI `App`, with `LSUIElement` and `DesktopWidget` set to false in its `InfoPlistExtras.xml`), and each a line in `build.sh`'s `CLOCKS` table. The same rule on Swift macros applies.

- **Fourier Epicycles.** Draw a closed curve, or drop an SVG path, and watch a chain of rotating circles trace it, with a slider for how many terms to keep, so the outline sharpens from an ellipse as terms are added. A discrete Fourier transform of the resampled points gives the circles, biggest first. Save the trace as SVG or PNG like Stipple.
- **Orrery.** The planets where they are today, from Kepler's orbital elements (JPL's approximate elements, good to a fraction of a degree for 1800–2050), with a date scrubber and play speeds, and Polyhedra's turntable to tilt the view out of the ecliptic. Inner and outer planets want separate zooms, or a log scale for distance. The Moon and its phase would follow from the same maths.

## Future ideas

- **Replicants, after BeOS.** Drag part of a widget (Soma Player's now-playing line, the stopwatch readout) out onto the desktop to make it a small live window of its own, perhaps by a hand-like grip shown on hover; drop one on Widget Bar to dock it there, like the Deskbar's tray. Each piece would be another `DesktopPanel` in the same app, opened when a drag ends outside the window and restored at launch. Unlike Be's, a piece closes when its app quits, since macOS apps can't host each other's views.
- **Dock-only apps.** Apps with no window at all, whose Dock icon is the whole app: draw into `NSApp.dockTile.contentView` and call `display()` when it changes (once a second at most). Dock Clock (`Dock/`) was the first, and Dock Load (`Load/`, CPU load and memory pressure) the second. Next perhaps the moon's phase or a countdown. Each shows its Dock icon rather than being `LSUIElement` (set in its `InfoPlistExtras.xml`) and only draws while running; a Dock tile plug-in (`NSDockTilePlugIn`, as Calendar uses for its date) to keep drawing when closed can wait. Candidates:
  - *Status:* battery (a ring, with a bolt while charging), network speed, free disk space (in the accent when low), days since the last Time Machine backup.
  - *Time:* moon phase, a countdown to a date set from the Dock menu, the sun's place on a day arc, a second time zone, the week number or day of the year.
  - *Controlled from the icon:* Dock Timer (a wedge counting down, with presets in the Dock menu, bouncing when done) and Dock Stopwatch (click to start and stop).
  - *Dropped onto the icon:* a file shelf with a count badge, an image resizer that writes to the Desktop, and Text Extractor putting the text on the clipboard.
  - *Fun:* a Dock pet that sleeps at night, weather (needs location and a network call), and Soma Player's now playing with a click to pause.
  - Moon Phase and Dock Timer are the easiest next ones.
- **Menu bar items.** SwiftUI's `MenuBarExtra` scene (macOS 13+, not a macro) shows a symbol or short label that opens a menu, or a small window with `.menuBarExtraStyle(.window)`; set `LSUIElement` for a menu-bar-only app, or add one to an existing widget. Keep each item narrow, since items that don't fit on a notched MacBook are hidden, and keep to text and symbols, since the bar is about 22 points tall and drawn in one colour. Candidates:
  - *Readouts:* Dial Timer's time left (or the stopwatch) with presets in its menu, a second time zone ("LON 18:42"), a countdown ("Trip 12d"), a CPU sparkline or memory percentage, and the moon phase from the `moonphase.*` SF Symbols.
  - *Plain Paste:* a menu item, and a shortcut, that strips the clipboard to plain text, by reading `NSPasteboard`'s `.string` and writing it back alone. Options could trim whitespace, straighten curly quotes and drop tracking parameters from URLs.
  - *Widgets as menus:* Soma Player with play and pause and a station list, Scratch Pad as a drop-down window, and Widget Bar showing and hiding the widgets and flipping Float on Top.
  - Server List was the first, and is now only a menu bar item (`Servers/`). Dial Timer's readout and Soma Player as a menu are the best next tries.
- **Tailscale.** Every device here is on the tailnet, and the CLI inside the app, `/Applications/Tailscale.app/Contents/MacOS/Tailscale` (it isn't on the `PATH`), answers `status --json` without root: each peer's name, OS, Tailscale IPs, `Online`, `LastSeen`, whether the connection is direct (`CurAddr`) or relayed (`Relay`, the DERP region), bytes sent and received, and whether it offers an exit node or takes Taildrop. Read it every few seconds, as Dock Load runs `ps`. Candidates:
  - *Server List from the tailnet:* fill Server List from `status --json` instead of by hand, so new devices appear by themselves, Macs open Screen Sharing and Linux machines open SSH, and offline ones are greyed with when they were last seen. The best first step, since the app is already there.
  - *Dock Tailnet:* a ring of dots on the Dock icon, one per device, lit while it's online, with a count badge; the Dock menu lists them to copy an address or open them.
  - *Taildrop shelf:* drop files on a Dock icon and pick a device from the menu to send them with `file cp`, and pull waiting files into Downloads with `file get`.
  - *Tailnet ping:* `ping` each online peer and draw the latencies, marking which are direct and which go through a relay, to see why one connection is slow.
  - *Exit node switcher:* a menu bar item listing the exit nodes on offer, with a tick by the one in use and None at the top.
  - *Serve a folder:* share a folder, or this repo's clocks, to the other devices with `serve`, so they open on the phone at the Mac's tailnet name.
- **rsync.net and SDF.** A lifetime rsync.net account (private storage, reached over SSH, with ZFS snapshots and no public links) and an SDF shell account (which serves a web site and a gopher hole to anyone) cover each other's gaps. Both speak SSH, so the apps should run the Mac's own `ssh`, `scp` and `rsync` against host aliases in `~/.ssh/config` with a key, and never store a password. Chosen:
  - *Courier:* one drop target, a Dock icon like the Dock-only apps above, that sends what's dropped on it to one of three places picked from its menu: a tailnet device by Taildrop, rsync.net for keeping, or SDF for a public link copied to the clipboard. Its Dock menu lists the last few sends, to copy a link again or reveal where a file went; a badge counts sends still under way.
  - *Scratch Pad and Markdown Editor on rsync.net:* keep Scratch Pad's text and a Markdown Editor folder on rsync.net, so every Mac has the same ones. Pull on launch and push on save (after a short pause, like Stipple's debounce), keep a local copy for working offline, and if both sides changed, keep both rather than guess. The ZFS snapshots are the undo history for free.
  - *Publish to SDF:* a Publish item in Markdown Editor that renders the document to HTML (with a small fixed stylesheet) and copies it into the SDF web folder, then copies the page's URL; Stipple and Polyhedra get a Share item that does the same for their PNG or SVG. Republishing the same document replaces its page rather than making a new one.
