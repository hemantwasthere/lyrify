# The Overlay becomes resizable again, styled after Spotify's Mini Player

ADR-0008's "one small widget, always the same fixed size" reasoning no longer holds now that a concrete, well-liked reference design exists to imitate: Spotify's own Mini Player, which is resizable and adapts its layout to whatever size the listener drags it to. That reference — not a change of heart about the fixed-size widget's own reasoning — is what justifies reopening a decision made one ticket ago. The Overlay regains `.resizable`, with sensible minimum and maximum bounds, and a new Core seam, `OverlayLayout`, decides which of two layouts a given size calls for: **Compact Layout** (a small square thumbnail with title and artist beside it — this ticket's scope) and **Full Layout** (a Spotify Mini Player–style artwork display, seek bar, and chrome — later tickets). The retired "Minimized"/"Expanded" terms are not reused, to avoid confusion with ADR-0008's different meaning for them.

## Considered Options

- **Keep ADR-0008's fixed size, adjust its visual treatment instead** — would not have given the listener a size they control, the actual complaint a concrete Mini Player reference surfaced; a fixed-size widget can look nicer without ever feeling like a real player.
- **Resizable again, with an adaptive Compact/Full layout** (chosen) — gives up the simplicity of a single unconditional layout, in exchange for a size the listener controls and a widget that can look as small or as substantial as they want.

## Consequences

`OverlaySizePreference`, retired in the ADR-0008 commit, is revived — the Overlay's size is remembered across launches again, alongside its position, exactly the way it was before ADR-0008 retired it.

`OverlayWindow` regains `.resizable` in its `styleMask`, plus `minSize`/`maxSize` bounds set by `OverlayController`. The maximum height is capped just below `OverlayLayout.thresholdHeight` for now — Full Layout isn't rendered yet, so resizing is bounded to stay within Compact Layout's own territory until a later ticket both raises that bound and teaches `OverlayCardView` to render what's on the other side of it.

`OverlayLayout` replaces and expands the retired `LyricsViewScale`: the old height-to-line-count-and-font-size formula reappears unchanged as Full Layout's own Lyrics Face scaling, just anchored at a new starting point sized for Full Layout's own chrome rather than the old fixed card's unrelated minimum.

`OverlayCardView` no longer pins its own fixed width/height — its frame now comes directly from the (now-resizable) window, the same relationship any ordinary resizable window has with its content view. Everything inside it that previously assumed a fixed 220×96 card (the seek bar's width, in particular) is relative to its actual current size instead of a baked-in constant.
