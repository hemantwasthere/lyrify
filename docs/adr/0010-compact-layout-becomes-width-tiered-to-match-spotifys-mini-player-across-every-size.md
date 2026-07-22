# Compact Layout becomes width-tiered, to match Spotify's Mini Player across every size

ADR-0009 imitated Spotify's Mini Player only at Full Layout's size — Compact Layout kept its own pre-existing design (a dark scrim fading in over the whole card, seek bar/transport/volume stacked vertically inside it), regardless of width. A full set of Spotify Mini Player reference screenshots, across its whole resizable range, showed Compact Layout's real counterpart is nothing like that: a horizontal thumbnail-and-text bar whose available chrome and transport controls narrow in steps as it gets narrower, with everything still hover-gated (nothing shown at rest) the same way Full Layout already works. Compact Layout is rebuilt to match, rather than introducing a third named layout for the wide-but-short states that still show Full Layout's complete control set — those stay Compact Layout, just its widest tier.

## Considered Options

- **A third named layout** for the wide-and-short, richly-controlled states — rejected: it would keep each layout's own internal logic simpler, but two names already cover the real distinction (`OverlayLayout.thresholdHeight`, unchanged), and a third name would only describe "Compact Layout at its widest," not a genuinely different resolving rule.
- **Compact Layout, internally width-tiered** (chosen) — keeps ADR-0009's two-layout split exactly as it is; Compact Layout's own rendering now reads both the Overlay's width and height instead of just showing one fixed control set.

## Consequences

Compact Layout's tiers, widest to narrowest, each dropping controls the previous tier showed: (1) full chrome bar (hide dot, drag grip, settings) + the lyrics button (occupying the spot Spotify gives X/add-to-library) + the full transport row (mute/volume, shuffle, previous, play/pause, next, repeat, share); (2) the settings icon drops and the drag grip relocates to a corner; mute, shuffle, repeat, and share drop, leaving the lyrics button + previous/play/next; (3) the lyrics button and previous drop too, leaving just play/next; (4) if height is also very short, the hide dot and drag grip drop, leaving a bare thumbnail + title + play/next. The Lyrics Face has its own floor independent of these tiers: below it, the lyrics button itself hides (dismissing back to Now Playing if it was open), rather than rendering a cramped lyrics view.

The mute/volume control, previously a separate always-visible slider row unique to the old Compact Layout, is redesigned to match Spotify's own: a single icon in the transport row (added to Full Layout too, which had no volume control at all before this) that mutes instantly on click (swapping its own glyph to reflect muted/unmuted) and reveals an inline slider beside itself on a hover of the icon specifically, nested within the card's own hover-reveal.

Compact Layout drops its seek bar entirely — seeking is now exclusively a Full Layout capability, matching Spotify exactly rather than offering a bare seek slider with no time labels.

`OverlayCardView.defaultSize` (also `OverlayController`'s `minimumSize`) shrinks from 220×96 to whatever Compact Layout's narrowest tier actually needs, so every tier described above is reachable rather than the bottom one or two being unreachable dead code.

The Settings Face stays a single toggle — Spotify's own second toggle, "Queue," has nothing to bind to, since Lyrify has no queue concept (per `CONTEXT.md`, it observes/controls the current Track only).

A decorative resize-handle glyph is added to the card's bottom-right corner, hover-revealed alongside everything else, swapping the cursor to a resize cursor on hover of that specific spot — native edge-drag resizing already works and is unchanged; this only adds the visual affordance Spotify itself shows.
