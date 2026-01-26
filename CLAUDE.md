# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a collection of creative, self-contained web clock implementations. Each clock is a single HTML file with embedded CSS and JavaScript - no build process, dependencies, or external libraries required. Clocks can be opened directly in a browser.

## Architecture

### Self-Contained Design
Each clock (`*.html`) is completely standalone:
- All styles in `<style>` tags
- All JavaScript in `<script>` tags
- No build process required
- External libraries loaded from CDN when needed (e.g., Three.js for 3D graphics)
- Responsive design using CSS clamp() for flexible sizing
- Dark mode support where appropriate (prefers-color-scheme media query)

### Clock Implementations

**ng26_clock.html** - NeuroGateways '26 Conference Clock
- Traditional analog clock with Tufte-inspired design
- Countdown timer to conference date (April 9-10, 2026)
- Web Audio API for minute tick sounds
- Trailing second hand with animated dots
- Auto dark mode support

**circadian_clock.html** - Natural Time Period Clock
- 20 defined circadian periods throughout the day (e.g., "Golden Hour", "First Light", "Tea Time")
- Dynamic background gradients that change based on time of day
- Animated celestial bodies (sun and moon) that arc across the sky
- SVG wheel visualization showing all periods
- Contextual suggestions for each time period

**binary_clock.html** - Binary LED Clock
- Displays time in binary format (6 columns: hour tens/ones, minute tens/ones, second tens/ones)
- LED-style visual with glow effects
- 4-bit representation (8-4-2-1 pattern)
- Pulsing separator dots

**flip_clock.html** - Animated Flip Card Clock
- Mechanical flip clock simulation
- CSS 3D transforms for flip animations
- Split-flap display effect with top/bottom card halves
- Smooth transitions between digit changes

**particle_clock.html** - Particle Physics Clock
- Canvas-based particle system displaying time
- Spring physics for smooth particle movement
- Digit patterns defined as 7x7 character grids
- Particles dynamically assigned to nearest target positions
- Color transitions based on particle velocity

**polar_clock.html** - Circular Progress Clock
- Concentric circles representing hours, minutes, and seconds
- Smooth arc animations showing time progress
- Percentage-based display for each unit
- Minimal, modern aesthetic

**word_clock.html** - Natural Language Clock
- Displays time in written English (e.g., "ten minutes past three")
- Smooth word transitions with fade effects
- Generates natural language strings from time values
- Conversational time format

**ng26_countdown.html** - Minimal Countdown Timer
- Focused countdown to specific event date
- Days, hours, minutes, seconds display
- Clean typography and spacing

**spectrum_clock.html** - Color Spectrum Clock
- Time represented as colors mapped to hue spectrum (0-360°)
- Three vertical bars showing hours, minutes, and seconds with color-coded fills
- Animated spectrum strip with position indicator showing day progress
- Dynamic background gradient that shifts throughout the day
- Displays HSL, RGB, and Hex color values of current time color
- Smooth color transitions using cubic-bezier easing

**hsv_clock.html** - HSV Color Model Clock
- Direct HSV mapping: Hours → Hue (0-360°), Seconds → Saturation (0-100%), Minutes → Value (0-100%)
- Large circular color display showing the current HSV color
- Three control panels with progress bars for H, S, and V components
- Progress bars use gradients showing the current component's range
- Displays color in HSV, RGB, and Hex formats
- Dynamic text color adjustment for readability based on background luminance
- Creates unique color every second (86,400 unique colors per day)

**sundial_clock.html** - 3D Sundial Clock
- Full 3D sundial built with Three.js
- Real-time sun positioning based on actual time of day
- Dynamic shadow casting from gnomon onto sundial face
- Hour markers (6 AM - 6 PM) with Roman numerals
- Interactive camera controls (drag to rotate, scroll to zoom)
- Physically accurate sun arc across the sky
- Responsive touch controls for mobile devices

## Development Workflow

### Viewing Clocks
Open `index.html` in a browser to see a landing page with links to all clocks, or open any individual clock file directly.

### Testing Changes
Simply open the HTML file in a browser:
```bash
# On Linux
xdg-open binary_clock.html

# On macOS
open binary_clock.html

# Or use Python's built-in server if needed
python3 -m http.server 8000
# Then navigate to http://localhost:8000/
```

### Common Patterns

**Time Updates**
All clocks use `setInterval()` or `requestAnimationFrame()` for real-time updates:
- Simple clocks: `setInterval(updateClock, 1000)` for 1-second updates
- Smooth animations: `requestAnimationFrame(animate)` for 60fps

**Responsive Sizing**
Consistent use of CSS `clamp()` for responsive typography and sizing:
```css
font-size: clamp(min, preferred, max);
/* Example: clamp(1rem, 5vw, 3rem) */
```

**Dark Mode**
Implemented via CSS custom properties and media queries:
```javascript
if (window.matchMedia('(prefers-color-scheme: dark)').matches) {
    document.documentElement.classList.add('dark');
}
```

**Date Formatting**
Most clocks include consistent date display logic:
```javascript
const days = ['Sunday', 'Monday', ...];
const months = ['January', 'February', ...];
```

### Adding New Clocks

When creating new clock implementations:
1. Keep everything self-contained in a single HTML file
2. Use CSS custom properties (variables) for theming
3. Implement responsive design with clamp() or media queries
4. Include both time display and current date
5. Consider adding to index.html or creating a separate launcher page if needed
6. Follow the naming pattern: descriptive_clock.html

### Animation Performance

For canvas-based clocks (particle_clock.html):
- Clear/redraw each frame with semi-transparent fill for trail effects
- Use `requestAnimationFrame` for smooth 60fps animation
- Implement object pooling for particles to avoid garbage collection

For CSS-based animations:
- Prefer CSS transforms over position changes
- Use `will-change` sparingly for performance hints
- Leverage GPU acceleration with `transform: translate3d()`

## File Structure

```
/
├── index.html              # Landing page listing all clocks
├── ng26_clock.html         # NeuroGateways conference clock
├── circadian_clock.html    # Natural time period clock
├── binary_clock.html       # Binary LED display
├── flip_clock.html         # Mechanical flip animation
├── particle_clock.html     # Canvas particle system
├── polar_clock.html        # Circular progress rings
├── word_clock.html         # Natural language time
├── spectrum_clock.html     # Color spectrum visualization
├── hsv_clock.html          # HSV color model clock
├── sundial_clock.html      # 3D sundial with Three.js
└── ng26_countdown.html     # Event countdown timer
```

## Design Philosophy

- **No build step**: Everything runs directly in the browser
- **No dependencies**: Pure HTML/CSS/JavaScript
- **Self-contained**: Each file is complete and independent
- **Responsive**: Works on mobile and desktop
- **Creative exploration**: Each clock offers a unique way to display time
