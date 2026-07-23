import AppKit
import LyrifyCore
import QuartzCore

/// The Overlay's one and only window content — the Now Playing face, shown
/// as Compact Layout (a thumbnail beside the current Track's title and
/// artist, at its most generous size styled just like Full Layout: a
/// hover-revealed top chrome bar and transport row of its own) or
/// Full Layout (a big square artwork area, an always-visible seek bar, and
/// title/artist pinned at the bottom) as `OverlayLayout` resolves for the
/// Overlay's current size — or the Lyrics face (`LyricsCardView`), toggled
/// by whichever layout's own lyrics button and crossfaded between. As the
/// Overlay's window is now user-resizable (`OverlayWindow`), this view is
/// sized directly by that window rather than pinning its own fixed size the
/// way it used to; `defaultSize` remains only as the starting size before
/// any resize is remembered. Compact Layout's own chrome bar and transport
/// row (mute, shuffle, previous, play/pause, next, repeat, share) fade in
/// together on hover and back out the moment the mouse leaves — the
/// thumbnail/title/artist row and the lyrics button beside it stay visible
/// regardless, the same way Full Layout's own title/artist and lyrics
/// button do. Full Layout reveals the identical shape of transport row and
/// chrome bar, overlaid on the artwork instead of stacked beneath the
/// thumbnail, on that same hover. The settings icon (in either layout's own
/// chrome bar) opens a third face — a single toggle for Full Layout's
/// artwork background's color-extraction wash, and a Done button back to
/// whichever face was showing before. Compact Layout never shows a seek
/// bar — seeking is exclusively a Full Layout capability. Clicking any
/// non-interactive area (inherited from `DraggableBackgroundView`) only
/// ever starts a drag — there is no more expand/collapse gesture, since
/// there's nothing left to expand into.
///
/// Seek and volume only commit on mouse-up, not on every intermediate
/// value — dragging either shouldn't fire a live AppleScript command for
/// every pixel crossed. Both ignore external updates while the listener is
/// actively dragging them, so a redraw never fights the gesture in progress.
/// Full Layout's own seek slider is the only one Compact Layout has no
/// counterpart for; every other shared control (transport, mute/volume)
/// has one instance per layout, sharing this same commit-on-release state
/// since only one instance is ever on screen at a time.
///
/// Deliberately untested — AppKit event handling and layout verified by
/// hand.
final class OverlayCardView: DraggableBackgroundView {
    /// The Overlay's size before any resize has ever been remembered —
    /// also `OverlayWindow`'s minimum resizable size, since it's the
    /// smallest proven-usable Compact Layout: below every one of
    /// `OverlayLayout.breakpoints`' own thresholds, so the narrowest,
    /// barest reflow (every optional control hidden) is an actually
    /// reachable state rather than dead code. Reaching it required its own
    /// single-row reflow (`compactTransportRowInlineConstraints`): the
    /// stacked arrangement wider/taller sizes use genuinely can't fit the
    /// fixed `discSize`-tall thumbnail above a second row within heights
    /// this small, confirmed by tracing the real geometry, not just by the
    /// absence of a logged Auto Layout conflict (which pure visual
    /// overlap between two independently-satisfiable constraint groups
    /// never produces).
    static let defaultSize = NSSize(width: 140, height: 48)

    /// A genuine, constant ceiling on how wide Compact Layout's title/
    /// artist row is ever allowed to demand — matches
    /// `OverlayController.maximumSize.width`, the Overlay's own resize
    /// ceiling, since a title any wider than that could never actually be
    /// shown in full regardless. Without an *independent* cap like this
    /// one, a long real Track title has nothing standing between it and
    /// the window itself: this view's own width comes from the window
    /// (deliberately, so the window can drive it rather than the reverse
    /// — see the class doc comment), so a cap relative to *this view's
    /// own* width is circular and resolves by growing the window to fit
    /// the untruncated title instead of truncating it. A cap against a
    /// plain constant breaks that circularity outright.
    private static let maximumRowWidth: CGFloat = 320 - 28

    /// Compact Layout's thumbnail is a small square, not the circular Disc
    /// the pre-resizable widget used — matching Spotify's own Mini Player,
    /// which ADR-0009 names as the concrete reference for this redesign.
    static let discSize: CGFloat = 40
    private static let discCornerRadius: CGFloat = 8

    /// Not tied to the view's actual (now-variable) height — a fixed,
    /// reasonable radius for Compact Layout at any size. Full Layout's own
    /// visual treatment is a later ticket's concern.
    private static let cornerRadius: CGFloat = 24

    /// A gentler rounding than the card's own — a big square tile reads as
    /// a tile, not a pill, at this size.
    private static let fullArtworkCornerRadius: CGFloat = 12

    /// How much smaller the sharp artwork copy is than the square
    /// background behind it — Spotify Mini Player's own proportions,
    /// leaving the blurred/plain backdrop clearly visible around it.
    private static let fullArtworkForegroundScale: CGFloat = 0.62

    private static let crossfadeDuration: TimeInterval = 0.2

    /// The top chrome bar's own height — just tall enough to hold the
    /// close button, drag-handle indicator, and settings icon comfortably.
    private static let chromeBarHeight: CGFloat = 20

    /// The decorative resize-handle glyph's size, and the size of its own
    /// nested hover/cursor zone — small enough to read as a corner detail,
    /// not a real button.
    private static let resizeHandleSize: CGFloat = 14

    /// Shared by the decorative glyph and the cursor built from it, so the
    /// two can never drift apart visually.
    private static let resizeHandleSymbolName = "arrow.up.left.and.arrow.down.right"

    /// How far the resize-handle glyph sits from the card's own
    /// bottom-right corner — as small as still reads as a corner detail
    /// rather than being clipped by the card's own rounded corner. Not
    /// just cosmetic: `PassthroughImageView` falls through a click to
    /// `DraggableBackgroundView`'s own *move*-drag (the same as the
    /// drag-handle indicator), so a click here only reaches native
    /// edge-*resize* instead if it lands within `OverlayWindow`'s own
    /// resize hit-region at the true frame edge — a margin native to
    /// `.resizable` windows, narrower than this glyph's own size, and
    /// outside this view hierarchy entirely to inspect or rely on
    /// precisely. Sitting this close is the best fit achievable without
    /// writing new resize-detection logic of its own, which the ticket
    /// this shipped in deliberately ruled out.
    private static let resizeHandleInset: CGFloat = 2

    /// A custom diagonal resize cursor — AppKit has no public one (only
    /// `.resizeLeftRight`/`.resizeUpDown`, neither diagonal), so this
    /// builds one from the same SF Symbol the decorative glyph itself
    /// uses, for visual consistency between the two.
    private static let resizeCursor: NSCursor = {
        let image = NSImage(systemSymbolName: resizeHandleSymbolName, accessibilityDescription: nil) ?? NSImage()
        return NSCursor(image: image, hotSpot: NSPoint(x: image.size.width / 2, y: image.size.height / 2))
    }()

    /// The inline volume slider's width once revealed beside the mute
    /// button — short enough to read as an inline reveal within the
    /// transport row, not a second full-width slider.
    private static let fullVolumeSliderWidth: CGFloat = 70

    /// `fullControlsOverlay`'s transport row spacing — shared with the
    /// mute hover zone's own width calculation, since that zone must
    /// reach exactly as far as the revealed slider's own right edge
    /// actually sits, not just the slider's bare width.
    private static let fullTransportRowSpacing: CGFloat = 20

    var onTogglePlayPause: (() -> Void)?
    var onSkipToNext: (() -> Void)?
    var onSkipToPrevious: (() -> Void)?
    var onSeek: ((TimeInterval) -> Void)?
    var onVolumeChange: ((Int) -> Void)?
    var onToggleLyrics: (() -> Void)?
    var onToggleShuffle: (() -> Void)?
    var onToggleRepeat: (() -> Void)?
    var onShare: (() -> Void)?
    var onToggleBlurredBackground: ((Bool) -> Void)?

    private let compactFace = NSView()
    private let discImageView = PassthroughImageView()
    private let titleLabel = PassthroughLabel(labelWithString: "")
    private let artistLabel = PassthroughLabel(labelWithString: "")

    private let fullFace = NSView()

    /// The big square behind `fullArtworkView`'s now-smaller sharp copy —
    /// either the blurred/color-boosted treatment, or (disabled, or before
    /// it's ready) the same plain image `fullArtworkView` shows.
    private let fullArtworkBackgroundView = PassthroughImageView()
    private let fullArtworkView = PassthroughImageView()
    private let fullTitleLabel = PassthroughLabel(labelWithString: "")
    private let fullArtistLabel = PassthroughLabel(labelWithString: "")
    private let fullLyricsButton = NSButton()
    private let fullSeekSlider = NSSlider()
    private let elapsedLabel = PassthroughLabel(labelWithString: "0:00")
    private let remainingLabel = PassthroughLabel(labelWithString: "0:00")

    /// Full Layout's hover-revealed transport row (mute, shuffle, previous,
    /// play/pause, next, repeat, share), overlaid on the artwork.
    private let fullControlsOverlay = NSView()
    private let fullPlayPauseButton = NSButton()

    /// The mute/volume control, leftmost in `fullControlsOverlay`'s
    /// transport row: `fullMuteButton` toggles mute instantly on click;
    /// `fullVolumeSlider` is a second, nested hover-reveal — hidden until
    /// the pointer is specifically over `fullMuteButton` or the slider
    /// itself (`muteHoverTrackingArea`), distinct from the transport row's
    /// own card-wide hover reveal. The mute/volume *behavior* — toggling,
    /// committing a drag, deriving the icon — lives in `applyVolume(_:)`,
    /// `volumeSliderChanged`, and `muteTapped`, shared with Compact
    /// Layout's own `compactMuteButton`/`volumeSlider` the same way
    /// `fullSeekSlider` and every other Full/Compact control pair already
    /// shares its own commit-on-release state. The *hover geometry*
    /// (`muteHoverTrackingArea`) is a single shared property, not one per
    /// layout — `updateTrackingAreas()` recomputes it each pass against
    /// whichever of `fullMuteButton`/`compactMuteButton` is actually
    /// current, since only one is ever reachable at a time.
    private let fullMuteButton = NSButton()
    private let fullVolumeSlider = NSSlider()

    /// Whether the mute button last silenced Spotify's volume — driven
    /// only by an explicit mute/unmute (button tap or dragging a slider to
    /// or away from zero), not derived from the slider's current value on
    /// every read, so the icon can't disagree with what the listener last
    /// actually chose.
    private var isMuted = false

    /// The volume last known before muting — restored when unmuting.
    /// Seeded at a plausible full volume; overwritten almost immediately
    /// by `OverlayController`'s own startup fetch of Spotify's real
    /// current volume via `updateVolume(_:)`, the same way other
    /// placeholder values here (the artwork placeholder image, "Nothing
    /// Playing") are seeded before the real value is known.
    private var lastNonZeroVolume = 100

