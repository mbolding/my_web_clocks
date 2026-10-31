# Desktop widgets for macOS

Small native Mac apps that float on the desktop: frosted, borderless windows that sit just above the desktop icons (or above every window, with Float on Top), show on every Space, and stay out of the Dock and menu bar. Twelve are different: Dock Clock and Dock Load live in their Dock icons, Server List lives in the menu bar, and Map Browser, Text Extractor, Markdown Editor, DICOM Viewer, Stipple, Polyhedra, Gopher Browser, News Reader and Relay Chat are ordinary apps with windows and a menu bar. They're written in SwiftUI and built with a single script, so you don't need Xcode itself.

| App | What it is |
| --- | --- |
| **Clock Widget** (`Analog/`) | An analog clock with the weekday and date; second hand optional |
| **Word Clock** (`Word/`) | The time spelled out on an 11×11 letter grid, a native port of [`clocks/art/word_clock.html`](../clocks/art/word_clock.html) |
| **Command Bar** (`Command/`) | A floating zsh you can type into and drop folders onto, with history, Tab completion and the current git branch |
| **Soma Player** (`Soma/`) | A small [SomaFM](https://somafm.com) radio with a channel menu and what's playing, and [tilderadio](https://tilderadio.org), the tildeverse's community station |
| **Dial Timer** (`Timer/`) | A round, up-to-an-hour timer: drag the face to set it, and a coloured wedge shows the time left. Also a stopwatch |
| **Month Calendar** (`Calendar/`) | This month's calendar, with today picked out |
| **Scratch Pad** (`Scratch/`) | A text pad that keeps what you type, with buttons to copy it all or save it to the Desktop |
| **Server List** (`Servers/`) | A menu bar item listing your Macs and servers: choose one to open Screen Sharing (`vnc://`) or an SSH session in Terminal (`ssh://`), like Finder's Go → Connect to Server |
| **Dock Clock** (`Dock/`) | An analog clock with no window: its live Dock icon is the whole app |
| **Dock Load** (`Load/`) | CPU load and memory pressure as rings in its Dock icon, with the busiest processes in its Dock menu; also no window |
| **Map Browser** (`Maps/`) | An [OpenStreetMap](https://www.openstreetmap.org) browser, and an ordinary Mac app with windows, a menu bar and a Dock icon: search for places, save them, and switch between map styles |
| **Text Extractor** (`Extractor/`) | Another ordinary app: drop a PDF or Word document on it and it shows just the text, to select, copy or save as plain text |
| **Markdown Editor** (`Markdown/`) | A plain text editor for Markdown files, with light syntax colouring and no preview; an ordinary document app with New, Open, Save and window tabs |
| **DICOM Viewer** (`Dicom/`) | A viewer for DICOM medical images: open or drop files, folders or zip archives to see each series, scroll through its slices, change the window and level, and read the tags |
| **Stipple** (`Stipple/`) | Drop a picture on it and it's redrawn in dots, gathered where the picture is dark, or as one continuous line through them, to save as SVG for a pen plotter or PNG; a native take on Evil Mad Scientist's [StippleGen](https://github.com/mbolding/stipplegen) |
| **Polyhedra** (`Polyhedra/`) | The five Platonic solids to turn over and look at, each with a slider that morphs it into its dual through the truncations between, and the numbers for whatever is showing |
| **Gopher Browser** (`Gopher/`) | A browser for gopherspace, the menus-and-text internet that SDF and others still run, for Gemini, its successor over TLS, for Spartan and for finger, with bookmarks, searches, telnet links opened in Terminal, and the Mac's handler for `gopher://`, `gemini://`, `spartan://` and `finger://` links |
| **News Reader** (`News/`) | A Usenet newsreader: subscribe to groups on any NNTP server, read them threaded with what you've read remembered, and follow up or post, with logins kept in the Keychain |
| **Relay Chat** (`Relay/`) | An IRC client for SDF's network, tilde.chat and Libera.Chat, or any other: channels and private conversations, nick completion, SASL logins kept in the Keychain, and it stays connected with its window closed, counting mentions on its Dock icon |
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
| `desktop_widget/build.sh --update` | Rebuilds only the apps already in `~/Applications`, and reopens only the ones that were running |

### Update

Right-click Widget Bar's background and choose **Update from GitHub…**, or from a terminal:

```bash
cd ~/repos/my_web_clocks && git pull && desktop_widget/build.sh --update
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
- tilderadio, the tildeverse's own station, is at the top of the menu above SomaFM's channels. Its song, cover art and listener count come from the station's AzuraCast server, and when a DJ is broadcasting live their name shows beside LIVE. Its DJs talk in `#tilderadio` on tilde.chat, which Relay Chat can join.
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
- Right-click the bar's background for **Update from GitHub…**. After you confirm, it pulls the latest code into the checkout the apps were built from (fast-forward only, so local commits stop it) and runs `build.sh --update`. Running apps quit and reopen, Widget Bar included, so save your work in Markdown Editor first, and Command Bar starts a new shell. A notification says when it's done; if it fails, the log (`~/Library/Logs/Widget Bar Update.log`) opens in TextEdit. If there's nothing new, nothing is rebuilt.
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

**Dock Load**

- Keep it in the Dock and open it, as with Dock Clock. Its icon becomes a gauge, redrawn every two seconds: the outer ring and the number in the middle are how busy the processors are, all cores together, in the accent colour. The inner ring is memory pressure, how much of memory macOS counts as spoken for, and turns from green to yellow to red as macOS grades the pressure normal, warning or critical.
- Right-click the icon for the numbers behind it: CPU split into user and system time, memory pressure, and memory used (app memory, wired and compressed, as Activity Monitor adds it up). Below them are the five busiest processes, as `ps` reports them, so a share of one core that can pass 100%. Choosing one, or **Open Activity Monitor**, opens Activity Monitor; so does clicking the icon. **Accent Color** is the shared colour.
- It reads the kernel's counters directly and needs no permissions. It uses well under 1% of one core itself. Like Dock Clock it has no window, isn't on Widget Bar, and shows its plain icon when it isn't running.

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

**Stipple**

- Drop a picture on the window or the Dock icon, choose **File → Open…** (**⌘O**), or right-click it in Finder and choose **Open With → Stipple**. Anything macOS can open works: JPEG, PNG, HEIC, TIFF, GIF and so on. A picture dropped on the window replaces what it shows; pictures opened another way go to the front window if it's empty, and otherwise each get a window of their own.
- Dots are scattered by the picture's darkness, then settle a step at a time as you watch: each moves to the darkness-weighted middle of the area nearest it (weighted Voronoi stippling, after Adrian Secord, with Lloyd's method), until they barely move. The subtitle counts the steps. **Keep Settling** (**⌘K**) pauses it, or carries on for another run of steps; **Start Over** (**⌘R**) scatters a fresh set.
- **Dots** and **Line** (**⌘1**, **⌘2**, or the toolbar) switch between separate dots and one continuous line through them all ("TSP art"): a route along a Hilbert curve, untangled with 2-opt moves until no two stretches cross. It's worked out when the dots stop, and drawn while it improves.
- The settings, at the side (the toolbar's right-hand button shows and hides them), are the number of dots, the **White cut-off** above which the picture counts as blank, **Light on black** to stipple the light parts in white on black, the smallest and largest dot (dots grow with the darkness they cover) or the line's width, and how many steps a run takes. Changing the number, the cut-off or Light on black starts over. **Show the picture underneath** (**⌘U**) puts the original faintly behind the dots, to compare. They're kept for next time.
- **Save as SVG…** (**⌘S**) writes circles or one polyline, in drawing units 1,200 on the picture's long side; black on white has no background, ready for a pen plotter. **Save as PNG…** (**⇧⌘S**) renders it 2,400, 4,800 or 9,600 pixels on the long side, picked under **Export**. **Edit → Copy Drawing** (**⌥⌘C**) puts a PNG on the clipboard.
- It's written fresh in Swift rather than ported, since StippleGen is LGPL. Pictures are read on the Mac and nothing is sent anywhere.

**Polyhedra**

- Pick a solid from the toolbar, the **Solid** menu or **⌘1**–**⌘5**: tetrahedron, cube, octahedron, dodecahedron or icosahedron. Drag to turn it, pinch to zoom, and double-click (or **⌘0**) to set it straight. **Spin** (**⌘J**) turns it slowly by itself.
- The slider under **Towards its dual** slices its corners off until only its dual is left. It stops at five named shapes, with a dot for each to jump to: the solid, its truncation, the rectified solid (cut to the edge midpoints), the truncated dual, and the dual; the cube goes through the truncated cube, the cuboctahedron and the truncated octahedron to the octahedron. **⌘]** and **⌘[** step between them, and **Morph Back and Forth** (**⌘K**) runs it there and back by itself. The solid's own faces are in the accent colour and the dual's are pale, so you can watch one set give way to the other.
- **View** has **Faces**, **Edges**, **Corners** and **The Hidden Side** (**⌥⌘1**–**⌥⌘4**), which shows the edges and corners round the back, dashed, through the faces. **Centre and Spokes** (**⌥⌘5**) marks the centre with a line out to every corner, and turns the faces see-through to show them.
- **Angles** (**⌥⌘6**) labels each different angle once, where it's easiest to see: inside one face of each kind, with an arc at every corner; between two faces, at the middle of a heavier edge (the dihedral angle); and with the spokes showing, at the centre between the spokes to the ends of an edge.
- The inspector's numbers are measured from the shape on screen rather than looked up: the corners, edges and faces (with Euler's V − E + F = 2), the faces by kind, the faces round each corner (3.8.8 for the truncated cube), the Schläfli symbol for the Platonic solids, the angles inside the faces, between them and at the centre, and at the named stops the circumradius, midradius, inradius, surface area and volume for edges of length 1. Below them are the solid's symmetry group, its dual and the element Plato gave it.
- Each shape is worked out as the intersection of the solid's face planes with its dual's, moved closer as the slider goes, and drawn flat-shaded in a SwiftUI `Canvas`; there's no SceneKit and nothing to download.

**Gopher Browser**

- It opens at SDF's gopher server, the home page until you choose another with **Go → Set This Page as Home**. Type an address in the toolbar (**⌘L**) as `gopher://host/` or just the host's name, with a port after a colon and the item type and selector after the slash, as in `gopher://sdf.org/1/maps/`, or as `gemini://host/path`. A web address typed there opens in your web browser.
- Menus are set in a monospaced font, as their ASCII art expects, with each link's type as a symbol beside it in the accent colour: a folder for a menu, a page for a text file, a magnifying glass for a search, a picture, a globe for a web link and an arrow for a file to save. The status bar says where the link under the pointer goes. Text files open as text you can select and search with **⌘F**, pictures show in the window, web links open in your web browser, and other files ask where to save them. Telnet links open in Terminal (below).
- Gemini pages are set in the system font, wrapped to a comfortable width, with their headings, lists and quotes, links one to a line (an arrow for Gemini, a folder for gopher, a globe for the web), and preformatted blocks kept monospaced. A Gemini page that's an image shows it, other text shows as text, and anything else offers to save it. Redirects are followed, up to five.
- A search, or any question a Gemini page asks, shows a field for the words and sends them; Veronica-2 among the bookmarks searches all of gopherspace, Kennedy searches Gemini, and TLGS searches Gemini and Spartan. The starting bookmarks also have Cosmos for new gemlog posts, and the Bubble BBS and Station, which can be read but need a client certificate to post.
- Spartan pages (`spartan://host/path`, port 300) are gemtext like Gemini's, over plain TCP with no certificates, and their links have a shield. A Spartan page's `=:` links, drawn with a pencil, ask for words first and send them to the server as the request's data, which is how Spartan does searches, guestbooks and uploads of text. Redirects stay on the same server, as Spartan requires. A reply the server calls `application/octet-stream` that is plain text is shown as text.
- Finger (`finger://host/user` or `finger://user@host`, port 79) shows what a server says about a user, from their `.plan` and `.project` files on a Unix host like SDF, or who's on if the user is left out. Gemini links to finger and Spartan open here too.
- A telnet link, from a gopher menu or a Gemini page, or a `telnet://` address typed in the toolbar, opens a new Terminal window on that server, saying which name to log in as when the gopher menu gives one. It uses `telnet` if Homebrew has installed it (`brew install telnet`), and otherwise the app's own small client, which answers the server's option negotiation the way nc can't, so SDF and BBSes get to their login prompts; **Control-]** closes it.
- Gemini servers mostly sign their own certificates, so the first one a server shows is remembered, the way SSH remembers hosts. If it later shows a different one that the Mac doesn't itself trust, the page stops and says so, with **Trust the New Certificate** to accept it. Pages that ask for a client certificate aren't supported.
- **⌘[** and **⌘]** go back and forward, **⌘R** reloads, **⌘.** stops, and **⇧⌘H** goes home. **⌘D** bookmarks the page, the **Bookmarks** menu lists them, and **Edit Bookmarks…** (**⌥⌘B**) renames, reorders and deletes them. **Go** lists the pages you've visited lately. Right-click a link to open it in a new window, copy it or bookmark it.
- **⌘+** and **⌘−** make the text bigger and smaller, and **⌘0** puts it back. **Save Page As…** (**⌘S**) saves the page as the server sent it, and **⌥⌘C** copies its address.
- It's the Mac's handler for `gopher://`, `gemini://`, `spartan://` and `finger://` links, so one clicked in any other app opens in a window of its own. Each request is one connection to the server with nothing else sent: plain TCP to port 70 for gopher, 300 for Spartan and 79 for finger, none of which are encrypted, and TLS to port 1965 for Gemini.

**News Reader**

- It starts with three servers: tilde.club's, for the tildeverse's own groups (over TLS), Gmane's, which carries thousands of mailing lists as newsgroups, and Eternal September, which carries the whole of Usenet, free, but needs an account even to read. Register at eternal-september.org, then put the user name and password in **Settings → Servers**, where you can also add, change and remove servers. Passwords go in your Keychain.
- The sidebar lists each server's subscribed groups with how many articles in each are unread; it starts subscribed to a few of tilde.club's busier groups. **Subscribe to Groups…** under a server (**⇧⌘G**) lists every group it carries, to search and tick.
- A group shows its latest 500 articles as threads, the thread with the newest reply first and each reply under the one it answers. Unread articles have a dot in the accent colour; opening one marks it read. **⌘]** goes to the next unread article, **⇧⌘U** marks the open one unread again, **⇧⌘K** marks the whole group read, and **⇧⌘N** gets new articles.
- Articles are set in a monospaced font, as Usenet's quoting and ASCII art expect, with quoted lines shaded by depth, the signature dimmed and web, gopher and other addresses made links. Encoded names and subjects, quoted-printable and base64 bodies, other charsets, the plain text part of multipart articles, and format=flowed paragraphs are all undone. **⇧⌘H** shows every header.
- **Follow Up** (**⌘R**) starts a reply to the open article's groups (or the ones its Followup-To names), "Re:" its subject, with it quoted under who wrote it; **New Post** (**⌥⌘N**) starts a new thread. Posts go out under the name and address in **Settings → Posting**, which every reader can see, so many people use a disguised address; a signature there goes under each post. Long lines are wrapped as format=flowed, so other readers can rewrap them.
- **⌘+** and **⌘−** make the text bigger and smaller, and **⌘0** puts it back. Each server gets one connection, kept open between commands and opened again if the server drops it for idling.

**Relay Chat**

- Choose a nick in **Settings → Identity** first; it's what people will call you. Then pick a network in the sidebar and **Connect**. It starts with three, each with a channel to join: SDF's (`#sdf`), the tildeverse's tilde.chat (`#meta`), and Libera.Chat (`#libera`), all over TLS on port 6697. **Settings → Networks** adds, changes and removes them, with a nick of a network's own, the channels to join, and the account and password for a registered nick, sent by SASL. Passwords go in your Keychain.
- The sidebar lists each network with a dot for whether it's connected, then its channels and private conversations, with how many messages are unread, and mentions and private messages in the accent colour. A network's own buffer holds what its server says, such as its message of the day.
- Type in the line at the bottom and press Return. **Tab** finishes a nick, again for the next match, and **↑** and **↓** go through what you've sent. Commands start with `/`: `/join #channel`, `/part`, `/me does something`, `/msg nick text`, `/query nick`, `/nick name`, `/topic`, `/whois nick`, `/ns` for NickServ, `/away`, `/close`, `/quit`, and `/help` for the rest; others go to the server as they are.
- Some channels only let people logged in to a registered nick talk, and the log says so with a pointer to **Network → Log In or Register…**. That sheet logs in to a nick you've registered, or registers the one you're using with the network's NickServ (with a **Suggest** button for a strong password), asks for the code NickServ emails if it sends one, and saves the account and password so SASL logs you in from then on. SDF has no NickServ, so its nicks can't be registered. If your nick was taken when you connected, as by a connection of yours that hasn't timed out, you're on with an underscore added until you log in; then NickServ is asked for it back, and it's taken as soon as whoever has it leaves.
- A password typed in a NickServ command (`/msg NickServ`, or `/ns` for short) is shown as dots in the log and kept as dots in the input history.
- **Join Channel…** (**⌘J**) takes a channel's name, or lists every channel on the network, busiest first, to search. SDF and tilde.chat only list their channels a minute after you connect.
- Channels show their topic above the log and who's in them at the side (**⌥⌘U**), operators first; double-click someone to talk privately. The log keeps IRC's bold, italics and colours, gives each nick a colour of its own, makes links clickable, highlights lines that say your nick, and follows new lines only while it's scrolled to the bottom. **View → Show Joins and Departures** hides the comings and goings.
- Closing the window leaves you in your channels: the app stays in the Dock, counts mentions and private messages on its icon, and sends a notification for them. Clicking the Dock icon brings the window back. Quitting says goodbye to each network, and the networks that were connected come back at the next launch. A dropped connection is tried again after a pause.

## Uninstall

Quit the app from its right-click menu, delete it from `~/Applications`, and if you like, remove its saved settings:

```bash
defaults delete com.mbolding.commandbar
```

The settings domains are `com.mbolding.clockwidget`, `com.mbolding.wordclock`, `com.mbolding.commandbar`, `com.mbolding.somaplayer`, `com.mbolding.dialtimer`, `com.mbolding.monthcalendar`, `com.mbolding.scratchpad`, `com.mbolding.serverlist`, `com.mbolding.dockclock`, `com.mbolding.dockload`, `com.mbolding.mapbrowser`, `com.mbolding.textextractor`, `com.mbolding.markdowneditor`, `com.mbolding.dicomviewer`, `com.mbolding.stipple`, `com.mbolding.polyhedra`, `com.mbolding.gopherbrowser`, `com.mbolding.newsreader`, `com.mbolding.relaychat` and `com.mbolding.widgetbar`, plus `com.mbolding.desktopwidgets` for the accent colour they share. Map Browser also keeps its map tiles in `~/Library/Caches/com.mbolding.mapbrowser`, and News Reader and Relay Chat keep passwords in the Keychain, under their names.

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
├── Load/           App.swift (with the Dock menu), Icon.swift, LoadTile.swift, the sampler, InfoPlistExtras.xml
├── Maps/           App.swift (with the menus and Settings), Icon.swift, the window, map view and model, tiles, search and places, InfoPlistExtras.xml
├── Extractor/      App.swift (with the menus), Icon.swift, the window, the model and the text extraction, InfoPlistExtras.xml (with its document types)
├── Markdown/       App.swift (with the menus and Settings), Icon.swift, the document, the editor and its highlighter, InfoPlistExtras.xml (with the document types)
├── Dicom/          App.swift (with the menus), Icon.swift, the DICOM parser, pixel decoding, series and tag list, the window, image view and model, InfoPlistExtras.xml (with the document types)
├── Stipple/        App.swift (with the menus), Icon.swift, the stippler, the line, the drawing and saving, the window and model, InfoPlistExtras.xml (with the document types)
├── Polyhedra/      App.swift (with the menus), Icon.swift, the solids, the plane-intersection geometry, the stage, the window and model, InfoPlistExtras.xml
├── Gopher/         App.swift (with the menus, and the `--telnet` entry), Icon.swift, the shared connection, gopher and its menus, Gemini and gemtext with its certificate check, Spartan, finger, the telnet hand-off to Terminal and the telnet client it runs, the window and model, InfoPlistExtras.xml (with the URL schemes)
├── News/           App.swift (with the menus), Icon.swift, the NNTP connection, articles and their MIME and threading, servers, subscriptions and read marks, the window and model, Settings, InfoPlistExtras.xml
├── Relay/          App.swift (with the menus, and staying open with no window), Icon.swift, the IRC connection and messages, each network's session, formatting codes, the shared state with the Dock badge and notifications, the window, Settings, InfoPlistExtras.xml
└── Launcher/       App.swift, Icon.swift, the bar, the launcher that finds and drives the widgets, and the updater
```

Each app is a folder: `App.swift` holds the `@main` entry (window size and any extra menu items), `Icon.swift` draws its app icon, and the rest is its face. App icons are drawn at build time from the app's own SwiftUI code, so no image files are checked in. Draw highlights with the `accent` environment value rather than a fixed colour, so they follow the shared Accent Color setting; it falls back to orange where no window sets it, as in the app icons. An app can add keys to its `Info.plist` with an `InfoPlistExtras.xml` file, as Command Bar does for its Finder action. Every app gets `LSUIElement` and the `DesktopWidget` key (which Widget Bar looks for) unless that file sets the key itself, as Dock Clock, Dock Load, Map Browser, Text Extractor, Markdown Editor, DICOM Viewer, Stipple, Polyhedra, Gopher Browser, News Reader and Relay Chat do to show their Dock icons and stay out of Widget Bar, and Server List does to stay out of it. Map Browser, Text Extractor, Markdown Editor, DICOM Viewer, Stipple, Polyhedra, Gopher Browser, News Reader, Relay Chat and Server List don't use `DesktopClock.run` at all: their `App.swift` is an ordinary SwiftUI `App`, with a `WindowGroup` for Map Browser (with `Settings`), Text Extractor, DICOM Viewer, Stipple, Polyhedra and Gopher Browser, a `WindowGroup` and `Settings` for News Reader, a single `Window` and `Settings` for Relay Chat, a `DocumentGroup` and `Settings` for Markdown Editor, and a `MenuBarExtra` for Server List. A window can be round (`round: true`, as Dial Timer is); if its face has drags of its own, turn off dragging by the background (`movableByBackground: false`) and put `MovesWindow` on the parts that should move it.

To add one: make a folder with those files, then add a line to the `CLOCKS` table in `build.sh` (folder, executable name, bundle id, display name). `build.sh` marks every app it builds with a `DesktopWidget` key in its `Info.plist`, which is how Widget Bar finds them, so a new widget appears on the bar once it's installed and the bar restarts. Each widget writes its `floatOnTop` setting to its own preferences domain and watches it, which is how the bar reads and flips it from outside.

The WidgetKit version of the analog clock in `Analog/Widget/` is only built when an Apple Development signing certificate is present, because macOS ignores widgets that aren't signed by one.
