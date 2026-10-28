# To do

## Widget ideas

Common desktop widgets that would sit well beside the ones here. Each would be a new folder and a line in `build.sh`'s `CLOCKS` table. Draw highlights with the shared `accent`, and avoid Swift macros (`@Observable`, `@Entry`, `#Preview`), since the command-line tools can't build them.

- **Up Next.** The next few events from Calendar via EventKit, with a countdown to the next one. Needs calendar permission (`NSCalendarsFullAccessUsageDescription`). Could also show on Month Calendar as dots under days with events.
- **Sun and Moon.** Sunrise, sunset and day length, plus the moon's phase, worked out locally like `clocks/nature/sun_moon_clock.html` does with SunCalc (here, a small Swift port).
- **Pomodoro.** Work and break rounds with a count of sessions done, a port of `clocks/utility/random_pomodoro_clock.html`. It could reuse Dial Timer's dial and chime.
- **Stopwatch.** Start, lap and reset, with laps listed below. A companion to Dial Timer, which only counts down.
- **System Stats.** CPU, memory, battery and network speed as small rings or sparklines, from `host_statistics`, IOKit and `getifaddrs`. No permissions needed.
- **Scratch Pad.** A text pad that keeps its contents as you type, with two buttons of its own: one copies everything to the clipboard, the other saves it as a new `.md` file on the Desktop (named by date and time, so nothing is overwritten). An interactive window, like Command Bar.
- **Countdown.** Days, hours and minutes to a date you set, such as a deadline or a trip, with a short label.
- **Clipboard History.** The last dozen things copied; click one to copy it again. Polls `NSPasteboard`'s change count, so no permissions are needed.

## Smaller changes

- **Month Calendar:** click to open Apple's Calendar, and step between months.
