import CoreGraphics

/// Resolves which layout the Overlay's current size calls for — Compact
/// Layout (a thumbnail-and-text bar, itself further resolved into the set
/// of chrome/transport controls currently visible) below a size threshold,
/// Full Layout (Spotify Mini Player–style artwork, seek bar, and chrome) at
/// or above it — and, for Full Layout, how many Lyrics Face lines and what
/// font size that height affords.
///
/// Expands the retired `LyricsViewScale`: its old height-to-scale formula
/// reappears unchanged as Full Layout's own scaling, just anchored at a
/// new starting point rather than the old card's own minimum. That old
/// minimum (96pt) fit a lyrics-text-only view; Full Layout needs enough
/// room for a big square artwork area, an always-visible seek bar, a
/// transport row, and a top chrome bar besides — a taller, independent
/// minimum, tuned separately from the scaling curve it happens to share.
public enum OverlayLayout: Equatable, Sendable {
    case compact(Set<CompactControl>)
    case full(LyricsScale)

    /// One control in Compact Layout's chrome bar or transport row that can
    /// disappear as the Overlay narrows. Play/pause and next are
    /// deliberately absent — they're unconditionally visible at every
    /// Compact size, so they have no Breakpoint of their own. Replaces
    /// ADR-0010's `CompactTier`, which bundled several of these together
    /// into four named presets switched all at once (ADR-0013).
    public enum CompactControl: CaseIterable, Equatable, Sendable {
        case hideButton
        case dragHandle
        case settingsButton
        case muteButton
        case shuffleButton
        case previousButton
        case lyricsButton
        case repeatButton
        case shareButton

        /// Every control at once — the placeholder callers reach for
        /// before any real resolution has happened, since "nothing
        /// resolved yet" reads more honestly as "assume the richest
        /// state" than as "assume everything's hidden."
        public static let allVisible: Set<CompactControl> = Set(allCases)
    }

    public struct LyricsScale: Equatable, Sendable {
        public let lineCount: Int
        public let fontSize: CGFloat

        public init(lineCount: Int, fontSize: CGFloat) {
            self.lineCount = lineCount
            self.fontSize = fontSize
        }
    }

    /// The width or height below which one specific `CompactControl`
    /// disappears, and the (higher) width or height it must clear again to
    /// reappear — the hysteresis gap that keeps a control from flickering
    /// in and out if a resize is held exactly on its boundary. A control
    /// with more than one `Breakpoint` (`lyricsButton` has both a width one
    /// and its own independent height floor) is visible only while every
    /// one of its `Breakpoint`s says so.
    public struct Breakpoint: Equatable, Sendable {
        public enum Axis: Equatable, Sendable {
            case width
            case height
        }

        public let control: CompactControl
        public let axis: Axis
        public let hideBelow: CGFloat
        public let reappearAt: CGFloat

        public init(control: CompactControl, axis: Axis, hideBelow: CGFloat, reappearAt: CGFloat) {
            self.control = control
            self.axis = axis
            self.hideBelow = hideBelow
            self.reappearAt = reappearAt
        }

        fileprivate func dimension(of size: CGSize) -> CGFloat {
            axis == .width ? size.width : size.height
        }
    }

    /// Every `CompactControl`'s own Breakpoint(s). The width-axis entries
    /// are listed widest-to-narrowest by `hideBelow` — the order those
    /// controls disappear in as the Overlay narrows — followed by the
    /// height-axis entries (not comparable to a width threshold, so not
    /// part of that same ordering). Values are a starting point, not a
    /// locked design decision (ADR-0013): unlike `CompactTier`'s old
    /// boundaries, these aren't yet confirmed against Spotify's own Mini
    /// Player — expect them to move during that empirical pass.
    /// `hideButton` and `dragHandle` are gated on height alone (a chrome
    /// bar needs vertical room to show at all) regardless of width, even
    /// at widths beyond every other control's own Breakpoint; everything
    /// else is gated on width alone, except `lyricsButton`, which keeps
    /// its own independent height floor (the Lyrics Face floor) alongside
    /// its width Breakpoint.
    public static let breakpoints: [Breakpoint] = [
        Breakpoint(control: .shareButton, axis: .width, hideBelow: 272, reappearAt: 278),
        Breakpoint(control: .repeatButton, axis: .width, hideBelow: 256, reappearAt: 262),
        Breakpoint(control: .settingsButton, axis: .width, hideBelow: 240, reappearAt: 246),
        Breakpoint(control: .shuffleButton, axis: .width, hideBelow: 224, reappearAt: 230),
        Breakpoint(control: .muteButton, axis: .width, hideBelow: 208, reappearAt: 214),
        Breakpoint(control: .lyricsButton, axis: .width, hideBelow: 176, reappearAt: 182),
        Breakpoint(control: .previousButton, axis: .width, hideBelow: 160, reappearAt: 166),
        Breakpoint(control: .lyricsButton, axis: .height, hideBelow: 56, reappearAt: 60),
        Breakpoint(control: .hideButton, axis: .height, hideBelow: 56, reappearAt: 60),
        Breakpoint(control: .dragHandle, axis: .height, hideBelow: 56, reappearAt: 60),
    ]