    /// A second, nested tracking area scoped to whichever of
    /// `fullMuteButton`/`compactMuteButton` is current, and its
    /// hover-revealed slider, together — narrower than `trackingArea`'s
    /// own card-wide rect, and independent of it: AppKit fires enter/exit
    /// for each tracking area on a view separately as the cursor crosses
    /// its own rect, regardless of any other tracking area's rect
    /// containing it.
    private var muteHoverTrackingArea: NSTrackingArea?

    /// The decorative resize-handle glyph, bottom-right corner of the
    /// card — shared by both layouts (unlike the chrome bar/transport
    /// row, it has no layout-specific content, so one instance and one
    /// hover-reveal alongside whichever layout's own chrome is currently
    /// fading in/out suffices). A `PassthroughImageView`, so a click on it
    /// falls through to `DraggableBackgroundView`/the window's own native
    /// edge-resize, the same way the drag-handle indicators already do
    /// for dragging.
    private let resizeHandleImageView = PassthroughImageView()

    /// A third, nested tracking area scoped to `resizeHandleImageView`'s
    /// own frame — swaps the cursor on enter/exit, independent of the
    /// general hover reveal and `muteHoverTrackingArea`, the same way
    /// that one is independent of the card-wide `trackingArea`.
    private var resizeHandleTrackingArea: NSTrackingArea?

    /// Full Layout's hover-revealed top chrome bar: the real system close
    /// button (ADR-0012), drag-handle indicator, and settings icon.
    private let fullTopChromeBar = NSView()
    private let settingsButton = NSButton()

    /// Compact Layout's own top chrome bar and transport row — the same
    /// close/drag/settings elements as `fullTopChromeBar`, and the same
    /// mute/shuffle/previous/play/next/repeat/share elements as
    /// `fullControlsOverlay`'s row, in second instances since only one
    /// layout's own chrome is ever visible at once. Stacked above and
    /// below the thumbnail/title/artist row respectively, rather than
    /// overlaid on top of it the way Full Layout's own chrome overlays its
    /// artwork — Compact Layout has no artwork square to float over.
    private let compactChromeBar = NSView()
    private let compactSettingsButton = NSButton()
    private let compactTransportRow = NSView()
    private let compactMuteButton = NSButton()

    /// The window's one real system close button (ADR-0012) — there's
    /// only one for the whole window, unlike every other chrome-bar
    /// element, which has a separate instance per layout. `init()` runs
    /// before there's a window to ask for one, so it starts `nil` and is
    /// installed later by `installCloseButton(_:)`, then reparented
    /// between `fullTopChromeBar` and `compactChromeBar` by
    /// `reparentCloseButton()` as the layout changes.
    private var closeButton: NSButton?
    private var closeButtonFullConstraints: [NSLayoutConstraint] = []
    private var closeButtonCompactConstraints: [NSLayoutConstraint] = []

    /// Compact Layout's own drag-handle indicator — centered in
    /// `compactChromeBar`, matching Full Layout's own, while the settings
    /// button is visible; relocated to sit directly beside the close
    /// button instead once the settings button on the other side of the
    /// bar is hidden. Passed into `configureChromeBar` (which otherwise
    /// builds and discards its own throwaway one for Full Layout's bar) so
    /// it can be referenced again afterward, the same pattern
    /// `configureTransportRow`'s own `muteButton`/`playPause` params
    /// already use.
    private let compactDragHandle = PassthroughImageView()

    /// The two position states `applyCompactControls()` swaps
    /// `compactDragHandle` between: `compactDragHandleFullTierConstraints`
    /// built once in `configureCompactChromeBar`,
    /// `compactDragHandleReducedTierConstraints` built later in
    /// `installCloseButton(_:)` since it anchors to the real close button,
    /// which doesn't exist yet at `configureCompactChromeBar`'s own call
    /// time. Unlike `fullLayoutContentConstraints`'s own plain on/off
    /// toggle, this is a swap between two mutually exclusive sets: exactly
    /// one is ever active.
    private var compactDragHandleFullTierConstraints: [NSLayoutConstraint] = []
    private var compactDragHandleReducedTierConstraints: [NSLayoutConstraint] = []

    /// Compact Layout's own shuffle/repeat/share buttons — three of the
    /// transport-row elements `applyCompactControls()` hides once each of
    /// their own `OverlayLayout.Breakpoint`s is crossed (alongside
    /// `compactMuteButton`), unlike play/next, which have no Breakpoint of
    /// their own and stay visible at every size. Passed into
    /// `configureTransportRow` the same way `compactMuteButton` already
    /// is, rather than built and discarded as throwaway locals the way
    /// Full Layout's own (which never need hiding) still are.
    private let compactShuffleButton = NSButton()
    private let compactRepeatButton = NSButton()
    private let compactShareButton = NSButton()

    /// Compact Layout's own previous button — like the lyrics button,
    /// hidden once its own `OverlayLayout.Breakpoint` is crossed. Passed
    /// into `configureTransportRow` for the same reason shuffle/repeat/
    /// share are.
    private let compactPreviousButton = NSButton()

    /// The thumbnail-and-title/artist row — a stored property (not a
    /// `configureCompactFace`-local variable) so `configureCompactTransportRow`
    /// (built afterward) can position `compactTransportRow` relative to
    /// it once the Overlay is too short for the stacked arrangement, where
    /// the two sit side by side in one row instead of `compactTransportRow`
    /// stacked beneath it.
    private let compactThumbnailTextRow = NSStackView()

    /// Two position states `applyCompactControls()` swaps
    /// `compactTransportRow` between — built once in
    /// `configureCompactTransportRow`, the same activate/deactivate
    /// pattern `compactDragHandleFullTierConstraints`/
    /// `...ReducedTierConstraints` already use.
    /// `compactTransportRowStackedConstraints` (centered beneath
    /// `compactThumbnailTextRow`, spanning the full width) is used at
    /// ordinary heights — `compactTransportRowInlineConstraints` (beside
    /// it instead, both in one row) once the Overlay gets very short:
    /// stacking two rows vertically needs more height than those tiny
    /// sizes actually have to give (confirmed by tracing the real
    /// geometry — the fixed `discSize`-tall thumbnail alone needs more
    /// headroom than those heights leave once a second row is stacked
    /// beneath it), while sitting side by side
    /// needs only as much height as the taller of the two, which the
    /// thumbnail's own fixed size already comfortably provides.
    private var compactTransportRowStackedConstraints: [NSLayoutConstraint] = []
    private var compactTransportRowInlineConstraints: [NSLayoutConstraint] = []

    /// The set of `OverlayLayout.CompactControl`s last resolved visible
    /// for the Overlay's current size — every control until the first
    /// real `update(layout:)` call, matching `isFullLayout`'s own
    /// placeholder-before-first-resolution default. Read by
    /// `applyCompactControls()`, which itself only ever runs while
    /// `!isFullLayout` — so a stale value left over from before a
    /// transition into Full Layout is never actually acted on, even
    /// though `update(layout:)` does still read (not act on) it every
    /// call, Full Layout resizes included, to detect the next real
    /// change in which controls are visible.
    private var visibleCompactControls: Set<OverlayLayout.CompactControl> = OverlayLayout.CompactControl.allVisible

    private let lyricsFace = LyricsCardView()
    private let volumeSlider = NSSlider()
    private let playPauseButton = NSButton()
    private let lyricsButton = NSButton()

    /// The settings panel — a third face, reached via the settings icon and
    /// returned from via its own Done button.
    private let settingsFace = NSView()
    private let blurredBackgroundSwitch = NSSwitch()
    private let settingsDoneButton = NSButton()

    /// Whether the Lyrics Face (rather than Now Playing content) was on
    /// screen when the settings icon was tapped — so Done can crossfade
    /// back to it specifically. Deliberately not a captured `NSView`
    /// reference to "whichever Now Playing face was showing": a resize can
    /// cross the Compact/Full boundary while Settings is open, and
    /// `activeNowPlayingFace` (re-read fresh at Done time) always reflects
    /// the *current* layout, where a stale capture from open-time would
    /// not.
    private var wasShowingLyricsBeforeSettings = false

    private var isDraggingSeek = false
    private var isDraggingVolume = false
    private var trackingArea: NSTrackingArea?

    /// Whether the current `OverlayLayout` is Full rather than Compact —
    /// tracked independently of either face's `isHidden`, since both go
    /// hidden together while the Lyrics face is showing and `isHidden`
    /// alone couldn't say which one to reveal when it isn't anymore.
    private var isFullLayout = false

    /// Whether `update(layout:)` has run at least once — its very first
    /// call must always apply (matching the constructor's own Compact
    /// defaults isn't guaranteed if the initial resolved layout is
    /// actually Full), every call after that only on an actual
    /// Compact/Full transition.
    private var didResolveInitialLayout = false

    /// The current Track's duration, needed alongside the live seek
    /// position to compute Full Layout's remaining-time label.
    private var trackDuration: TimeInterval = 1

    /// Full Layout's own internal content constraints — built once in
    /// `configureFullLayoutFace`, but only active while Full Layout is
    /// actually current. See that method's own comment for why: left
    /// active all the time, they'd pressure the window to grow to Full
    /// Layout's minimum size even while `fullFace` is hidden.
    private var fullLayoutContentConstraints: [NSLayoutConstraint] = []

    init() {
        super.init(frame: NSRect(origin: .zero, size: Self.defaultSize))

        wantsLayer = true
        // Nothing here is ever drawn via `draw(_:)` — background color,
        // border, and corner radius are plain CALayer properties Core
        // Animation composites on its own regardless of resize — so there's
        // no bitmap content that would ever need redrawing as this view's
        // size changes during a live resize drag.
        layerContentsRedrawPolicy = .never
        layer?.cornerRadius = Self.cornerRadius
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.85).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor

        // No fixed width/height constraint of its own: as the Overlay's
        // window content view, its frame is set directly by the (now
        // resizable) window, not derived from its subviews' own demands.
        // `suppressIntrinsicSizeGrowthPressure` and `maximumRowWidth`
        // exist because that's not quite the whole story — see their own
        // comments.
        translatesAutoresizingMaskIntoConstraints = false

        lyricsFace.isHidden = true
        lyricsFace.translatesAutoresizingMaskIntoConstraints = false
        addSubview(lyricsFace)

