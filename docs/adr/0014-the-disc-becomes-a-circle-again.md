# The Disc becomes a circle again, reopening ADR-0009's shape choice

ADR-0009 gave Compact Layout's thumbnail a shallow rounded-square corner radius, matching Spotify's own (static) Mini Player thumbnail exactly. That match didn't account for one thing Spotify's own thumbnail never has to deal with: this one keeps spinning while a Track plays, a behavior `CONTEXT.md`'s own Disc definition already flags as older than, and independent of, ADR-0009's shape change. A rotating shape with corners — however gently rounded — visibly wobbles as those corners sweep around; a circle is rotationally symmetric, so spinning it looks identical at every angle. Verified by hand, at Compact Layout's own smaller sizes, the rounded-square Disc's spin reads as visibly broken rather than smooth. The Disc becomes a full circle again — Full Layout's own artwork square is a separate view entirely, never spins, and keeps the square shape ADR-0009 gave it unchanged.

## Considered Options

- **Keep ADR-0009's rounded square, stop spinning it** — would fix the wobble by removing its cause, but throws away a distinctive touch that predates the Mini Player redesign entirely and that nothing in this feedback asked to give up.
- **A full circle again, still spinning** (chosen) — gives up exact shape-parity with Spotify's own static thumbnail at Compact Layout's small size, in exchange for a spin that actually looks smooth rather than wobbling.

## Consequences

`OverlayCardView.discCornerRadius` changes from a fixed `8` to `discSize / 2` (a full circle at the Disc's own `40`pt size) — `discImageView`'s own corner radius, unrelated to `fullArtworkCornerRadius`/`fullArtworkView`, which are untouched. No other Compact Layout geometry changes: the Disc's own size, position, and rotation mechanism (`update(rotationDegrees:)`'s `CATransform3D`, applied to the same layer) are unaffected — only the shape that rotation acts on.
