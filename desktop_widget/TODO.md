# To do

## Widget ideas

Common desktop widgets that would sit well beside the ones here. Each would be a new folder and a line in `build.sh`'s `CLOCKS` table. Draw highlights with the shared `accent`, and avoid Swift macros (`@Observable`, `@Entry`, `#Preview`), since the command-line tools can't build them.

- **Sun and Moon.** Sunrise, sunset and day length, plus the moon's phase, worked out locally like `clocks/nature/sun_moon_clock.html` does with SunCalc (here, a small Swift port).
- **System Stats.** CPU, memory, battery and network speed as small rings or sparklines, from `host_statistics`, IOKit and `getifaddrs`. No permissions needed.
- **Countdown.** Days, hours and minutes to a date you set, such as a deadline or a trip, with a short label.
