# The notch is a Placement, not a premise

_Superseded by [ADR-0006](0006-the-overlay-becomes-a-draggable-resizable-widget.md) — Placement (the notch-straddle/pill choice this ADR describes) is retired; kept here for the reasoning that led to and away from it._

Lyrify draws into a single always-on-top, click-through Overlay whose Placement is resolved at runtime: the user chooses which display it lives on, defaulting to the main display, and the Overlay straddles the notch if that display has one or renders as a pill near the top edge if it does not.

The idea began as "lyrics in the notch," so the demotion needs explaining. Two facts forced it. First, a notch is only a couple of hundred points wide — two readable lines of lyrics do not fit *inside* it, so any real implementation straddles it regardless. Second, on the developer's own machine the main display is an external monitor with no notch at all, and the notched built-in panel sits off to the side. An app that assumed the notch would have rendered onto the screen nobody was looking at.

## Consequences

Treating the notch as one rendering mode among two makes Lyrify usable on every Mac rather than only on notched laptops. The honest cost is that the notch — the detail that made the idea appealing in the first place — may be the path this user rarely sees.

Notch geometry must always be read from the system at runtime and never hardcoded, since it differs across models.

The Overlay must never take keyboard focus and must pass clicks through by default; it is a peripheral-vision display, and anything that interrupts typing defeats the point of leaving it on all day.
