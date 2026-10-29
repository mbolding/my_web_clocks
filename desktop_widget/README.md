# Desktop widgets for macOS

Small native Mac apps that float on the desktop: frosted, borderless windows that sit just above the desktop icons (or above every window, with Float on Top), show on every Space, and stay out of the Dock and menu bar. They're written in SwiftUI and built with a single script, so you don't need Xcode itself.

| App | What it is |
| --- | --- |
| **Clock Widget** (`Analog/`) | An analog clock with the weekday and date; second hand optional |
| **Word Clock** (`Word/`) | The time spelled out on an 11×11 letter grid, a native port of [`clocks/art/word_clock.html`](../clocks/art/word_clock.html) |
| **Command Bar** (`Command/`) | A floating zsh you can type into and drop folders onto, with history, Tab completion and the current git branch |
| **Soma Player** (`Soma/`) | A small [SomaFM](https://somafm.com) radio with a channel menu and what's playing |
| **Dial Timer** (`Timer/`) | A round, up-to-an-hour timer: drag the face to set it, and a coloured wedge shows the time left |
| **Month Calendar** (`Calendar/`) | This month's calendar, with today picked out |
| **Widget Bar** (`Launcher/`) | A small toolbar of the other widgets: open them, see which are running, and flip their Float on Top |

## Requirements

- A Mac with Apple Silicon, running macOS 14 (Sonoma) or newer
- Apple's command-line tools, for the Swift compiler. If `swiftc --version` doesn't print a version, run:

  ```bash
  xcode-select --install
  ```

## Install

Clone the repo and run the build script with `--install`:

```bash
git clone https://github.com/mbolding/my_web_clocks.git ~/repos/my_web_clocks
cd ~/repos/my_web_clocks
desktop_widget/build.sh --install
```

This builds every app, copies each to `~/Applications`, registers it with macOS (for Command Bar's Finder action), and launches it. To install only some, name their folders, in any case:

```bash
desktop_widget/build.sh command soma --install
```

Other forms:

| Command | Does |
| --- | --- |
| `desktop_widget/build.sh` | Builds every app into `desktop_widget/build/` without installing |
| `desktop_widget/build.sh word --run` | Builds one and launches it from `build/` |
| `desktop_widget/build.sh --install` | Builds, installs to `~/Applications` and launches |

### Update

```bash
cd ~/repos/my_web_clocks && git pull && desktop_widget/build.sh --install
```

Installing quits the running copy first and starts the new one. Window positions and settings are kept.

### Start at login

The apps don't add themselves to login. Add the ones you want under **Open at Login** in **System Settings → General → Login Items** (**Login Items & Extensions** on newer macOS), choosing them from the Applications folder in your home folder.

### Copying a built app to another Mac

Building on each Mac is simplest. If you'd rather copy `~/Applications/<App>.app` across (AirDrop, iCloud Drive, a USB stick), macOS will first refuse to open it, because it's signed only for the Mac that built it. Either click **Open Anyway** in **System Settings → Privacy & Security**, or clear the download flag before opening it:

```bash
xattr -dr com.apple.quarantine ~/Applications/CommandBar.app
```

## Using them

All of them:

- **Drag** the window to move it (on Command Bar, by its folder bar; on Dial Timer, by its rim); the position is remembered.
- **Right-click** for the app's options, **Accent Color**, **Float on Top**, and **Quit**.
- **Accent Color** sets the highlight colour (the second hand, the timer's wedge, the pins and so on) for all of them at once. It starts as orange; **Match System** follows the accent colour in System Settings → Appearance.
- Windows with a **pin** (Command Bar, Soma Player, Dial Timer, Widget Bar) show whether they float on top; click it to switch.
- Opening a widget that's already running (from Widget Bar's Show, Finder, or `open -a`) brings its window up above everything for a few seconds, so you can find it.
- They follow the system's light or dark appearance.

**Command Bar**

- Type a command and press Return. It runs in your login zsh, with `.zshrc` sourced, so `cd`, variables and aliases carry over between commands.
- Send it a folder by dropping the folder (or a file inside it) on the window, by right-clicking it in Finder and choosing **Open in Command Bar**, or from a terminal with `open -a "Command Bar" .`
- **↑ / ↓** history, **Tab** completes commands and file names, **⌃C** stops a command (twice replaces the shell), **⌘K** clears.
- It isn't a full terminal: full-screen and interactive programs (`vim`, `top`, `less`, password prompts) won't work, and colours are stripped.
- Floats on top by default; the window resizes from its edges.

**Soma Player**

- Pick a channel from the menu on its name and press play. It shows up in Control Center and answers the keyboard's play/pause key.
- It never starts playing on its own. SomaFM is listener-supported; the right-click menu has a link to [support it](https://somafm.com/support/).

**Dial Timer**

- Drag around the face to set whole minutes, up to 60; letting go starts it. Drag back to 0 to clear it.
- Tap the middle to pause or resume. When it's done it rings a bell every two seconds, for up to a minute, until you tap to dismiss it.
- The right-click menu has preset times, Reset, and **Chime When Done**. While idle, the middle shows the time of day.
- A running timer carries on if the app quits or the Mac restarts.

**Widget Bar**

- Shows every installed widget, found when it starts; restart it to pick up a newly installed one. It floats on top by default and starts at the bottom right.
- The dot under an icon is grey while that widget runs on the desktop and in the accent colour while it floats on top; no dot means it isn't running.
- Click a widget that isn't running to open it. Click a running one to flip its Float on Top.
- Right-click an icon to float it or put it on the desktop, **Show** it for a few seconds, or quit it.
- The **›** at the right end folds the bar into a small square at its right edge, to get it out of the way; click the square to open the bar again. It stays folded or open across restarts.

**Clock Widget** has a **Show Seconds** option in its right-click menu.

**Month Calendar** shows the current month, its weeks starting on the first day of the week set in System Settings, with weekends greyed and today on a circle of the accent colour. It moves on to the next day, and month, by itself. Click a day to open that week in Google Calendar, in Chrome (or your default browser if Chrome isn't installed). It starts just left of Clock Widget.

## Uninstall

Quit the app from its right-click menu, delete it from `~/Applications`, and if you like, remove its saved settings:

```bash
defaults delete com.mbolding.commandbar
```

The settings domains are `com.mbolding.clockwidget`, `com.mbolding.wordclock`, `com.mbolding.commandbar`, `com.mbolding.somaplayer`, `com.mbolding.dialtimer`, `com.mbolding.monthcalendar` and `com.mbolding.widgetbar`, plus `com.mbolding.desktopwidgets` for the accent colour they share.

## How it's put together

```
desktop_widget/
├── build.sh        the build script; lists every app in its CLOCKS table
├── Shared/         the floating window, right-click menu, FloatPin, the accent colour, and the icon renderer
├── Analog/         App.swift, Icon.swift, ClockFace.swift; Widget/ is a parked WidgetKit version
├── Word/           App.swift, Icon.swift, WordFace.swift
├── Command/        App.swift, Icon.swift, the view and shell session, InfoPlistExtras.xml
├── Soma/           App.swift, Icon.swift, the view and player
├── Timer/          App.swift, Icon.swift, the dial, its view, the timer and its chime
├── Calendar/       App.swift, Icon.swift, CalendarFace.swift
└── Launcher/       App.swift, Icon.swift, the bar and the launcher that finds and drives the widgets
```

Each app is a folder: `App.swift` holds the `@main` entry (window size and any extra menu items), `Icon.swift` draws its app icon, and the rest is its face. App icons are drawn at build time from the app's own SwiftUI code, so no image files are checked in. Draw highlights with the `accent` environment value rather than a fixed colour, so they follow the shared Accent Color setting; it falls back to orange where no window sets it, as in the app icons. An app can add keys to its `Info.plist` with an `InfoPlistExtras.xml` file, as Command Bar does for its Finder action. A window can be round (`round: true`, as Dial Timer is); if its face has drags of its own, turn off dragging by the background (`movableByBackground: false`) and put `MovesWindow` on the parts that should move it.

To add one: make a folder with those files, then add a line to the `CLOCKS` table in `build.sh` (folder, executable name, bundle id, display name). `build.sh` marks every app it builds with a `DesktopWidget` key in its `Info.plist`, which is how Widget Bar finds them, so a new widget appears on the bar once it's installed and the bar restarts. Each widget writes its `floatOnTop` setting to its own preferences domain and watches it, which is how the bar reads and flips it from outside.

The WidgetKit version of the analog clock in `Analog/Widget/` is only built when an Apple Development signing certificate is present, because macOS ignores widgets that aren't signed by one.
