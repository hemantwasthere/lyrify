# The Overlay becomes a draggable, resizable widget, not a click-through peripheral

ADR-0004's peripheral-vision design — click-through, never focus, notch-or-pill — traded interactivity for staying out of the way. Real use surfaced two problems with it: the notch-straddling form visually collided with the system menu bar's own status items, since both draw into the same reserved strip beside the notch; and, independently of that bug, it just wasn't a good-looking way to show lyrics. The Overlay is now a single non-activating panel — still never taking keyboard focus, so it can't steal focus from whatever the listener is doing elsewhere — but it accepts mouse input directly: click-and-drag anywhere on its body moves it immediately, with no separate activation step first. It has two states: Minimized, a small spinning Disc of album art, and Expanded, a resizable card toggling between its Now Playing view (controls, revealed on hover) and its Lyrics view. Placement — the pill-vs-notch choice, the chosen-display submenu — is retired entirely; a draggable window makes "which display, and where on it" a physical act, not a menu choice.

## Considered Options

- **Keep ADR-0004's click-through peripheral, just fix the menu bar collision** — would have kept the notch form out of the real menu bar's strip, but the "doesn't look good" complaint stands independent of the bug, and a click-through window can never be dragged, resized, or hold controls.
- **A draggable, resizable, non-activating widget with two states** (chosen) — gives up click-through, in exchange for controls, album art, and a size the listener controls.

## Consequences

Most of the Placement-era code — `OverlayWindow`, `OverlayView`, `OverlayWingView`, `OverlayPresenter`, `Placement`, `DisplaySelection`, `DisplayPreference`, `DisplayMenuController`, `AttachedDisplays`, and the visibility toggle — is retired along with the design it implemented. The Core seams that decide *what* to show — `LineSelection`, `PlaybackClock`, `LyricsProvider`, `MenuBarTitle`, `OverlayDisplay` — are unaffected; only how the answer gets drawn changes.

Showing more than the Active Line and Next Line as the Expanded card grows means `LineSelection`'s pair-of-lines answer will need to widen into a scrollable window of several lines — a Core change, not just a rendering one.

The Overlay's position (and now its size) must still be remembered across launches, the same way the retired Display choice was — persistence isn't new, only what's persisted changes.
