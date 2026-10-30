# Desktop widgets for macOS

Small native Mac apps that float on the desktop: frosted, borderless windows that sit just above the desktop icons (or above every window, with Float on Top), show on every Space, and stay out of the Dock and menu bar. Six are different: Dock Clock lives in its Dock icon, Server List lives in the menu bar, and Map Browser, Text Extractor, Markdown Editor and DICOM Viewer are ordinary apps with windows and a menu bar. They're written in SwiftUI and built with a single script, so you don't need Xcode itself.

| App | What it is |
| --- | --- |
| **Clock Widget** (`Analog/`) | An analog clock with the weekday and date; second hand optional |
| **Word Clock** (`Word/`) | The time spelled out on an 11×11 letter grid, a native port of [`clocks/art/word_clock.html`](../clocks/art/word_clock.html) |
| **Command Bar** (`Command/`) | A floating zsh you can type into and drop folders onto, with history, Tab completion and the current git branch |
| **Soma Player** (`Soma/`) | A small [SomaFM](https://somafm.com) radio with a channel menu and what's playing |
| **Dial Timer** (`Timer/`) | A round, up-to-an-hour timer: drag the face to set it, and a coloured wedge shows the time left. Also a stopwatch |
| **Month Calendar** (`Calendar/`) | This month's calendar, with today picked out |
| **Scratch Pad** (`Scratch/`) | A text pad that keeps what you type, with buttons to copy it all or save it to the Desktop |
| **Server List** (`Servers/`) | A menu bar item listing your Macs and servers: choose one to open Screen Sharing (`vnc://`) or an SSH session in Terminal (`ssh://`), like Finder's Go → Connect to Server |
| **Dock Clock** (`Dock/`) | An analog clock with no window: its live Dock icon is the whole app |
| **Map Browser** (`Maps/`) | An [OpenStreetMap](https://www.openstreetmap.org) browser, and an ordinary Mac app with windows, a menu bar and a Dock icon: search for places, save them, and switch between map styles |
| **Text Extractor** (`Extractor/`) | Another ordinary app: drop a PDF or Word document on it and it shows just the text, to select, copy or save as plain text |
| **Markdown Editor** (`Markdown/`) | A plain text editor for Markdown files, with light syntax colouring and no preview; an ordinary document app with New, Open, Save and window tabs |
| **DICOM Viewer** (`Dicom/`) | A viewer for DICOM medical images: open or drop files, folders or zip archives to see each series, scroll through its slices, change the window and level, and read the tags |
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

- **Drag** the window to move it (on Command Bar, by its folder bar; on Dial Timer, by its rim, or anywhere as a stopwatch); the position is remembered.
- **Right-click** for the app's options, **Accent Color**, **Float on Top**, and **Quit**. Clock Widget, Word Clock, Month Calendar and Soma Player also have **Behind Desktop Icons**, which tucks the widget under the icons with its frosted background faded almost away, so it sits on the desktop picture. Clicks there go to the desktop, so to bring it back, open the widget again (from Widget Bar or Finder): it comes to the front for a few seconds, long enough to right-click it. Widget Bar's float button brings it straight back too. Soma Player's media keys still work while it's behind the icons.
- **Accent Color** sets the highlight colour (the second hand, the timer's wedge, the pins and so on) for all of them at once. It starts as orange; **Match System** follows the accent colour in System Settings → Appearance.
- Widget Bar has a **pin** at its right end showing whether it floats on top; click it to switch.
- **⌘-click**, or **force click** on a trackpad, anywhere on a widget to flip its Float on Top. A force click doesn't also press what it lands on. While a widget floats on top, a thin edge in the accent colour runs around it, however the setting was changed: the menu, a click, a pin or Widget Bar.
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
- Click the stopwatch symbol below the middle, or choose **Stopwatch** in the right-click menu, to count up instead; the hourglass in its place switches back. Tap the middle to start, pause and resume; the arrow above the middle resets a paused one. A hand sweeps the seconds and a faint wedge fills with the minutes. A timer left running keeps going, and switches the dial back when it rings; a running stopwatch likewise carries on behind the timer, and across a quit or restart.

**Widget Bar**

- Shows every installed widget, found when it starts; restart it to pick up a newly installed one. It floats on top by default and starts at the bottom right.
- The dot under an icon is grey while that widget runs on the desktop and in the accent colour while it floats on top; no dot means it isn't running.
- Click a widget that isn't running to open it. Click a running one to flip its Float on Top.
- Right-click an icon to float it or put it on the desktop, **Show** it for a few seconds, or quit it.
- The **›** at the right end folds the bar into a small square at its right edge, to get it out of the way; click the square to open the bar again. It stays folded or open across restarts.

**Clock Widget** has a **Show Seconds** option in its right-click menu.

**Month Calendar** shows the current month, its weeks starting on the first day of the week set in System Settings, with weekends greyed and today on a circle of the accent colour. It moves on to the next day, and month, by itself. Click a day to open that week in Google Calendar, in Chrome (or your default browser if Chrome isn't installed). It starts just left of Clock Widget.

**Scratch Pad**

- Type or paste anything; it's kept as you type, across quits and restarts. The header shows the word count.
- The two buttons at the top right copy everything to the clipboard, and save it as a new Markdown file on the Desktop. The file is named after the first line, with its words joined by underscores and only letters, digits and underscores kept, so nothing in it means anything to the shell (`# Ideas for the weekend!` saves as `Ideas_for_the_weekend.md`, and `well-known` as `well_known`), or by the date and time (`Scratch_20261028_194512.md`) if the first line is empty. A number is added (`_2`, `_3`) rather than overwrite a file of the same name. **⌘S** saves too. The first save asks for access to the Desktop folder.
- The right-click menu (on the header; the text has its own) also has **Show Saved File in Finder** and **Clear**.
- Floats on top by default; the window resizes from its edges.

**Server List**

- It lives in the menu bar, as a server rack, with no window or Dock icon, and isn't on Widget Bar. Click it for the list.
- Choose a server to connect. Its address is handed to macOS, as Finder's **Go → Connect to Server** does: `vnc://` opens Screen Sharing, `ssh://` opens Terminal, and `smb://` or `afp://` mounts the share in Finder.
- Each item shows the host (or `user@host` for SSH) beside a display for Screen Sharing or a terminal for SSH.
- **Add Server…** adds one, typing its full address, such as `vnc://hostname` or `ssh://user@hostname`. **Remove** lists them by address to take one off. **Quit Server List** is at the bottom.
- It starts empty. The list is kept in its settings, so you can also set it in one go from a terminal:

  ```bash
  defaults write com.mbolding.serverlist servers -array vnc://my-mac ssh://me@my-mac
  ```

  A running Server List picks that up straight away.

**Dock Clock**

- Keep it in the Dock (right-click its icon → **Options → Keep in Dock**) and open it; the icon becomes the analog dial and keeps time while the app runs. When it quits, the Dock shows the plain icon again, since there's no Dock tile plug-in to draw it while closed.
- Right-click the Dock icon for **Show Seconds** (the dial redraws once a minute without it) and **Accent Color**, the same shared colour as the widgets.
- It has no window, so it isn't `LSUIElement` like the others, and Widget Bar doesn't list it. Quit it from the Dock icon or with **⌘Q** while it's active.

**Map Browser**

- Drag to move the map; pinch, scroll or double-click to zoom, or use the **−** and **+** buttons (**⌘−** and **⌘=**). **⌘N** opens another window, and each new window starts where you last looked.
- Type a name in the search field and press Return. Results come from OpenStreetMap's Nominatim, nearest to the map first, and are listed in the sidebar. The first is shown straight away; click another to go there. You can also type coordinates (`33.5, -86.8`), a `geo:` address, or paste an openstreetmap.org link.
- Click the map to pin that spot and name it from OpenStreetMap: the shop, building or street address there. Click elsewhere to move the pin.
- Right-click the map for **What's Here?** (names the spot under the pointer), **Drop Pin**, **Save as a Place…**, **Copy Coordinates** and **Report a Problem Here…**, which opens openstreetmap.org's note form.
- **⌘D** or the star saves the pin, or the middle of the map, under **Places** in the sidebar and in the Places menu. Right-click a place to rename or delete it, or drag places to reorder them.
- **View** has the map styles (**⌘1**–**⌘4**: Standard, Humanitarian, CyclOSM and OpenTopoMap), **Show My Location** (**⌘L**) and **Open in Web Browser**. **Edit** has **Copy Link to This View**.
- **Settings** (**⌘,**) picks the style new windows start with. It also has **Sharper map, with smaller text**, which draws tiles at half size so they're crisp on a Retina screen, and a button to clear the saved tiles.
- Map tiles are cached in `~/Library/Caches/com.mbolding.mapbrowser`. Every request names the app in its User-Agent, as the OpenStreetMap tile and search policies ask, and searches go one at a time, at most once a second.

**Text Extractor**

- Drop a PDF or Word document (`.docx` or `.doc`) on the window or the Dock icon, choose **File → Open…** (**⌘O**), or right-click the file in Finder and choose **Open With → Text Extractor**. RTF, OpenDocument and plain text files work too. A file dropped on the window replaces what it shows; files opened another way go to the front window if it's empty, and otherwise each get a window of their own (or a tab, if macOS is set to prefer tabs).
- The text is plain and can be selected, searched (**⌘F**) and edited before saving. The title shows the file's name, with its word and character counts below.
- **Copy All Text** (**⇧⌘C**) puts it all on the clipboard, and **Save as Text…** (**⌘S**) saves it as a `.txt` file, offering the original's name and folder. Both are also in the toolbar.
- A scanned PDF has pictures of its pages rather than text, so there's nothing to show; it says so, as it does for a password-protected PDF or a kind of file it can't read. It reads PDFs with PDFKit and the rest with `NSAttributedString`, so nothing is sent anywhere.

**Markdown Editor**

- An ordinary document app: **⌘N** for a new document, **⌘O** to open one, **⌘S** to save, and **File → Revert To** to go back to the last save. Open Recent, window tabs and version history work as in TextEdit. Drop files on its Dock icon or use Finder's **Open With**. It opens Markdown (`.md`, `.markdown`) and plain text files.
- There's no preview; the Markdown is coloured as you type. Headings are bold and larger, `*emphasis*`, `**strong**` and `~~strike~~` show as such, code spans and fenced code blocks are monospaced on a faint background, and link text, list markers, task boxes and quote markers take the accent colour. The markup itself stays visible, dimmed.
- Smart quotes, smart dashes and text replacement are off, since they change Markdown's own punctuation (**Edit → Substitutions** turns them back on for a window). A file is saved back in the encoding it was opened in.
- **View** has **Make Text Bigger** (**⌘=**), **Make Text Smaller** (**⌘−**) and **Make Text Normal Size** (**⌘0**). **Settings** (**⌘,**) picks a monospaced or system font, the size, and the accent colour the widgets share.
- It never makes itself the default app for Markdown files. To have them open in it, select one in Finder, choose **Get Info → Open with**, pick Markdown Editor and click **Change All**.

**DICOM Viewer**

- Drop DICOM files, folders or zip archives on the window or the Dock icon, choose **File → Open…** (**⌘O**), or right-click a `.dcm` or `.zip` file in Finder and choose **Open With → DICOM Viewer**. Folders are searched all the way down, and zip archives are read without unzipping them yourself (they're unpacked into a temporary folder, which is deleted as soon as the files are read), and files are recognised by their contents rather than their names, so the many DICOM files with no extension work too; anything that isn't DICOM is skipped, with a note saying how many. A drop on the window replaces what it shows; files opened another way go to the front window if it's empty, and otherwise get a window of their own.
- The files are grouped into series (by Series Instance UID and image size), listed by study in the sidebar with a picture of each. Slices are in Instance Number order, then by position. A multi-frame file's frames are slices too.
- Scroll, or use the arrow keys, to move through the slices, one per notch or every few points of a trackpad swipe; **Page Up** and **Page Down** jump ten, **Home** and **End** go to the ends, and the slider under the image goes anywhere. **⌘[** and **⌘]** go to the previous and next series. The corners show the slice number and position, and the window.
- Drag across the image for window and level: right widens the window, down raises the level, and **Shift** makes it finer. It starts with the file's own window (or an automatic one from the middle slice if the file has none). The **Image** menu, the toolbar's window menu and a right-click on the image have the file's windows, **Auto** (1st to 99th percentile), **Full Range**, and for CT **Brain**, **Subdural**, **Abdomen**, **Lung** and **Bone**; **⌘1**–**⌘9** pick them, **⌘R** resets and **⌘I** inverts.
- Pinch or use **⌘=** and **⌘−** to zoom, **⌥**-drag to move the image, and double-click or **⌘0** to fit it again. Rectangular pixels are drawn at their true shape. **Edit → Copy Image** (**⌥⌘C**) copies the slice as shown.
- The inspector (**View → Show Inspector**, or the toolbar) lists the current file's tags: tag, name, VR and value, with each sequence's items indented beneath it, private tags named by their creator, and UIDs named where they're known. The field at the top filters them; select rows and **⌘C** to copy them, or **Edit → Copy All Tags** (**⇧⌘C**) for the lot.
- It reads explicit and implicit VR little endian, explicit big endian and deflated files; uncompressed pixels of 1 to 32 bits, signed or not, in MONOCHROME1, MONOCHROME2, RGB, YBR_FULL and palette colour; and RLE and baseline JPEG compression, with JPEG 2000 tried through macOS's own decoder. Rescale slope and intercept (or a modality LUT) are applied. Files compressed another way, such as JPEG Lossless or JPEG-LS, still show their tags, with a note that the image can't be shown. The parser is a Swift port of the one in [`dicom/index.html`](../dicom/index.html). Files are read on the Mac; nothing is sent anywhere.
- It never makes itself the default app for DICOM files; to have `.dcm` files open in it, use Finder's **Get Info → Open with → Change All**.

## Uninstall

Quit the app from its right-click menu, delete it from `~/Applications`, and if you like, remove its saved settings:

```bash
defaults delete com.mbolding.commandbar
```

The settings domains are `com.mbolding.clockwidget`, `com.mbolding.wordclock`, `com.mbolding.commandbar`, `com.mbolding.somaplayer`, `com.mbolding.dialtimer`, `com.mbolding.monthcalendar`, `com.mbolding.scratchpad`, `com.mbolding.serverlist`, `com.mbolding.dockclock`, `com.mbolding.mapbrowser`, `com.mbolding.textextractor`, `com.mbolding.markdowneditor`, `com.mbolding.dicomviewer` and `com.mbolding.widgetbar`, plus `com.mbolding.desktopwidgets` for the accent colour they share. Map Browser also keeps its map tiles in `~/Library/Caches/com.mbolding.mapbrowser`.

## How it's put together

```
desktop_widget/
├── build.sh        the build script; lists every app in its CLOCKS table
├── Shared/         the floating window, right-click menu, FloatPin, the accent colour, and the icon renderer
├── Analog/         App.swift, Icon.swift, ClockFace.swift; Widget/ is a parked WidgetKit version
├── Word/           App.swift, Icon.swift, WordFace.swift
├── Command/        App.swift, Icon.swift, the view and shell session, InfoPlistExtras.xml
├── Soma/           App.swift, Icon.swift, the view and player
├── Timer/          App.swift, Icon.swift, the dial, its view, the timer, the stopwatch and the chime
├── Calendar/       App.swift, Icon.swift, CalendarFace.swift
├── Scratch/        App.swift, Icon.swift, the view and the pad
├── Servers/        App.swift (the menu bar item), Icon.swift, the saved server list, InfoPlistExtras.xml
├── Dock/           App.swift, Icon.swift, DockTile.swift, InfoPlistExtras.xml; ClockFace.swift links to Analog's
├── Maps/           App.swift (with the menus and Settings), Icon.swift, the window, map view and model, tiles, search and places, InfoPlistExtras.xml
├── Extractor/      App.swift (with the menus), Icon.swift, the window, the model and the text extraction, InfoPlistExtras.xml (with its document types)
├── Markdown/       App.swift (with the menus and Settings), Icon.swift, the document, the editor and its highlighter, InfoPlistExtras.xml (with the document types)
├── Dicom/          App.swift (with the menus), Icon.swift, the DICOM parser, pixel decoding, series and tag list, the window, image view and model, InfoPlistExtras.xml (with the document types)
└── Launcher/       App.swift, Icon.swift, the bar and the launcher that finds and drives the widgets
```

Each app is a folder: `App.swift` holds the `@main` entry (window size and any extra menu items), `Icon.swift` draws its app icon, and the rest is its face. App icons are drawn at build time from the app's own SwiftUI code, so no image files are checked in. Draw highlights with the `accent` environment value rather than a fixed colour, so they follow the shared Accent Color setting; it falls back to orange where no window sets it, as in the app icons. An app can add keys to its `Info.plist` with an `InfoPlistExtras.xml` file, as Command Bar does for its Finder action. Every app gets `LSUIElement` and the `DesktopWidget` key (which Widget Bar looks for) unless that file sets the key itself, as Dock Clock, Map Browser, Text Extractor, Markdown Editor and DICOM Viewer do to show their Dock icons and stay out of Widget Bar, and Server List does to stay out of it. Map Browser, Text Extractor, Markdown Editor, DICOM Viewer and Server List don't use `DesktopClock.run` at all: their `App.swift` is an ordinary SwiftUI `App`, with a `WindowGroup` for Map Browser (with `Settings`), Text Extractor and DICOM Viewer, a `DocumentGroup` and `Settings` for Markdown Editor, and a `MenuBarExtra` for Server List. A window can be round (`round: true`, as Dial Timer is); if its face has drags of its own, turn off dragging by the background (`movableByBackground: false`) and put `MovesWindow` on the parts that should move it.

To add one: make a folder with those files, then add a line to the `CLOCKS` table in `build.sh` (folder, executable name, bundle id, display name). `build.sh` marks every app it builds with a `DesktopWidget` key in its `Info.plist`, which is how Widget Bar finds them, so a new widget appears on the bar once it's installed and the bar restarts. Each widget writes its `floatOnTop` setting to its own preferences domain and watches it, which is how the bar reads and flips it from outside.

The WidgetKit version of the analog clock in `Analog/Widget/` is only built when an Apple Development signing certificate is present, because macOS ignores widgets that aren't signed by one.
