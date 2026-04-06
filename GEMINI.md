# GEMINI.md

This file provides guidance to the Gemini CLI when working with code in this repository.

## Project Overview

This is a collection of creative, self-contained web clock implementations. Each clock is a single HTML file with embedded CSS and JavaScript. This means there is no build process, no dependencies, and no external libraries are required (they are loaded from a CDN when needed). The clocks can be opened directly in a browser.

The project is designed to be a showcase of different ways to visualize time, with each clock having a unique aesthetic and technical implementation.

## Architecture

### Self-Contained Design
Each clock (`*.html`) is completely standalone:
- All styles are in `<style>` tags.
- All JavaScript is in `<script>` tags.
- There is no build process required.
- External libraries like Three.js are loaded from a CDN.
- The clocks are responsive, using CSS `clamp()` for flexible sizing.
- Dark mode is supported where appropriate, using the `prefers-color-scheme` media query.

### Clock Implementations

This project includes a variety of clocks, each with a different theme:

- **clocks/utility/ng26_clock.html**: A traditional analog clock with a countdown timer.
- **clocks/nature/circadian_clock.html**: A clock that shows 20 defined circadian periods throughout the day.
- **clocks/retro/binary_clock.html**: A clock that displays the time in binary format.
- **clocks/retro/flip_clock.html**: A clock that simulates a mechanical flip clock.
- **clocks/simulation/particle_clock.html**: A clock that uses a particle system to display the time.
- **clocks/art/polar_clock.html**: A clock that uses concentric circles to represent hours, minutes, and seconds.
- **clocks/art/word_clock.html**: A clock that displays the time in written English.
- **clocks/utility/ng26_countdown.html**: A countdown timer.
- **clocks/art/spectrum_clock.html**: A clock that represents the time as colors on a spectrum.
- **clocks/art/hsv_clock.html**: A clock that maps the time to the HSV color model.
- **clocks/nature/sundial_clock.html**: A 3D sundial that uses Three.js.

## Building and Running

There is no build process for this project.

### Viewing Clocks
You can open the `index.html` file to see a landing page with links to all the clocks, or you can open any individual clock's HTML file directly in your browser.

### Using a local server
If you need to run a local server, you can use Python's built-in HTTP server:

```bash
python3 -m http.server 8000
```
Then, you can navigate to `http://localhost:8000/` in your browser.

## Development Conventions

### Adding New Clocks

When creating a new clock, please follow these conventions:
1.  Keep everything self-contained in a single HTML file.
2.  Use CSS custom properties (variables) for theming.
3.  Implement a responsive design with `clamp()` or media queries.
4.  Include both the time and the current date.
5.  Add a link to the new clock in `index.html`.
6.  Follow the naming pattern: `descriptive_clock.html`.

### Time Updates
Clocks use `setInterval()` or `requestAnimationFrame()` for real-time updates. For simple clocks, `setInterval(updateClock, 1000)` is used for 1-second updates. For clocks with smooth animations, `requestAnimationFrame(animate)` is used for 60fps animations.