        NSLayoutConstraint.activate([
            lyricsFace.leadingAnchor.constraint(equalTo: leadingAnchor),
            lyricsFace.trailingAnchor.constraint(equalTo: trailingAnchor),
            lyricsFace.topAnchor.constraint(equalTo: topAnchor),
            lyricsFace.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        // Added after `lyricsFace`, so each renders above both — every
        // layout's own lyrics button must stay reachable regardless of
        // which Now Playing/Lyrics face is currently showing. Hidden by
        // default; `update(layout:)` shows exactly one of the two, toggled
        // opposite to the other.
        addSubview(fullLyricsButton)
        fullLyricsButton.isHidden = true
        addSubview(lyricsButton)
        lyricsButton.isHidden = true

        // `configureCompactFace()` positions `lyricsButton` relative to
        // its own thumbnail/title/artist row, so it must run after
        // `lyricsButton` is already a subview of `self` above — activating
        // a constraint between two views needs a common ancestor already
        // in place. Same reasoning for `configureFullLayoutFace()` and
        // `fullLyricsButton`, already satisfied above it too.
        configureCompactFace()
        configureCompactChromeBar()
        configureCompactTransportRow()
        configureFullLayoutFace()
        // `fullFace` isn't added to the hierarchy here at all — see
        // `configureFullLayoutFace`'s own comment on why; `update(layout:)`
        // (always called at least once, right after this view is built)
        // adds it only once Full Layout is actually current.

        configureSettingsFace()
        configureResizeHandle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        // `.activeAlways`, not `.activeInKeyWindow`: this panel never
        // becomes key, so hover must work regardless.
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area

        if let resizeHandleTrackingArea {
            removeTrackingArea(resizeHandleTrackingArea)
        }
        // `resizeHandleImageView` is a permanent sibling of `self` — never
        // detached the way `fullFace`'s own content is, just possibly not
        // laid out yet on the very first pass.
        if !resizeHandleImageView.bounds.isEmpty {
            let resizeHandleFrame = convert(resizeHandleImageView.bounds, from: resizeHandleImageView)
            let resizeArea = NSTrackingArea(
                rect: resizeHandleFrame,
                options: [.mouseEnteredAndExited, .activeAlways],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(resizeArea)
            resizeHandleTrackingArea = resizeArea
        }

        if let muteHoverTrackingArea {
            removeTrackingArea(muteHoverTrackingArea)
        }
        // Whichever mute button belongs to the current layout: outside
        // Full Layout, `fullFace` (and `fullMuteButton` beneath it) has
        // been removed from the hierarchy entirely, not just hidden (see
        // `fullLayoutContentConstraints`'s own comment on why) — `.window`
        // is what actually detects that detached case, since a detached
        // view's `bounds` survives the removal unchanged. `compactMuteButton`
        // is never detached this way, but can still be `.isHidden` via its
        // own ancestor (Compact Layout not current, or the Lyrics/Settings
        // Face covering it) — `isHiddenOrHasHiddenAncestor` catches that
        // case instead. `convert(_:from:)` against a detached or
        // effectively-invisible view would otherwise be meaningless.
        let activeMuteButton = isFullLayout ? fullMuteButton : compactMuteButton
        guard
            activeMuteButton.window != nil,
            !activeMuteButton.isHiddenOrHasHiddenAncestor,
            !activeMuteButton.bounds.isEmpty
        else { return }
        let muteButtonFrame = convert(activeMuteButton.bounds, from: activeMuteButton)
        // Reaches exactly as far as the revealed slider's own right edge —
        // the slider's width plus the row spacing between it and the mute
        // button, not just the slider's bare width, or hovering its last
        // stretch would fall outside this zone and collapse it back.
        let hoverZone = CGRect(
            x: muteButtonFrame.minX,
            y: muteButtonFrame.minY,
            width: muteButtonFrame.width + Self.fullTransportRowSpacing + Self.fullVolumeSliderWidth,
            height: muteButtonFrame.height
        )
        let muteArea = NSTrackingArea(
            rect: hoverZone,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(muteArea)
        muteHoverTrackingArea = muteArea
    }

    /// Compact and Full Layout each reveal their own chrome bar and
    /// transport row together, on the same hover — identical shapes, two
    /// instances — alongside the shared resize-handle glyph. The mute
    /// hover zone and the resize-handle zone are each nested independently
    /// of that reveal and of each other: entering/exiting the mute zone
    /// only ever reveals or hides whichever of `fullVolumeSlider`/
    /// `volumeSlider` belongs to the current layout; entering/exiting the
    /// resize-handle zone only ever swaps the cursor.
    override func mouseEntered(with event: NSEvent) {
        if event.trackingArea === resizeHandleTrackingArea {
            // `.set()`, not `.push()`/`.pop()`: this panel can be hidden
            // (the hide button, or a resize crossing a layout boundary)
            // without `mouseExited` necessarily firing first, and a stack
            // imbalance from a missed `.pop()` would compound across
            // repeated hovers. `.set()` only ever affects the current
            // cursor directly, so a missed exit self-corrects on the next
            // successful one instead of accumulating.
            Self.resizeCursor.set()
            return
        }
        if event.trackingArea === muteHoverTrackingArea {
            revealVolumeSlider(true)
            return
        }
        resizeHandleImageView.animator().alphaValue = 1
        if isFullLayout {
            fullControlsOverlay.animator().alphaValue = 1
            fullTopChromeBar.animator().alphaValue = 1
        } else {
            compactChromeBar.animator().alphaValue = 1
            compactTransportRow.animator().alphaValue = 1
        }
    }

    override func mouseExited(with event: NSEvent) {
        if event.trackingArea === resizeHandleTrackingArea {
            NSCursor.arrow.set()
            return
        }
        if event.trackingArea === muteHoverTrackingArea {
            // Ignored mid-drag — a fast drag gesture can momentarily carry
            // the cursor outside the hover zone's own rect, and hiding the
            // slider out from under an active drag would be jarring.
            guard !isDraggingVolume else { return }
            revealVolumeSlider(false)
            return
        }
        resizeHandleImageView.animator().alphaValue = 0
        if isFullLayout {
            fullControlsOverlay.animator().alphaValue = 0
            fullTopChromeBar.animator().alphaValue = 0
        } else {
            compactChromeBar.animator().alphaValue = 0
            compactTransportRow.animator().alphaValue = 0
        }
    }

    /// Fades whichever of `fullVolumeSlider`/`volumeSlider` belongs to the
    /// current layout in or out — a plain `isHidden` toggle would jump
    /// instantly, and hiding it collapses its own space (and the spacing
    /// around it) in the transport row's stack view automatically, the
    /// same way any hidden arranged subview does.
    private func revealVolumeSlider(_ reveal: Bool) {
        let slider = isFullLayout ? fullVolumeSlider : volumeSlider
        if reveal {
            slider.isHidden = false
            slider.alphaValue = 0
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.crossfadeDuration
            slider.animator().alphaValue = reveal ? 1 : 0
        } completionHandler: {
            // See `crossfade(from:to:)`'s own comment on why this
            // completion handler needs `MainActor.assumeIsolated`.
            guard !reveal else { return }
            MainActor.assumeIsolated {
                slider.isHidden = true
            }
        }
    }

    /// Switches between Compact and Full Layout's Now Playing content as
    /// `OverlayLayout` resolves differently for the Overlay's current size,
    /// and applies whichever Lyrics Face scale that layout calls for —
    /// Full Layout's own resolved `LyricsScale`, or Compact Layout's fixed
    /// default. Scale is applied unconditionally, on every call, not just
    /// on a Compact/Full transition: a live resize drag keeps `.full`
    /// resolving new scales as height changes without ever crossing back
    /// to `.compact`, and those must all reach `lyricsFace` too.
    func update(layout: OverlayLayout) {
        let wasFullLayout = isFullLayout
        let wasVisibleControls = visibleCompactControls
        switch layout {
        case .compact(let controls):
            isFullLayout = false
            visibleCompactControls = controls
            lyricsFace.updateScale(lineCount: LyricsCardView.defaultLineCount, fontSize: LyricsCardView.defaultFontSize)
        case .full(let scale):
            isFullLayout = true
            lyricsFace.updateScale(lineCount: scale.lineCount, fontSize: scale.fontSize)
        }

        // `sizeChanged()` calls this on every tick of a live resize drag,
        // not just when it crosses the Compact/Full boundary (or, now, a
        // change in which Compact-Layout controls are visible) — skip the
        // work below unless one of those was actually crossed (or this is
        // the first call), so a redundant activate/deactivate cycle on
        // every tick can't itself perturb layout.
        let layoutBoundaryCrossed = isFullLayout != wasFullLayout
        let compactControlsChanged = !isFullLayout && visibleCompactControls != wasVisibleControls
        guard layoutBoundaryCrossed || compactControlsChanged || !didResolveInitialLayout else { return }
        didResolveInitialLayout = true

        // `fullFace` is added to (and removed from) the hierarchy here,
        // not just hidden — see `fullLayoutContentConstraints`'s own doc
        // comment for why merely hiding it isn't enough. A view outside
        // the hierarchy entirely can't influence anything's sizing,
        // regardless of its own content's intrinsic size.
        if isFullLayout {
            addSubview(fullFace)
            NSLayoutConstraint.activate(fullLayoutContentConstraints)
        } else {
            NSLayoutConstraint.deactivate(fullLayoutContentConstraints)
            fullFace.removeFromSuperview()
        }

        // Reset both layouts' hover-revealed chrome immediately (not
        // animated) rather than leaving a stale reveal from before a resize
        // crossed the threshold mid-hover.
        resizeHandleImageView.alphaValue = 0
        compactChromeBar.alphaValue = 0
        compactTransportRow.alphaValue = 0
        fullControlsOverlay.alphaValue = 0
        fullTopChromeBar.alphaValue = 0

        // Reachable regardless of which face is currently showing — set
        // here, not inside the guard below, so neither goes dark the
        // moment the Lyrics face is showing.
        fullLyricsButton.isHidden = !isFullLayout
        lyricsButton.isHidden = isFullLayout

        // Moves the real close button into whichever bar matches
        // `isFullLayout` before `applyCompactControls()` runs, so its own
        // Breakpoint check below lands on the button now actually parented
        // in `compactChromeBar`.
        reparentCloseButton()

        // Run before the Lyrics/Settings-Face guard below, not after: that
        // guard's own early-return, whenever the Lyrics Face is still the
        // (pre-dismissal) active face, would otherwise skip this entirely
        // — exactly the moment a change in visible controls needs to react
        // to. Returns whether it just triggered a dismissal back to Now
        // Playing, so the guard below can treat that the same as the
        // Lyrics Face already being closed, rather than fighting the
        // crossfade it just started (`showNowPlaying()` synchronously
        // un-hides `compactFace`/`fullFace` as part of its own setup — the
        // guard's `else` branch re-hiding both immediately after, based on
        // `lyricsFace.isHidden`'s still-stale pre-animation value, would
        // undo that in the same tick).
        let dismissedLyricsFace = applyCompactControls()

        guard (lyricsFace.isHidden || dismissedLyricsFace), settingsFace.isHidden else {
            // The Lyrics or Settings face is showing — nothing to reveal
            // until it's dismissed; `isFullLayout` alone remembers which
            // Now Playing content that'll be. Settings needs the same
            // treatment as Lyrics here: `addSubview(fullFace)` above always
            // brings `fullFace` to the front of the z-order, which would
            // otherwise bury whichever of these two is currently on top —
            // forcing both hidden regardless of z-order sidesteps that
            // entirely, since a hidden view never draws no matter how it
            // stacks. `resizeHandleImageView` needs the same treatment —
            // unlike `lyricsButton`/`fullLyricsButton`, it has no reason to
            // stay reachable over the Lyrics/Settings Face, and being a
            // sibling of `self` (not nested in `compactFace`/`fullFace`)
            // means it isn't hidden by either of those cascading already.
            compactFace.isHidden = true
            fullFace.isHidden = true
            resizeHandleImageView.isHidden = true
            return
        }

        // Reachable again now that neither face above is showing.
        resizeHandleImageView.isHidden = false

        compactFace.isHidden = isFullLayout
        fullFace.isHidden = !isFullLayout
    }

    /// Applies `visibleCompactControls` to Compact Layout's own chrome and
    /// transport row, relative to `.full`'s own full-featured rendering
    /// (ADR-0013): each control's own `isHidden` reads its own membership
    /// in `visibleCompactControls` directly — there's no longer a bundled
    /// tier deciding several of these together. The drag handle relocates
    /// to sit beside the hide/close button whenever the settings button
    /// isn't currently visible (freeing the far side of the bar it used to
    /// share), independent of the drag handle's own visibility. If the
    /// Lyrics Face happened to be open when a resize hid the lyrics
    /// button, returns to the Now Playing Face, since there's no longer a
    /// lyrics button to have reached it from. A no-op for Full Layout,
    /// which never narrows.
    ///
    /// `hideButton` and `dragHandle` share the same height Breakpoint
    /// (see `OverlayLayout.breakpoints`), so either's absence is used as
    /// the "very short" signal that reflows the transport row into a
    /// single inline row beside the thumbnail rather than stacked beneath
    /// it — the stacked arrangement genuinely can't fit the fixed
    /// `discSize`-tall thumbnail above a second row within heights that
    /// short (see `compactTransportRowStackedConstraints`'s own doc
    /// comment).
    ///
    /// Returns whether it just triggered that Lyrics-Face dismissal, so
    /// `update(layout:)`'s own Lyrics/Settings-Face guard (which runs
    /// right after this) can treat the crossfade already underway the
    /// same as the Lyrics Face being closed, rather than reading
    /// `lyricsFace.isHidden`'s still-stale pre-animation value and
    /// fighting it.
    @discardableResult
    private func applyCompactControls() -> Bool {
        guard !isFullLayout else { return false }

        func isVisible(_ control: OverlayLayout.CompactControl) -> Bool {
            visibleCompactControls.contains(control)
        }

        compactSettingsButton.isHidden = !isVisible(.settingsButton)
        compactMuteButton.isHidden = !isVisible(.muteButton)
        compactShuffleButton.isHidden = !isVisible(.shuffleButton)
        compactRepeatButton.isHidden = !isVisible(.repeatButton)
        compactShareButton.isHidden = !isVisible(.shareButton)
        // Only ever force-hidden here, never force-shown: whether it's
        // actually visible at rest is `revealVolumeSlider`'s own call,
        // driven by hovering `compactMuteButton` specifically — which no
        // longer exists to hover once `muteButton` itself is hidden.
        if !isVisible(.muteButton) {
            volumeSlider.isHidden = true
        }

        let dragHandleAtCorner = !isVisible(.settingsButton)
        NSLayoutConstraint.deactivate(dragHandleAtCorner ? compactDragHandleFullTierConstraints : compactDragHandleReducedTierConstraints)
        NSLayoutConstraint.activate(dragHandleAtCorner ? compactDragHandleReducedTierConstraints : compactDragHandleFullTierConstraints)

        closeButton?.isHidden = !isVisible(.hideButton)
        compactDragHandle.isHidden = !isVisible(.dragHandle)
        compactPreviousButton.isHidden = !isVisible(.previousButton)
        // Overwrites `update(layout:)`'s own earlier `= isFullLayout`
        // assignment (always `false` here, since this method already
        // guarded on `!isFullLayout`) with the Breakpoint-aware final word.
        lyricsButton.isHidden = !isVisible(.lyricsButton)

        // Reflows into a single row — thumbnail, title, play/next side by
        // side — dropping the artist line and moving `compactTransportRow`
        // beside `compactThumbnailTextRow` instead of stacking it beneath,
        // once the Overlay is too short for the stacked arrangement (see
        // this method's own doc comment).
        let isVeryShort = !isVisible(.hideButton)
        artistLabel.isHidden = isVeryShort
        NSLayoutConstraint.deactivate(isVeryShort ? compactTransportRowStackedConstraints : compactTransportRowInlineConstraints)
        NSLayoutConstraint.activate(isVeryShort ? compactTransportRowInlineConstraints : compactTransportRowStackedConstraints)

        // Called from `update(layout:)` *before* its own Lyrics/Settings-
        // Face guard runs (see that call site's own comment on why), so
        // `lyricsFace.isHidden` here still reflects reality at the exact
        // moment a resize just hid the lyrics button — including if the
        // Lyrics Face was open at that moment. There's no way to have
        // newly opened it *while already* hidden, since `lyricsButton`
        // itself is hidden throughout, so this only ever fires on that one
        // crossing, never repeatedly.
        guard !isVisible(.lyricsButton), !lyricsFace.isHidden else { return false }
        showNowPlaying()
        return true
    }

    /// Rotates the Disc's artwork to `degrees` — `DiscRotation`'s current
    /// estimate, or its frozen angle while paused. A CALayer transform,
    /// not `NSView.frameCenterRotation`: the latter mutates the view's own
    /// frame, which fights Auto Layout's own relayout on every pass and
    /// produced a visibly broken spin; a layer transform is purely a
    /// render-time effect Auto Layout never looks at.
    func update(rotationDegrees: Double) {
        let radians = CGFloat(rotationDegrees) * .pi / 180
        discImageView.layer?.transform = CATransform3DMakeRotation(radians, 0, 0, 1)
    }

    /// Shows real album art on both Compact and Full Layout — no tint, the
    /// art speaks for itself. Full Layout's background defaults to this
    /// same plain image too — showing it immediately, before the blurred
    /// treatment finishes computing, and matching what "blurred background
    /// off" itself shows; `updateBlurredBackground` overrides it once the
    /// blur is ready and enabled.
    func updateArtwork(_ image: NSImage) {
        discImageView.contentTintColor = nil
        discImageView.image = image
        fullArtworkView.contentTintColor = nil
        fullArtworkView.image = image
        fullArtworkBackgroundView.contentTintColor = nil
        fullArtworkBackgroundView.image = image
    }

    /// Back to the placeholder — no artwork or track name known yet, or a
    /// confirmed no-artwork outcome. Real track info follows immediately
    /// via `updateTrackInfo` whenever a Track is actually known.
    func updatePlaceholder() {
        discImageView.contentTintColor = OverlayArtworkPlaceholder.tint
        discImageView.image = OverlayArtworkPlaceholder.image(pointSize: 16)
        fullArtworkView.contentTintColor = OverlayArtworkPlaceholder.tint
        fullArtworkView.image = OverlayArtworkPlaceholder.image(pointSize: 32)
        fullArtworkBackgroundView.contentTintColor = OverlayArtworkPlaceholder.tint
        fullArtworkBackgroundView.image = OverlayArtworkPlaceholder.image(pointSize: 32)
        titleLabel.stringValue = LyricsCardView.nothingPlayingText
        artistLabel.stringValue = ""
        fullTitleLabel.stringValue = LyricsCardView.nothingPlayingText
        fullArtistLabel.stringValue = ""
    }

    /// Full Layout's background once the blurred/color-boosted treatment
    /// is ready and enabled — the caller (`OverlayController`) decides
    /// whether that's this image or the plain artwork, since it's the one
    /// holding both the cached blur and the current toggle state.
    func updateBlurredBackground(_ image: NSImage) {
        fullArtworkBackgroundView.image = image
    }

    /// Seeds the settings panel's toggle from the persisted preference —
    /// called once at startup, since nothing else in this view ever
    /// changes it out from under the switch itself.
    func update(blurredBackgroundEnabled: Bool) {
        blurredBackgroundSwitch.state = blurredBackgroundEnabled ? .on : .off
    }

    /// The current Track's name and artist, shown on whichever Now Playing
    /// content (Compact or Full Layout) is current.
    func updateTrackInfo(name: String, artist: String) {
        titleLabel.stringValue = name
        artistLabel.stringValue = artist
        fullTitleLabel.stringValue = name
        fullArtistLabel.stringValue = artist
    }

    func update(isPlaying: Bool) {
        let symbolName = isPlaying ? "pause.fill" : "play.fill"
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Play/Pause")
        playPauseButton.image = image
        fullPlayPauseButton.image = image
    }

    /// Whichever Now Playing content is current — Compact or Full
    /// Layout's — the one `update(layout:)` last selected.
    private var activeNowPlayingFace: NSView { isFullLayout ? fullFace : compactFace }

    /// Crossfades to the Lyrics face, from whichever Now Playing content is
    /// current. Compact Layout's controls overlay is unaffected — hovering
    /// still reveals the same transport, seek, and volume controls, so
    /// playback stays reachable while reading along; Full Layout has no
    /// hover controls of its own yet to worry about.
    func showLyrics() {
        crossfade(from: activeNowPlayingFace, to: lyricsFace)
        lyricsButton.contentTintColor = .white
        fullLyricsButton.contentTintColor = .white
        // Unlike `lyricsButton`/`fullLyricsButton`, the resize-handle glyph
        // has no reason to stay reachable over the Lyrics Face, and being
        // a sibling of `self` (not nested in `compactFace`/`fullFace`)
        // means it isn't hidden by either of those cascading already.
        resizeHandleImageView.isHidden = true
    }

    /// Crossfades back to whichever Now Playing content is current.
    func showNowPlaying() {
        crossfade(from: lyricsFace, to: activeNowPlayingFace)
        lyricsButton.contentTintColor = .white.withAlphaComponent(0.7)
        fullLyricsButton.contentTintColor = .white.withAlphaComponent(0.7)
        resizeHandleImageView.isHidden = false
    }

    /// What the Lyrics face shows — forwarded straight to `LyricsCardView`,
    /// updated regardless of whether it's currently the visible face, so
    /// it's already current the moment the listener switches to it.
    func updateLyrics(_ content: LyricsCardView.Content) {
        lyricsFace.update(with: content)
    }

    /// Sets Full Layout's seek slider range to the current Track's
    /// duration. Called once per Track, not on every Anchor. Compact
    /// Layout has no seek slider of its own to set — seeking is
    /// exclusively a Full Layout capability.
    func configureSeek(duration: TimeInterval) {
        trackDuration = max(duration, 1)
        fullSeekSlider.minValue = 0
        fullSeekSlider.maxValue = trackDuration
    }

    /// Moves Full Layout's seek slider thumb to `position`, and its
    /// elapsed/remaining labels alongside it — ignored while the listener
    /// is actively dragging it, so a redraw never yanks the thumb out from
    /// under their cursor.
    func updateSeek(position: TimeInterval) {
        guard !isDraggingSeek else { return }
        fullSeekSlider.doubleValue = position
        elapsedLabel.stringValue = PlaybackTimeFormat.string(forSeconds: position)
        remainingLabel.stringValue = "-" + PlaybackTimeFormat.string(forSeconds: trackDuration - position)
    }

    /// Sets both volume sliders' thumb to Spotify's actual current volume —
    /// called once when the controls first appear, so the first drag
    /// starts from the real value rather than jumping Spotify's volume to
    /// wherever the thumb happened to be drawn. Ignored while being
    /// dragged, same as `updateSeek`. Also seeds `isMuted`/
    /// `lastNonZeroVolume` from this same real value, so the mute icon
    /// never disagrees with Spotify's actual starting volume.
    func updateVolume(_ percent: Int) {
        guard !isDraggingVolume else { return }
        applyVolume(percent)
    }

    /// Applies `percent` to both volume sliders, `isMuted`, and
    /// `lastNonZeroVolume` together — the one place all three ever change,
    /// shared by `updateVolume`, a committed slider drag, and the mute
    /// button's own toggle, so the three can never drift out of sync with
    /// each other.
    private func applyVolume(_ percent: Int) {
        volumeSlider.doubleValue = Double(percent)
        fullVolumeSlider.doubleValue = Double(percent)
        isMuted = percent == 0
        if percent > 0 { lastNonZeroVolume = percent }
        updateMuteIcon()
    }

    /// Sets both mute buttons' glyph to reflect `isMuted` — muted and
    /// unmuted are visually distinct symbols, not a tint change, so the
    /// state reads at a glance without needing to also check the slider.
    private func updateMuteIcon() {
        let symbolName = isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"
        let image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: isMuted ? "Unmute" : "Mute"
        )
        fullMuteButton.image = image
        compactMuteButton.image = image
    }

    /// Fades `from` out and `to` in together, leaving only `to` visible
    /// (and un-hidden) once the animation settles — a plain `isHidden`
    /// toggle would jump instantly, which is what this replaces.
    private func crossfade(from: NSView, to: NSView) {
        to.alphaValue = 0
        to.isHidden = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.crossfadeDuration
            from.animator().alphaValue = 0
            to.animator().alphaValue = 1
        } completionHandler: {
            // AppKit always calls this back on the main thread, but the
            // completion handler's type isn't itself @MainActor — same
            // situation as `OverlayController`'s NotificationCenter/Timer
            // callbacks.
            MainActor.assumeIsolated {
                from.isHidden = true
            }
        }
    }

    private func configureCompactFace() {
        discImageView.wantsLayer = true
        discImageView.layer?.cornerRadius = Self.discCornerRadius
        discImageView.layer?.masksToBounds = true
        // Fills the disc exactly — the rounded-square mask above clips
        // whatever doesn't fit.
        discImageView.image = OverlayArtworkPlaceholder.image(pointSize: 16)
        discImageView.contentTintColor = OverlayArtworkPlaceholder.tint
        discImageView.imageScaling = .scaleProportionallyDown
        discImageView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        artistLabel.font = .systemFont(ofSize: 11, weight: .regular)
        artistLabel.textColor = .white.withAlphaComponent(0.7)
        artistLabel.lineBreakMode = .byTruncatingTail
        artistLabel.maximumNumberOfLines = 1
        artistLabel.translatesAutoresizingMaskIntoConstraints = false

        let textStack = NSStackView(views: [titleLabel, artistLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2

        // A stored property, not a local variable: `configureCompactTransportRow`
        // (built afterward) needs to position `compactTransportRow`
        // relative to it once the Overlay is very short, where the two sit
        // side by side in one row instead of stacked.
        let row = compactThumbnailTextRow
        row.setViews([discImageView, textStack], in: .leading)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false

        // Without this, a long real Track title's default (high)
        // compression resistance refuses to shrink below its own full
        // width, so `.byTruncatingTail` above never actually engages —
        // see `suppressIntrinsicSizeGrowthPressure`'s own comment.
        [titleLabel, artistLabel, textStack, row].forEach(suppressIntrinsicSizeGrowthPressure)

        // The spot Spotify's own Mini Player gives its X/add-to-library
        // pair — always visible (not hover-gated) whenever Compact Layout
        // is current, the same as `fullLyricsButton` is for Full Layout.
        // Already a subview of `self` (added in `init()`, alongside
        // `fullLyricsButton`) so it renders above `lyricsFace`/
        // `settingsFace` and stays reachable while either is showing.
        lyricsButton.image = NSImage(systemSymbolName: "quote.bubble", accessibilityDescription: "Lyrics")
        styleTransportButton(lyricsButton)
        lyricsButton.contentTintColor = .white.withAlphaComponent(0.7)
        lyricsButton.target = self
        lyricsButton.action = #selector(lyricsTapped)
        // A plain `addSubview`, not an NSStackView arranged subview the
        // way it used to be — a stack view disables this automatically
        // for its own arranged subviews, but added directly like this it
        // defaults to `true`, which fights the explicit constraints below
        // with an auto-generated frame constraint of its own.
        lyricsButton.translatesAutoresizingMaskIntoConstraints = false

        compactFace.translatesAutoresizingMaskIntoConstraints = false
        compactFace.addSubview(row)
        addSubview(compactFace)

        NSLayoutConstraint.activate([
            discImageView.widthAnchor.constraint(equalToConstant: Self.discSize),
            discImageView.heightAnchor.constraint(equalToConstant: Self.discSize),

            row.leadingAnchor.constraint(equalTo: compactFace.leadingAnchor, constant: 16),
            // Truncates before it can ever reach the lyrics button, not a
            // fixed inset — mirrors `fullTextStack`/`fullLyricsButton`'s
            // own relationship exactly.
            row.trailingAnchor.constraint(lessThanOrEqualTo: lyricsButton.leadingAnchor, constant: -8),
            // See `maximumRowWidth`'s own comment: a real, non-circular
            // ceiling, independent of this view's own (window-derived)
            // width, is what actually makes a long title truncate instead
            // of growing the window to fit it.
            row.widthAnchor.constraint(lessThanOrEqualToConstant: Self.maximumRowWidth),
            row.centerYAnchor.constraint(equalTo: compactFace.centerYAnchor),

            compactFace.leadingAnchor.constraint(equalTo: leadingAnchor),
            compactFace.trailingAnchor.constraint(equalTo: trailingAnchor),
            compactFace.topAnchor.constraint(equalTo: topAnchor),
            compactFace.bottomAnchor.constraint(equalTo: bottomAnchor),

            lyricsButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            lyricsButton.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])
    }

    /// Lowers `view`'s content compression resistance to the point of
    /// having none, on both axes. Every view whose real content (a
    /// fetched artwork image, a Track's actual title or artist) can be far
    /// bigger than the small, often-truncated size it's meant to render at
    /// needs this: content compression resistance defaults *high*, which
    /// otherwise insists on staying at least as large as that real
    /// content — for a label, that means truncation (`.byTruncatingTail`)
    /// never actually engages; for a view whose position constraints are
    /// conditionally inactive (Full Layout's own content, kept out of the
    /// hierarchy entirely while Compact Layout is current — see
    /// `fullLayoutContentConstraints`'s own comment), it's the *only*
    /// thing left determining its size once nothing else constrains it.
    /// Either way, that "at least this large" pressure feeds into the
    /// window's own automatic content-based sizing and grows the whole
    /// Overlay to fit — confirmed by watching it happen live, for both a
    /// long real Track title in Compact Layout and real artwork/track
    /// info loading into Full Layout's own (otherwise-unconstrained)
    /// content a few seconds after launch.
    private func suppressIntrinsicSizeGrowthPressure(_ view: NSView) {
        view.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        view.setContentCompressionResistancePriority(.init(1), for: .vertical)
    }

    /// Full Layout's Now Playing content: a big square artwork area (a
    /// blurred/color-boosted, or plain, backdrop behind a smaller sharp
    /// copy of the same artwork), an always-visible seek bar with
    /// elapsed/remaining time, and the current Track's title/artist beside
    /// a persistent lyrics-toggle button — the bottom-corner spot
    /// Spotify's own Mini Player gives its "add to library" button.
    private func configureFullLayoutFace() {
        fullArtworkBackgroundView.wantsLayer = true
        fullArtworkBackgroundView.layer?.cornerRadius = Self.fullArtworkCornerRadius
        fullArtworkBackgroundView.layer?.masksToBounds = true
        fullArtworkBackgroundView.image = OverlayArtworkPlaceholder.image(pointSize: 32)
        fullArtworkBackgroundView.contentTintColor = OverlayArtworkPlaceholder.tint
        fullArtworkBackgroundView.imageScaling = .scaleProportionallyUpOrDown
        fullArtworkBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        fullArtworkBackgroundView.setContentHuggingPriority(.init(1), for: .horizontal)
        fullArtworkBackgroundView.setContentHuggingPriority(.init(1), for: .vertical)

        fullArtworkView.wantsLayer = true
        fullArtworkView.layer?.cornerRadius = Self.fullArtworkCornerRadius
        fullArtworkView.layer?.masksToBounds = true
        fullArtworkView.image = OverlayArtworkPlaceholder.image(pointSize: 32)
        fullArtworkView.contentTintColor = OverlayArtworkPlaceholder.tint
        fullArtworkView.imageScaling = .scaleProportionallyDown
        fullArtworkView.translatesAutoresizingMaskIntoConstraints = false
        fullArtworkView.setContentHuggingPriority(.init(1), for: .horizontal)
        fullArtworkView.setContentHuggingPriority(.init(1), for: .vertical)

        fullTitleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        fullTitleLabel.textColor = .white
        fullTitleLabel.lineBreakMode = .byTruncatingTail
        fullTitleLabel.maximumNumberOfLines = 1
        fullTitleLabel.translatesAutoresizingMaskIntoConstraints = false

        fullArtistLabel.font = .systemFont(ofSize: 12, weight: .regular)
        fullArtistLabel.textColor = .white.withAlphaComponent(0.7)
        fullArtistLabel.lineBreakMode = .byTruncatingTail
        fullArtistLabel.maximumNumberOfLines = 1
        fullArtistLabel.translatesAutoresizingMaskIntoConstraints = false

        let fullTextStack = NSStackView(views: [fullTitleLabel, fullArtistLabel])
        fullTextStack.orientation = .vertical
        fullTextStack.alignment = .leading
        fullTextStack.spacing = 2
        fullTextStack.translatesAutoresizingMaskIntoConstraints = false

        fullLyricsButton.image = NSImage(systemSymbolName: "quote.bubble", accessibilityDescription: "Lyrics")
        styleTransportButton(fullLyricsButton)
        fullLyricsButton.contentTintColor = .white.withAlphaComponent(0.7)
        fullLyricsButton.target = self
        fullLyricsButton.action = #selector(lyricsTapped)
        fullLyricsButton.translatesAutoresizingMaskIntoConstraints = false

        elapsedLabel.font = .systemFont(ofSize: 10, weight: .regular)
        elapsedLabel.textColor = .white.withAlphaComponent(0.7)
        elapsedLabel.translatesAutoresizingMaskIntoConstraints = false
        elapsedLabel.setContentHuggingPriority(.required, for: .horizontal)

        remainingLabel.font = .systemFont(ofSize: 10, weight: .regular)
        remainingLabel.textColor = .white.withAlphaComponent(0.7)
        remainingLabel.alignment = .right
        remainingLabel.translatesAutoresizingMaskIntoConstraints = false
        remainingLabel.setContentHuggingPriority(.required, for: .horizontal)

        // The only seek slider anywhere in the Overlay — Compact Layout
        // has none of its own; seeking is exclusively a Full Layout
        // capability. `seekSliderChanged`/`isDraggingSeek` still exist as
        // the commit-on-release gate `volumeSliderChanged`/
        // `isDraggingVolume` mirrors for the mute/volume control's own
        // two instances.
        styleSlider(fullSeekSlider, min: 0, max: 1)
        fullSeekSlider.target = self
        fullSeekSlider.action = #selector(seekSliderChanged)

        let seekRow = NSStackView(views: [elapsedLabel, fullSeekSlider, remainingLabel])
        seekRow.orientation = .horizontal
        seekRow.spacing = 8
        seekRow.translatesAutoresizingMaskIntoConstraints = false

        // Every dynamic-content view built above needs this — see
        // `suppressIntrinsicSizeGrowthPressure`'s own comment for why.
        [fullArtworkBackgroundView, fullArtworkView, fullTitleLabel, fullArtistLabel, fullTextStack, elapsedLabel, remainingLabel, fullSeekSlider, seekRow]
            .forEach(suppressIntrinsicSizeGrowthPressure)

        fullFace.translatesAutoresizingMaskIntoConstraints = false
        // Background added first, so it renders behind the sharp copy —
        // NSView z-order follows subview array order.
        fullFace.addSubview(fullArtworkBackgroundView)
        fullFace.addSubview(fullArtworkView)
        fullFace.addSubview(seekRow)
        fullFace.addSubview(fullTextStack)
        configureFullControlsOverlay()
        configureFullTopChromeBar()
        // Not added as a subview of `self` here — see
        // `fullLayoutContentConstraints`'s own comment: `update(layout:)`
        // adds it only while Full Layout is actually current.

        // A sibling of `fullFace`, not one of its subviews: it must stay
        // reachable even while the Lyrics face is showing (so the listener
        // always has a way back), the same way Compact Layout's own
        // `lyricsButton` is a sibling of `compactFace` rather than a
        // subview of it.
        addSubview(fullLyricsButton)

        // `fullFace` itself is kept out of the view hierarchy entirely
        // (not just hidden) until Full Layout is actually current —
        // `update(layout:)` adds it and activates these constraints
        // together, and removes it after deactivating them. A view
        // outside the hierarchy entirely can't influence anything's
        // sizing, no matter what its own content-size properties are set
        // to — see `suppressIntrinsicSizeGrowthPressure`'s own comment
        // for the underlying mechanism this sidesteps.
        //
        // The artwork's width is pinned to `fullFace`'s own width exactly
        // (leading and trailing both fixed) rather than capped with an
        // oversized-low-priority "grow as big as possible" constraint —
        // the usual trick for an ordinary view, but not a safe one for a
        // window's own content view (again, see
        // `suppressIntrinsicSizeGrowthPressure`). Pinning both edges
        // exactly removes any pull at all: the artwork always exactly
        // matches whatever width the window
        // already has, never asks for more.
        fullLayoutContentConstraints = [
            fullArtworkBackgroundView.leadingAnchor.constraint(equalTo: fullFace.leadingAnchor, constant: 16),
            fullArtworkBackgroundView.trailingAnchor.constraint(equalTo: fullFace.trailingAnchor, constant: -16),
            fullArtworkBackgroundView.heightAnchor.constraint(equalTo: fullArtworkBackgroundView.widthAnchor),
            fullArtworkBackgroundView.topAnchor.constraint(equalTo: fullFace.topAnchor, constant: 16),
            // A minimum gap, not a fixed position — the bottom rows below
            // are anchored from the bottom up. If the window is wide
            // enough relative to its height that the width-matched square
            // wouldn't leave room for them, this constraint is the one
            // that gives (a visual clipping concern, not a window-growth
            // one) — Full Layout at very short, very wide sizes is an
            // extreme this static skeleton doesn't attempt to handle
            // gracefully yet.
            fullArtworkBackgroundView.bottomAnchor.constraint(lessThanOrEqualTo: seekRow.topAnchor, constant: -12),

            // The sharp copy: smaller, centered within the background
            // square rather than filling it — see
            // `fullArtworkForegroundScale`'s own comment.
            fullArtworkView.centerXAnchor.constraint(equalTo: fullArtworkBackgroundView.centerXAnchor),
            fullArtworkView.centerYAnchor.constraint(equalTo: fullArtworkBackgroundView.centerYAnchor),
            fullArtworkView.widthAnchor.constraint(equalTo: fullArtworkBackgroundView.widthAnchor, multiplier: Self.fullArtworkForegroundScale),
            fullArtworkView.heightAnchor.constraint(equalTo: fullArtworkView.widthAnchor),

            seekRow.leadingAnchor.constraint(equalTo: fullFace.leadingAnchor, constant: 16),
            seekRow.trailingAnchor.constraint(equalTo: fullFace.trailingAnchor, constant: -16),
            seekRow.bottomAnchor.constraint(equalTo: fullTextStack.topAnchor, constant: -10),

            fullTextStack.leadingAnchor.constraint(equalTo: fullFace.leadingAnchor, constant: 16),
            fullTextStack.trailingAnchor.constraint(lessThanOrEqualTo: fullLyricsButton.leadingAnchor, constant: -8),
            fullTextStack.centerYAnchor.constraint(equalTo: fullLyricsButton.centerYAnchor),

            // Overlaid across the whole square — `fullArtworkBackgroundView`,
            // not the now-smaller `fullArtworkView` copy — both are
            // `fullFace` subviews built together, so referencing it here is
            // always safe: it never outlives `fullFace`'s own membership in
            // the hierarchy, which this whole array's activate/deactivate
            // cycle already tracks.
            fullControlsOverlay.centerXAnchor.constraint(equalTo: fullArtworkBackgroundView.centerXAnchor),
            fullControlsOverlay.centerYAnchor.constraint(equalTo: fullArtworkBackgroundView.centerYAnchor),

            // Sits just inside the square's own top edge, not `fullFace`'s —
            // matching Spotify Mini Player's own chrome bar, floating on
            // the art rather than above it.
            fullTopChromeBar.leadingAnchor.constraint(equalTo: fullArtworkBackgroundView.leadingAnchor, constant: 12),
            fullTopChromeBar.trailingAnchor.constraint(equalTo: fullArtworkBackgroundView.trailingAnchor, constant: -12),
            fullTopChromeBar.topAnchor.constraint(equalTo: fullArtworkBackgroundView.topAnchor, constant: 10),

            // `fullFace`'s own pin-to-self — grouped with the rest here,
            // not activated unconditionally, since it only makes sense
            // once `fullFace` has actually been added as a subview of
            // `self` (which requires a common ancestor to resolve
            // against), which `update(layout:)` does immediately before
            // activating this whole array.
            fullFace.leadingAnchor.constraint(equalTo: leadingAnchor),
            fullFace.trailingAnchor.constraint(equalTo: trailingAnchor),
            fullFace.topAnchor.constraint(equalTo: topAnchor),
            fullFace.bottomAnchor.constraint(equalTo: bottomAnchor),
        ]

        // Positioned relative to `self`, not `fullFace` — always active
        // (unlike the group above), since a fixed-intrinsic-size button
        // pinned to a corner imposes no minimum-size pressure the way the
        // toggleable content above does, and it must stay positioned
        // correctly even while hidden in Compact Layout, ready to appear
        // the instant a resize crosses into Full Layout.
        NSLayoutConstraint.activate([
            fullLyricsButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            fullLyricsButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
        ])
    }

    /// Full Layout's transport row — mute, shuffle, previous, play/pause,
    /// next, repeat, share — overlaid on the artwork and faded in/out on
    /// hover (`mouseEntered`/`mouseExited`), alongside `fullTopChromeBar`.
    /// A `fullFace` subview, not a sibling of `self` the way
    /// `fullLyricsButton` is: it has no need to survive into the Lyrics
    /// face the way the lyrics-toggle button itself does, so it can
    /// simply ride `fullFace`'s own add/remove cycle. Compact Layout's own
    /// `compactTransportRow` is a `compactFace` subview for the analogous
    /// reason, riding `compactFace`'s own `isHidden` cascade instead.
    private func configureFullControlsOverlay() {
        fullControlsOverlay.translatesAutoresizingMaskIntoConstraints = false
        fullControlsOverlay.alphaValue = 0
        fullFace.addSubview(fullControlsOverlay)

        // Full Layout never needs to reference its own previous/shuffle/
        // repeat/share buttons again — throwaway instances, unlike
        // Compact Layout's own, which `applyCompactControls()` hides once
        // its own Breakpoint is crossed.
        let row = configureTransportRow(
            muteButton: fullMuteButton,
            volumeSlider: fullVolumeSlider,
            previousButton: NSButton(),
            playPauseButton: fullPlayPauseButton,
            shuffleButton: NSButton(),
            repeatButton: NSButton(),
            shareButton: NSButton()
        )
        fullControlsOverlay.addSubview(row)

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: fullControlsOverlay.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: fullControlsOverlay.trailingAnchor),
            row.topAnchor.constraint(equalTo: fullControlsOverlay.topAnchor),
            row.bottomAnchor.constraint(equalTo: fullControlsOverlay.bottomAnchor),
        ])
    }

