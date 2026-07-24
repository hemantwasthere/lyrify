# Compact Layout becomes the true horizontal Mini Player; the width cap is lifted and the resize handle dropped

A side-by-side of the Overlay against Spotify's own Mini Player at its small, wide-and-short size exposed a structural mismatch, not a tuning one. Spotify's small Mini Player is a wide, short horizontal bar — a disc on the left, title/artist beside it, a lyrics button on the right, a slim seek line pinned to the bottom edge, and, on hover, a transport row that fades in over a dark scrim. Lyrify couldn't reach that shape at all:

- `OverlayController.maximumSize.width` was capped at **320**, narrower than Spotify's small Mini Player is wide, so the Overlay physically couldn't be dragged to the same proportions.
- Full Layout's artwork square was pinned edge-to-edge to the Overlay's width and grew with it, so its structural minimum grew with width too. That coupling is exactly why `thresholdHeight` had to sit high (420) and why widening the ceiling would have forced it higher still — the square fights the wide-short bar.
- Compact Layout had **no seek bar** ("seeking is exclusively a Full Layout capability"), so at the compared size the Overlay showed neither Spotify's bottom seek line nor its hover controls over a scrim.
- The transport icons carried no `SymbolConfiguration`, rendering at AppKit's heavy default weight/scale — visibly sharper than Spotify's lighter, evenly-sized glyphs.
- A decorative resize-handle glyph sat in the bottom-right corner; Spotify's Mini Player has none, relying on native edge/corner resize.

This ADR re-aims Compact Layout to *be* Spotify's horizontal Mini Player rather than an approximation of it: it gains a slim, always-visible seek bar and a dark scrim behind its hover-revealed controls, the width ceiling is raised so it can reach true Mini Player proportions, Full Layout's artwork square is capped to a fixed maximum width (decoupling its structural minimum from the Overlay's width, so the raised ceiling doesn't drag `thresholdHeight` up with it), the transport icons get a real `SymbolConfiguration`, and the resize-handle glyph is dropped for native-resize parity.

## Considered Options

- **Keep two discrete faces, only retune the thresholds** — cheapest, but leaves the width cap and the square-grows-with-width coupling in place, so the wide-short bar stays unreachable no matter how the numbers move. Rejected: this is the structural mismatch, not a boundary that needs nudging.
- **Make Full Layout (the big square) the thing that reshapes into the bar** — collapses to one continuous layout, but throws away the working Compact bar that already has disc-left/title/lyrics-button and per-control Breakpoints (ADR-0013), and forces the square-artwork treatment to also express a wide-short shape it was never meant to.
- **Reshape Compact into the real horizontal Mini Player and lift the width cap, capping Full Layout's square width** (chosen) — keeps both faces and everything ADR-0009/0013 already built, adds only what Compact was missing (seek bar, scrim), and breaks the width/threshold coupling by bounding the square instead of the window.

## Consequences

`OverlayController.maximumSize.width` rises from 320 to 600; `OverlayCardView.maximumRowWidth` tracks it. Full Layout's artwork square gains a maximum-width cap and centers within any wider Overlay rather than stretching edge-to-edge, so its structural minimum — and therefore `thresholdHeight` — no longer moves when the width ceiling does. Bumping the width ceiling again is now independent of the threshold, reversing the coupling this repo's own `thresholdHeight` comment previously warned about.

Compact Layout gains a slim, always-visible seek bar pinned to its bottom edge, wired to the same commit-on-release seek path Full Layout's slider already uses (`configureSeek`/`updateSeek` now drive both). The domain glossary's "Compact Layout never shows a seek bar" invariant is retired.

Both layouts gain a dark gradient **Scrim** behind their hover-revealed transport controls, faded in and out on the same hover as the controls themselves.

The decorative resize-handle glyph and its custom diagonal cursor are removed entirely; the Overlay is resized by dragging its native window edges/corners, exactly as ADR-0012's real titled window already affords. Nothing replaces it — one fewer element to reveal on hover.

The transport, chrome, mute, play/pause, and lyrics glyphs render through a shared `SymbolConfiguration` (a lighter weight and controlled scale) rather than AppKit's default.

Every value here — the 600 ceiling, the square's width cap, the seek bar's thickness, the scrim's gradient, the symbol weight — is a first-pass starting point to compare against Spotify live, in the same iterative spirit ADR-0013 set for the Breakpoint table, not a locked design decision.
