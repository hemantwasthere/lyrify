# Compact Layout's tiers become per-control Breakpoints, continuously resolved

ADR-0010 modeled Compact Layout's narrowing as four named `CompactTier` cases (`.full`/`.reduced`/`.minimal`/`.bare`), each bundling several controls' visibility together and switching all of them at once at one of three width/height constants. A side-by-side against Spotify's own Mini Player across its full resizable range showed Spotify doesn't jump between a handful of bundled presets — each control disappears at its own size, continuously, the way a CSS layout with per-element breakpoints would, not in steps. `CompactTier` is retired; `OverlayLayout` instead resolves an ordered table of per-control Breakpoints, each with a small hysteresis buffer between its hide and reappear thresholds (so holding a resize exactly on a boundary can't make a control flicker), continuously recomputed on every resize rather than switched between named buckets.

## Considered Options

- **Keep `CompactTier`, add more named tiers for finer granularity** — still a small number of hand-authored buckets, not truly continuous; every additional tier is another whole bundle of controls to design and test together, not an independent per-control answer.
- **AppKit's own `NSStackView` compression-resistance priorities** — less new code, but the exact width a given control disappears at becomes an indirect consequence of priorities and neighbors' intrinsic sizes, hard to tune precisely against Spotify's own measured drop-points, and (per this repo's own convention) untested AppKit-layer behavior rather than a tested Core seam.
- **An ordered table of per-control Breakpoints in `LyrifyCore`, each independently tested** (chosen) — keeps sizing logic in the same tested Core layer `OverlayLayoutTests` already covers, at the cost of needing every Breakpoint's exact value hand-tuned rather than derived automatically.

## Consequences

`OverlayLayout.CompactTier` and its three tier-boundary constants (`fullTierMinimumWidth`, `reducedTierMinimumWidth`, `minimalTierMinimumHeight`) are retired. `OverlayCardView.applyCompactTier()`'s all-at-once `isHidden` toggling — settings/mute/shuffle/repeat/share dropping together at `.reduced`, previous/lyrics dropping together at `.minimal`, the chrome bar and drag grip dropping together at `.bare` — is replaced with each control independently reading its own Breakpoint against the Overlay's current size.

Every Breakpoint's exact value needs empirical tuning against the real Spotify Mini Player rather than being derivable purely from static reference screenshots (no window-dimension metadata survives a screenshot) — expect an iterative pass comparing the built Overlay side-by-side with Spotify itself, the same way ADR-0010's own tier-boundary constants were "confirmed live."

The Lyrics Face's own floor (ADR-0010: hides the lyrics button below a height, dismissing back to Now Playing if it was open) becomes the lyrics button's own Breakpoint — the same mechanism as every other control, rather than a special case bolted on separately.