    /// Builds the shared transport row — mute, shuffle, previous, play/
    /// pause, next, repeat, share — wiring `muteButton`/`slider`/
    /// `playPause`/`shuffleButton`/`previousButton`/`repeatButton`/
    /// `shareButton` to their shared action handlers. Shared by
    /// `configureFullControlsOverlay`/`configureCompactTransportRow`: the
    /// same elements, arranged identically, in two separate instances
    /// since only one layout's own row is ever visible at once.
    /// `updateMuteIcon()` runs here (not left to the caller) so whichever
    /// row is configured first always leaves both mute buttons' glyphs
    /// correct, regardless of `init()`'s own call order.
    ///
    /// Every button but `nextButton` is taken as a param (like
    /// `muteButton`/`slider`/`playPause` already were), not built
    /// internally: Compact Layout needs to keep its own reference to each
    /// one `applyCompactControls()` hides once its own
    /// `OverlayLayout.Breakpoint` is crossed — so its caller passes real
    /// stored properties, while Full Layout's own (which never hides any
    /// of them) passes throwaway instances. `nextButton` stays
    /// internal-only — it has no Breakpoint of its own, so nothing outside
    /// this method needs to reach it again.
    private func configureTransportRow(
        muteButton: NSButton,
        volumeSlider slider: NSSlider,
        previousButton: NSButton,
        playPauseButton playPause: NSButton,
        shuffleButton: NSButton,
        repeatButton: NSButton,
        shareButton: NSButton
    ) -> NSStackView {
        updateMuteIcon()
        styleTransportButton(muteButton)
        muteButton.target = self
        muteButton.action = #selector(muteTapped)

        styleSlider(slider, min: 0, max: 100)
        slider.target = self
        slider.action = #selector(volumeSliderChanged)
        // Hidden until the mute hover zone is entered — a hidden arranged
        // subview collapses its own space (and surrounding spacing) in
        // the row automatically, the same way any NSStackView member does.
        slider.isHidden = true
        NSLayoutConstraint.activate([
            slider.widthAnchor.constraint(equalToConstant: Self.fullVolumeSliderWidth),
        ])

        shuffleButton.image = NSImage(systemSymbolName: "shuffle", accessibilityDescription: nil)
        styleTransportButton(shuffleButton)
        shuffleButton.target = self
        shuffleButton.action = #selector(shuffleTapped)

        previousButton.image = NSImage(systemSymbolName: "backward.fill", accessibilityDescription: nil)
        styleTransportButton(previousButton)
        previousButton.target = self
        previousButton.action = #selector(previousTapped)

        playPause.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "Play/Pause")
        styleTransportButton(playPause)
        playPause.target = self
        playPause.action = #selector(playPauseTapped)