    /// Below this height, Compact Layout; at or above it, Full Layout.
    /// Set high enough that Full Layout's own structural minimum — its
    /// square artwork area (which grows with the Overlay's width, up to
    /// `OverlayController.maximumSize.width`) plus its seek bar and
    /// title/artist chrome beneath it — always actually fits within any
    /// height Full Layout claims to support, at any width Full Layout is
    /// reachable at. Set too low relative to that width ceiling, and a
    /// resize down towards the boundary can get stuck: Full Layout's own
    /// required constraints can't be satisfied by a height that's
    /// nominally "Full Layout territory" but too short for what Full
    /// Layout structurally needs at the Overlay's current width. A tuning
    /// knob, not a locked design decision — but bumping
    /// `OverlayController.maximumSize.width` up means bumping this up
    /// too, not independently.
    public static let thresholdHeight: CGFloat = 420

    public static let minimumLineCount = 2
    public static let minimumFontSize: CGFloat = 15

    /// However tall the Overlay grows, line count and font size stop
    /// growing here — a Lyrics Face too crowded with lines stops being
    /// legible at a glance, which is the whole point of the Overlay.
    public static let maximumLineCount = 9
    public static let maximumFontSize: CGFloat = 32

    /// One additional line for every this many points of extra height
    /// above `thresholdHeight`.
    private static let pointsPerLine: CGFloat = 40

    /// Degrees of font growth per additional line — kept in step with
    /// line count so the two always change together.
    private static let fontSizeStepPerLine: CGFloat = 1.5

    /// `previousControls` is the set of controls visible the last time
    /// this was resolved — each `Breakpoint`'s hysteresis needs to know
    /// which of its two thresholds applies: a control that was visible
    /// must drop below `hideBelow` to disappear; one that was hidden must
    /// clear `reappearAt` to come back. `nil` means no prior resolution
    /// exists yet (the Overlay's very first layout pass) — every control
    /// is then judged directly against its own `hideBelow`, the same
    /// answer a fresh resolution with no history to bias it should give.
    public static func resolve(size: CGSize, previousControls: Set<CompactControl>? = nil) -> OverlayLayout {
        guard size.height >= thresholdHeight else {
            return .compact(resolveCompactControls(size: size, previousControls: previousControls))
        }
        return resolveFull(size: size)
    }

    private static func resolveCompactControls(size: CGSize, previousControls: Set<CompactControl>?) -> Set<CompactControl> {
        Set(CompactControl.allCases.filter { control in
            let wasVisible = previousControls?.contains(control) ?? true
            return breakpoints
                .filter { $0.control == control }
                .allSatisfy { breakpoint in
                    breakpoint.dimension(of: size) >= (wasVisible ? breakpoint.hideBelow : breakpoint.reappearAt)
                }
        })
    }

    private static func resolveFull(size: CGSize) -> OverlayLayout {
        let extraHeight = size.height - thresholdHeight
        let extraLines = Int(extraHeight / pointsPerLine)

        let lineCount = min(minimumLineCount + extraLines, maximumLineCount)
        let fontSize = min(minimumFontSize + CGFloat(extraLines) * fontSizeStepPerLine, maximumFontSize)

        return .full(LyricsScale(lineCount: lineCount, fontSize: fontSize))
    }
}
