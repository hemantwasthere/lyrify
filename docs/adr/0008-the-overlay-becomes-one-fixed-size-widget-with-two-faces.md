# The Overlay becomes one fixed-size widget with two faces, not a resizable Minimized/Expanded pair

ADR-0006's Minimized Disc / Expanded Card split, and the Expanded card's user-resizing, turned out to work against the Overlay's own point: real use reported the resting Disc as too easy to lose track of and the Expanded card as too large and plain-looking for something meant to sit unobtrusively on screen while a Track plays. The two states and the resize handle are retired in favor of one small widget, always the same fixed size, with two faces toggled by the same lyrics button as before: a Now Playing Face (a small spinning Disc of album art alongside the current Track's title and artist — the "info of the song" the old Now Playing view never actually showed) and a Lyrics Face (the Active Line and its surrounding context, now a fixed number of lines rather than one that grows with a resizable card's height). Switching faces crossfades rather than resizing the window, since both are the same size. Clicking the widget's background no longer does anything but drag — there is no more Disc-to-expand or card-to-collapse gesture, since there is nothing left to expand into.

## Considered Options

- **Keep ADR-0006's two states, just shrink the Expanded card's default size** — would not have addressed the Disc's separate "too easy to lose track of, and shows no song info at all" complaint, and leaves two states and a resize handle to maintain for a design that no longer wants either.
- **One fixed-size widget with two crossfaded faces** (chosen) — collapses "small and easy to spot" and "shows song info" into a single always-current face, at the cost of the resize-driven line count ADR-0006 introduced.

## Consequences

`DiscView` and `NowPlayingView` are retired; a single `OverlayCardView` replaces both. `OverlayExpansionPreference` and `OverlaySizePreference` are retired along with the expanded/collapsed state and user-chosen size they persisted — the Overlay's position is still remembered across launches, the same way it always has been, but its size no longer varies.

`LyricsWindow` (the Core seam ADR-0006 introduced to widen beyond the Active/Next pair) is unaffected — it's still asked for a window of lines — but it's now always asked for the same fixed count, rather than one derived from the Expanded card's current height. `LyricsViewScale`, the height-to-line-count-and-font-size mapping ADR-0006 also introduced, no longer has anything to map from and is retired with it.

The Disc's rotation moves from `NSView.frameCenterRotation` to a CALayer transform, fixing a real bug where the two fought Auto Layout's own relayout on every pass — unrelated to the state/sizing change itself, but discovered and fixed as part of the same rework since the Disc's rendering moved into `OverlayCardView` regardless.