        let nextButton = transportButton(symbolName: "forward.fill", action: #selector(nextTapped))

        repeatButton.image = NSImage(systemSymbolName: "repeat", accessibilityDescription: nil)
        styleTransportButton(repeatButton)
        repeatButton.target = self
        repeatButton.action = #selector(repeatTapped)

        // Repurposes the transport row's own share affordance for
        // `SpotifyShareLink`'s clipboard copy rather than opening a share
        // sheet, per the ticket's own decision.
        shareButton.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: nil)
        styleTransportButton(shareButton)
        shareButton.target = self
        shareButton.action = #selector(shareTapped)

        // Every button suppressed alongside `row` itself, not just the
        // row — matching `suppressIntrinsicSizeGrowthPressure`'s own use
        // elsewhere (always applied to the full leaf-view list together).
        // Fixed inter-item spacing is the dominant contributor to this
        // row's own minimum width, but leaving the buttons at their
        // default (high) resistance is still real, if smaller, pressure
        // this suppresses defensively — relevant once narrower Compact
        // tiers (later tickets) need this same row to compress further.
        let row = NSStackView(views: [muteButton, slider, shuffleButton, previousButton, playPause, nextButton, repeatButton, shareButton])
        row.orientation = .horizontal
        row.spacing = Self.fullTransportRowSpacing
        row.translatesAutoresizingMaskIntoConstraints = false
        [muteButton, shuffleButton, previousButton, playPause, nextButton, repeatButton, shareButton, row]
            .forEach(suppressIntrinsicSizeGrowthPressure)

