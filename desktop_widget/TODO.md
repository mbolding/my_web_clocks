# To do

## Widget ideas

Common desktop widgets that would sit well beside the ones here. Each would be a new folder and a line in `build.sh`'s `CLOCKS` table. Draw highlights with the shared `accent`, and avoid Swift macros (`@Observable`, `@Entry`, `#Preview`), since the command-line tools can't build them.

- **System Stats.** CPU, memory, battery and network speed as small rings or sparklines, from `host_statistics`, IOKit and `getifaddrs`. No permissions needed.

## Little app ideas

Small apps that are a bit more than widgets: ordinary windowed apps with a menu bar and Dock icon, built like Map Browser (an ordinary SwiftUI `App`, with `LSUIElement` and `DesktopWidget` set to false in its `InfoPlistExtras.xml`), and each a line in `build.sh`'s `CLOCKS` table. The same rule on Swift macros applies.

- **DICOM Viewer.** A simple native viewer for DICOM files you open or drop on it: the image with window and level, scrolling through a series, and the tags. macOS has no DICOM decoder, so port the parser from `dicom/index.html`, starting with uncompressed and baseline JPEG (which ImageIO can decode).
- **Markdown Editor.** A plain text editor for `.md` files with light syntax highlighting (headings, emphasis, code, links and list markers), with no preview, opening and saving ordinary files through the standard Open and Save panels.
- **Text Extractor.** Drop a Word document or PDF on it and it shows just the text, ready to select, copy or save as plain text. PDFKit's `PDFDocument.string` reads PDFs, and `NSAttributedString` reads `.docx`, `.doc` and `.rtf`, so it needs no other libraries.

## Future ideas

- **Replicants, after BeOS.** Drag part of a widget (Soma Player's now-playing line, the stopwatch readout) out onto the desktop to make it a small live window of its own, perhaps by a hand-like grip shown on hover; drop one on Widget Bar to dock it there, like the Deskbar's tray. Each piece would be another `DesktopPanel` in the same app, opened when a drag ends outside the window and restored at launch. Unlike Be's, a piece closes when its app quits, since macOS apps can't host each other's views.
- **Dock-only apps.** Apps with no window at all, whose Dock icon is the whole app: draw into `NSApp.dockTile.contentView` and call `display()` when it changes (once a second at most). Dock Clock (`Dock/`) is the first. Next perhaps a CPU or memory graph like Activity Monitor's Dock icon, the moon's phase, or a countdown. Each shows its Dock icon rather than being `LSUIElement` (set in its `InfoPlistExtras.xml`) and only draws while running; a Dock tile plug-in (`NSDockTilePlugIn`, as Calendar uses for its date) to keep drawing when closed can wait.