        return row
    }

    /// Full Layout's top chrome bar — the real system close button
    /// (ADR-0012, installed later by `installCloseButton(_:)`), a
    /// decorative drag-handle indicator, and the settings icon — faded
    /// in/out on the same hover as `fullControlsOverlay`. Full Layout
    /// never narrows this bar the way Compact Layout's own tiers do, so
    /// the drag handle's centered position is activated immediately and
    /// permanently.
    private func configureFullTopChromeBar() {
        fullTopChromeBar.translatesAutoresizingMaskIntoConstraints = false
        fullTopChromeBar.alphaValue = 0
        fullFace.addSubview(fullTopChromeBar)
        // Full Layout never needs to reference its own drag handle again
        // — a throwaway instance, unlike Compact Layout's own
        // `compactDragHandle`, which `applyCompactControls()` repositions.
        let centeredConstraints = configureChromeBar(
            fullTopChromeBar, settingsButton: settingsButton, dragHandle: PassthroughImageView()
        )
        NSLayoutConstraint.activate(centeredConstraints)
    }

    /// Compact Layout's own top chrome bar — the same close/drag/settings
    /// elements as `fullTopChromeBar`, faded in/out on the same hover as
    /// `compactTransportRow`. A `compactFace` subview, not a sibling of
    /// `self` the way `lyricsButton` is: unlike the lyrics button, it has
    /// no need to survive into the Lyrics or Settings Face, so it can
    /// simply ride `compactFace`'s own `isHidden` cascade. Unlike Full
    /// Layout's own bar, the drag handle's position here isn't permanent
    /// — `applyCompactControls()` swaps it between this centered position
    /// and a spot beside the close button once the settings button is no
    /// longer visible.
    private func configureCompactChromeBar() {
        compactChromeBar.translatesAutoresizingMaskIntoConstraints = false
        compactChromeBar.alphaValue = 0
        compactFace.addSubview(compactChromeBar)
        compactDragHandleFullTierConstraints = configureChromeBar(
            compactChromeBar, settingsButton: compactSettingsButton, dragHandle: compactDragHandle
        )
        NSLayoutConstraint.activate(compactDragHandleFullTierConstraints)

        NSLayoutConstraint.activate([
            compactChromeBar.leadingAnchor.constraint(equalTo: compactFace.leadingAnchor, constant: 16),
            compactChromeBar.trailingAnchor.constraint(equalTo: compactFace.trailingAnchor, constant: -16),
            compactChromeBar.topAnchor.constraint(equalTo: compactFace.topAnchor, constant: 8),
        ])
    }

    /// Builds a top chrome bar — `dragHandle` and the settings icon — into
    /// `bar`. The real close button isn't part of this: it doesn't exist
    /// yet at this method's call time (`installCloseButton(_:)` installs
    /// it later, once a window exists to ask for one) and, unlike
    /// `dragHandle`/`settings`, there's only one of it shared between both
    /// layouts rather than one instance per bar. Shared by
    /// `configureFullTopChromeBar`/`configureCompactChromeBar`: the same
    /// two elements, arranged identically, in two separate instances
    /// since only one layout's own bar is ever visible at once — the
    /// same reason `configureTransportRow` takes its own buttons as
    /// params rather than building them internally. The drag-handle
    /// indicator is a `PassthroughImageView`, not a plain button: it's
    /// decorative only, so a click on it must fall through to
    /// `DraggableBackgroundView` and start a drag exactly as it would
    /// anywhere else non-interactive on the card, rather than swallowing
    /// the event itself.
    ///
    /// Returns `dragHandle`'s own centered-in-`bar` constraints, not yet
    /// activated — activating them is the caller's own call, since
    /// Compact Layout's tiers need to swap this position out later, while
    /// Full Layout's never changes.
    private func configureChromeBar(
        _ bar: NSView, settingsButton settings: NSButton, dragHandle: PassthroughImageView
    ) -> [NSLayoutConstraint] {
        dragHandle.image = NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: nil)
        dragHandle.contentTintColor = .white.withAlphaComponent(0.4)
        dragHandle.translatesAutoresizingMaskIntoConstraints = false

        settings.image = NSImage(systemSymbolName: "gearshape.fill", accessibilityDescription: "Settings")
        styleTransportButton(settings)
        settings.contentTintColor = .white.withAlphaComponent(0.7)
        settings.target = self
        settings.action = #selector(settingsTapped)
        settings.translatesAutoresizingMaskIntoConstraints = false

        bar.addSubview(dragHandle)
        bar.addSubview(settings)

        NSLayoutConstraint.activate([
            bar.heightAnchor.constraint(equalToConstant: Self.chromeBarHeight),

            settings.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            settings.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
        ])

        return [
            dragHandle.centerXAnchor.constraint(equalTo: bar.centerXAnchor),
            dragHandle.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
        ]
    }

    /// Installs the window's one real system close button (ADR-0012) —
    /// called once by `OverlayController` right after creating the
    /// Overlay's window, since no window (and so no `standardWindowButton`)
    /// exists yet at `init()` time. Replaces the hand-drawn hide dot
    /// outright: the same button object is reparented between
    /// `fullTopChromeBar` and `compactChromeBar` by `reparentCloseButton()`
    /// as the layout changes, since there's only one real button to share
    /// between them.
    ///
    /// `compactDragHandleReducedTierConstraints` is built here, not in
    /// `configureCompactChromeBar()`, for the same reason: it anchors to
    /// this button's trailing edge, which doesn't exist until now.
    func installCloseButton(_ button: NSButton) {
        button.translatesAutoresizingMaskIntoConstraints = false
        closeButton = button

        closeButtonFullConstraints = [
            button.leadingAnchor.constraint(equalTo: fullTopChromeBar.leadingAnchor),
            button.centerYAnchor.constraint(equalTo: fullTopChromeBar.centerYAnchor),
        ]
        closeButtonCompactConstraints = [
            button.leadingAnchor.constraint(equalTo: compactChromeBar.leadingAnchor),
            button.centerYAnchor.constraint(equalTo: compactChromeBar.centerYAnchor),
        ]

        // Sits directly beside the close button, sharing its own vertical
        // center — reads as one small cluster in the bar's leading
        // corner, matching the ticket's own "alongside the hide dot"
        // framing, rather than a second element floating elsewhere.
        compactDragHandleReducedTierConstraints = [
            compactDragHandle.leadingAnchor.constraint(equalTo: button.trailingAnchor, constant: 6),
            compactDragHandle.centerYAnchor.constraint(equalTo: compactChromeBar.centerYAnchor),
        ]

        reparentCloseButton()
    }

    /// Moves the shared close button into whichever chrome bar matches
    /// `isFullLayout`, called from `update(layout:)` whenever the Overlay
    /// crosses the Compact/Full boundary (`addSubview` on a view already
    /// elsewhere in the hierarchy moves it, rather than requiring an
    /// explicit remove first). Full Layout's own button is never hidden by
    /// a Breakpoint — Full Layout never narrows — so it's explicitly reset
    /// visible here; Compact Layout's own visibility is
    /// `applyCompactControls()`'s call, made right after this runs.
    private func reparentCloseButton() {
        guard let closeButton else { return }

        NSLayoutConstraint.deactivate(closeButtonFullConstraints)
        NSLayoutConstraint.deactivate(closeButtonCompactConstraints)

        if isFullLayout {
            fullTopChromeBar.addSubview(closeButton)
            NSLayoutConstraint.activate(closeButtonFullConstraints)
            closeButton.isHidden = false
        } else {
            compactChromeBar.addSubview(closeButton)
            NSLayoutConstraint.activate(closeButtonCompactConstraints)
        }
    }

    /// The decorative resize-handle glyph — hover-revealed alongside
    /// whichever layout's own chrome is currently fading in/out (see
    /// `mouseEntered`/`mouseExited`), reset to invisible in
    /// `update(layout:)` the same way that chrome already is.
    private func configureResizeHandle() {
        resizeHandleImageView.image = NSImage(systemSymbolName: Self.resizeHandleSymbolName, accessibilityDescription: nil)
        resizeHandleImageView.contentTintColor = .white.withAlphaComponent(0.4)
        resizeHandleImageView.alphaValue = 0
        resizeHandleImageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(resizeHandleImageView)

        NSLayoutConstraint.activate([
            resizeHandleImageView.widthAnchor.constraint(equalToConstant: Self.resizeHandleSize),
            resizeHandleImageView.heightAnchor.constraint(equalToConstant: Self.resizeHandleSize),
            resizeHandleImageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.resizeHandleInset),
            resizeHandleImageView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.resizeHandleInset),
        ])
    }

    /// The settings panel: one clearly-labelled toggle for the blurred
    /// background, and a Done button back. A sibling of `self`, pinned to
    /// its full bounds exactly like `lyricsFace` — reachable regardless of
    /// which Now Playing/Lyrics face is underneath, the same way opening
    /// it can be reached from either.
    private func configureSettingsFace() {
        settingsFace.isHidden = true
        settingsFace.translatesAutoresizingMaskIntoConstraints = false
        addSubview(settingsFace)

        NSLayoutConstraint.activate([
            settingsFace.leadingAnchor.constraint(equalTo: leadingAnchor),
            settingsFace.trailingAnchor.constraint(equalTo: trailingAnchor),
            settingsFace.topAnchor.constraint(equalTo: topAnchor),
            settingsFace.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        let titleLabel = PassthroughLabel(labelWithString: "Settings")
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .white

        let blurLabel = PassthroughLabel(labelWithString: "Background color")
        blurLabel.font = .systemFont(ofSize: 12, weight: .regular)
        blurLabel.textColor = .white.withAlphaComponent(0.85)

        blurredBackgroundSwitch.target = self
        blurredBackgroundSwitch.action = #selector(blurredBackgroundToggled)

        let toggleRow = NSStackView(views: [blurLabel, blurredBackgroundSwitch])
        toggleRow.orientation = .horizontal
        toggleRow.spacing = 8

        // A plain title has no readable color of its own against this
        // card's dark background — `attributedTitle` sets one directly,
        // rather than relying on `contentTintColor`, which only reliably
        // tints template images, not title text.
        settingsDoneButton.attributedTitle = NSAttributedString(
            string: "Done",
            attributes: [.foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 12, weight: .semibold)]
        )
        settingsDoneButton.isBordered = false
        settingsDoneButton.wantsLayer = true
        settingsDoneButton.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.15).cgColor
        settingsDoneButton.layer?.cornerRadius = 8
        settingsDoneButton.target = self
        settingsDoneButton.action = #selector(settingsDoneTapped)
        settingsDoneButton.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [titleLabel, toggleRow, settingsDoneButton])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        settingsFace.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: settingsFace.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: settingsFace.centerYAnchor),
            settingsDoneButton.widthAnchor.constraint(equalToConstant: 64),
            settingsDoneButton.heightAnchor.constraint(equalToConstant: 26),
        ])
    }

    /// Compact Layout's own transport row — mute, shuffle, previous, play/
    /// pause, next, repeat, share — the same elements as Full Layout's own
    /// `fullControlsOverlay` row, in a second instance sharing every one
    /// of their action handlers (only one layout's own row is ever visible
    /// at once). A `compactFace` subview, for the same reason
    /// `compactChromeBar` is — see that method's own doc comment.
    private func configureCompactTransportRow() {
        // `compactTransportRow` has no leading/trailing relationship to
        // `compactFace` at all — only `centerX`/`bottom` below, deliberately
        // mirroring `fullControlsOverlay`'s own relationship to its
        // artwork square exactly. A `<=`/`>=` width cap here was tried and
        // confirmed live to *not* prevent window growth: it's just as
        // satisfiable by growing `compactFace` (and so the window) as by
        // shrinking `row`, and the solver sometimes picked the former.
        // With no width relationship to cap at all, `row`'s own content
        // can only ever affect its own rendering (clipped by `self`'s own
        // `masksToBounds` if it overflows), never the window's actual
        // frame — the same reason Full Layout's row never has this
        // problem despite having no cap of its own either.
        let row = configureTransportRow(
            muteButton: compactMuteButton,
            volumeSlider: volumeSlider,
            previousButton: compactPreviousButton,
            playPauseButton: playPauseButton,
            shuffleButton: compactShuffleButton,
            repeatButton: compactRepeatButton,
            shareButton: compactShareButton
        )

        compactTransportRow.translatesAutoresizingMaskIntoConstraints = false
        compactTransportRow.alphaValue = 0
        compactTransportRow.addSubview(row)
        compactFace.addSubview(compactTransportRow)

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: compactTransportRow.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: compactTransportRow.trailingAnchor),
            row.topAnchor.constraint(equalTo: compactTransportRow.topAnchor),
            row.bottomAnchor.constraint(equalTo: compactTransportRow.bottomAnchor),
        ])

        // See `compactTransportRowStackedConstraints`'s own doc comment
        // for why a very short Overlay needs the alternate, inline
        // position instead.
        compactTransportRowStackedConstraints = [
            compactTransportRow.centerXAnchor.constraint(equalTo: compactFace.centerXAnchor),
            compactTransportRow.bottomAnchor.constraint(equalTo: compactFace.bottomAnchor, constant: -8),
        ]
        compactTransportRowInlineConstraints = [
            compactTransportRow.trailingAnchor.constraint(equalTo: compactFace.trailingAnchor, constant: -16),
            compactTransportRow.centerYAnchor.constraint(equalTo: compactThumbnailTextRow.centerYAnchor),
            // `compactThumbnailTextRow`'s own existing trailing cap (in
            // `configureCompactFace`) only truncates before reaching
            // `lyricsButton` — narrower than `compactTransportRow` (play
            // and next together) now sitting in roughly that same trailing
            // area here. Without this, a long title could truncate
            // assuming only the narrower (and, this short, already-hidden)
            // lyrics icon needs avoiding, and still overlap the wider row
            // that's actually visible here.
            compactThumbnailTextRow.trailingAnchor.constraint(lessThanOrEqualTo: compactTransportRow.leadingAnchor, constant: -8),
        ]
        NSLayoutConstraint.activate(compactTransportRowStackedConstraints)
    }

    private func transportButton(symbolName: String, action: Selector) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) ?? NSImage(), target: self, action: action)
        styleTransportButton(button)
        return button
    }

    private func styleTransportButton(_ button: NSButton) {
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.contentTintColor = .white
    }

    private func styleSlider(_ slider: NSSlider, min: Double, max: Double) {
        slider.minValue = min
        slider.maxValue = max
        slider.isContinuous = true
    }

    @objc private func playPauseTapped() {
        onTogglePlayPause?()
    }

    @objc private func previousTapped() {
        onSkipToPrevious?()
    }

    @objc private func nextTapped() {
        onSkipToNext?()
    }

    @objc private func lyricsTapped() {
        onToggleLyrics?()
    }

    @objc private func shuffleTapped() {
        onToggleShuffle?()
    }

    @objc private func repeatTapped() {
        onToggleRepeat?()
    }

    @objc private func shareTapped() {
        onShare?()
    }

    /// Opens the settings panel, remembering whether Lyrics or Now Playing
    /// content was on screen so Done can return to it specifically.
    @objc private func settingsTapped() {
        wasShowingLyricsBeforeSettings = !lyricsFace.isHidden
        let current = wasShowingLyricsBeforeSettings ? lyricsFace : activeNowPlayingFace
        crossfade(from: current, to: settingsFace)
        resizeHandleImageView.isHidden = true
    }

    /// Returns to Lyrics or Now Playing content, matching whichever was
    /// showing before Settings was opened — `activeNowPlayingFace` is
    /// re-read fresh here, not a value captured back at `settingsTapped()`,
    /// so a resize that happened while Settings was open (see
    /// `wasShowingLyricsBeforeSettings`'s own comment) can never leave this
    /// returning to the wrong layout's face.
    @objc private func settingsDoneTapped() {
        let destination = wasShowingLyricsBeforeSettings ? lyricsFace : activeNowPlayingFace
        crossfade(from: settingsFace, to: destination)
        resizeHandleImageView.isHidden = false
    }

    @objc private func blurredBackgroundToggled(_ sender: NSSwitch) {
        onToggleBlurredBackground?(sender.state == .on)
    }

    @objc private func seekSliderChanged(_ sender: NSSlider) {
        isDraggingSeek = !isFinalSliderEvent
        guard isFinalSliderEvent else { return }
        onSeek?(sender.doubleValue)
    }

    /// Shared by Compact Layout's `volumeSlider` and Full Layout's
    /// `fullVolumeSlider` — only one is ever on screen at once, so this one
    /// handler keeps both in sync regardless of which was actually
    /// dragged, and updates the mute icon to match wherever the drag
    /// landed.
    @objc private func volumeSliderChanged(_ sender: NSSlider) {
        isDraggingVolume = !isFinalSliderEvent
        guard isFinalSliderEvent else { return }

        let value = Int(sender.doubleValue)
        applyVolume(value)

        onVolumeChange?(value)
    }

    /// Toggles mute instantly: silences to zero, remembering the volume to
    /// restore, or restores whatever that was — applied optimistically to
    /// both volume sliders and the mute icon itself rather than waiting on
    /// any round trip, since nothing here polls Spotify's volume
    /// continuously the way playback state does (only a one-time fetch at
    /// startup — see `OverlayController`'s own use of `updateVolume(_:)`).
    @objc private func muteTapped() {
        let newVolume = isMuted ? lastNonZeroVolume : 0
        applyVolume(newVolume)

        onVolumeChange?(newVolume)
    }

    /// False for the mouse-down and every drag tick, true for whatever ends
    /// the gesture (mouse-up) — the commit-on-release gate both sliders
    /// share, so dragging never fires a live command per pixel crossed.
    private var isFinalSliderEvent: Bool {
        switch window?.currentEvent?.type {
        case .leftMouseDown, .leftMouseDragged: false
        default: true
        }
    }
}
