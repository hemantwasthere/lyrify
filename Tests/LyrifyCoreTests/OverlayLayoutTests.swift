import CoreGraphics
import Foundation
import Testing

@testable import LyrifyCore

/// Given the Overlay's current size, resolves Compact Layout (a small
/// thumbnail-and-text bar, itself resolving which individual controls are
/// currently visible via `OverlayLayout.Breakpoint`) or Full Layout
/// (Spotify Mini Player–style artwork, seek bar, and chrome) — and, for
/// Full Layout, the Lyrics Face's line count and font size for that
/// height. Directly modelled on the retired `LyricsViewScaleTests` for the
/// height-scaling shapes, and on `OverlayOriginTests` for the
/// boundary-decision shapes.
@Suite("Overlay layout")
struct OverlayLayoutTests {
    /// An arbitrary, unvarying width — every Full Layout scenario here
    /// turns on height alone.
    private let width: CGFloat = 220

    /// A height comfortably above every height-gated Breakpoint's
    /// `reappearAt` (`hideButton`/`dragHandle`/`lyricsButton`'s floor, all
    /// 60), so Compact-tier width scenarios aren't accidentally gated by
    /// height too.
    private let ordinaryHeight: CGFloat = 200

    /// Resolves `height` and unwraps the Full Layout case, failing the
    /// test if Compact was resolved instead — every scenario below this
    /// point expects Full.
    private func resolveFull(height: CGFloat, sourceLocation: SourceLocation = #_sourceLocation) -> OverlayLayout.LyricsScale? {
        guard case .full(let scale) = OverlayLayout.resolve(size: CGSize(width: width, height: height)) else {
            Issue.record("expected Full Layout", sourceLocation: sourceLocation)
            return nil
        }
        return scale
    }

    /// Resolves `width`/`height` and unwraps Compact Layout's visible
    /// control set, failing the test if Full was resolved instead —
    /// mirrors `resolveFull(height:)` for the Compact scenarios below.
    private func resolveCompact(
        width: CGFloat,
        height: CGFloat,
        previousControls: Set<OverlayLayout.CompactControl>? = nil,
        sourceLocation: SourceLocation = #_sourceLocation
    ) -> Set<OverlayLayout.CompactControl>? {
        guard case .compact(let controls) = OverlayLayout.resolve(
            size: CGSize(width: width, height: height),
            previousControls: previousControls
        ) else {
            Issue.record("expected Compact Layout", sourceLocation: sourceLocation)
            return nil
        }
        return controls
    }

    // MARK: - Per-control Breakpoints

    @Test("a control that's currently visible stays visible above its hide threshold")
    func staysVisibleAboveHideThreshold() {
        let breakpoint = OverlayLayout.breakpoints.first { $0.control == .shareButton && $0.axis == .width }!
        let controls = resolveCompact(
            width: breakpoint.hideBelow,
            height: ordinaryHeight,
            previousControls: [.shareButton]
        )
        #expect(controls?.contains(.shareButton) == true)
    }

    @Test("a control that's currently visible hides once the size crosses below its hide threshold")
    func hidesBelowHideThreshold() {
        let breakpoint = OverlayLayout.breakpoints.first { $0.control == .shareButton && $0.axis == .width }!
        let controls = resolveCompact(
            width: breakpoint.hideBelow - 1,
            height: ordinaryHeight,
            previousControls: [.shareButton]
        )
        #expect(controls?.contains(.shareButton) == false)
    }

    @Test("a control that's currently hidden stays hidden inside its hysteresis gap")
    func staysHiddenInsideHysteresisGap() {
        let breakpoint = OverlayLayout.breakpoints.first { $0.control == .shareButton && $0.axis == .width }!
        let midpoint = (breakpoint.hideBelow + breakpoint.reappearAt) / 2
        let controls = resolveCompact(
            width: midpoint,
            height: ordinaryHeight,
            previousControls: []
        )
        #expect(controls?.contains(.shareButton) == false)
    }

    @Test("a control that's currently hidden reappears once the size clears its reappear threshold")
    func reappearsAtReappearThreshold() {
        let breakpoint = OverlayLayout.breakpoints.first { $0.control == .shareButton && $0.axis == .width }!
        let controls = resolveCompact(
            width: breakpoint.reappearAt,
            height: ordinaryHeight,
            previousControls: []
        )
        #expect(controls?.contains(.shareButton) == true)
    }

    @Test("with no prior resolution, a control resolves visible using its hide threshold directly")
    func noPriorResolutionUsesHideThreshold() {
        let breakpoint = OverlayLayout.breakpoints.first { $0.control == .shareButton && $0.axis == .width }!
        let controls = resolveCompact(width: breakpoint.hideBelow, height: ordinaryHeight, previousControls: nil)
        #expect(controls?.contains(.shareButton) == true)
    }

    @Test("the lyrics button hides below its own independent height floor, even at a generous width")
    func lyricsButtonHeightFloor() {
        let floor = OverlayLayout.breakpoints.first { $0.control == .lyricsButton && $0.axis == .height }!
        let controls = resolveCompact(width: 1_000, height: floor.hideBelow - 1, previousControls: [.lyricsButton])
        #expect(controls?.contains(.lyricsButton) == false)
    }

    @Test("hideButton and dragHandle are gated on height alone, regardless of width")
    func hideButtonAndDragHandleGatedOnHeight() {
        let hideButtonFloor = OverlayLayout.breakpoints.first { $0.control == .hideButton }!
        let controls = resolveCompact(
            width: 1_000,
            height: hideButtonFloor.hideBelow - 1,
            previousControls: [.hideButton, .dragHandle]
        )
        #expect(controls?.contains(.hideButton) == false)
        #expect(controls?.contains(.dragHandle) == false)
    }

    @Test("at a generous width and height, every control is visible")
    func everyControlVisibleAtGenerousSize() {
        let controls = resolveCompact(width: 320, height: ordinaryHeight, previousControls: Set(OverlayLayout.CompactControl.allCases))
        for control in OverlayLayout.CompactControl.allCases {
            #expect(controls?.contains(control) == true, "\(control) expected visible")
        }
    }

    @Test("at the smallest resizable size, no control remains visible")
    func noControlVisibleAtSmallestSize() {
        let controls = resolveCompact(width: 140, height: 48, previousControls: [])
        #expect(controls?.isEmpty == true)
    }

    @Test("extreme sizes resolve to a defined, empty control set rather than crashing or falling through")
    func extremeSizes() {
        #expect(resolveCompact(width: 0, height: 0, previousControls: [])?.isEmpty == true)
        #expect(resolveCompact(width: -100, height: -100, previousControls: [])?.isEmpty == true)
        #expect(resolveCompact(width: 1_000_000, height: ordinaryHeight, previousControls: Set(OverlayLayout.CompactControl.allCases))?.count == OverlayLayout.CompactControl.allCases.count)
    }

    @Test("threading previous state through a monotonically widening resize never loses a control")
    func monotonicWideningNeverLosesAControl() {
        var previousControls: Set<OverlayLayout.CompactControl>? = []
        var previousCount = 0

        for width in stride(from: CGFloat(140), through: 320, by: 4) {
            guard let controls = resolveCompact(width: width, height: ordinaryHeight, previousControls: previousControls) else { return }
            #expect(controls.count >= previousCount)
            previousCount = controls.count
            previousControls = controls
        }
    }

    // MARK: - Compact vs. Full

    @Test("height still gates Compact vs. Full independent of width")
    func heightGatesIndependentOfWidth() {
        let narrowAtThreshold = CGSize(width: 1, height: OverlayLayout.thresholdHeight)
        let wideBelowThreshold = CGSize(width: 100_000, height: OverlayLayout.thresholdHeight - 1)

        guard case .full = OverlayLayout.resolve(size: narrowAtThreshold) else {
            Issue.record("expected Full Layout for a narrow width at the threshold height")
            return
        }
        guard case .compact = OverlayLayout.resolve(size: wideBelowThreshold) else {
            Issue.record("expected Compact Layout for a wide width below the threshold height")
            return
        }
    }

    // MARK: - Full Layout / Lyrics scale

    @Test("exactly at the threshold height resolves Full Layout")
    func atThreshold() {
        #expect(resolveFull(height: OverlayLayout.thresholdHeight) != nil)
    }

    @Test("above the threshold height resolves Full Layout")
    func aboveThreshold() {
        #expect(resolveFull(height: OverlayLayout.thresholdHeight + 1) != nil)
    }

    @Test("the threshold height answers the base scale: minimum lines at the minimum font size")
    func minimumHeight() {
        guard let scale = resolveFull(height: OverlayLayout.thresholdHeight) else { return }

        #expect(scale.lineCount == OverlayLayout.minimumLineCount)
        #expect(scale.fontSize == OverlayLayout.minimumFontSize)
    }

    @Test("a taller height answers more lines at a larger font")
    func tallerHeight() {
        guard let base = resolveFull(height: OverlayLayout.thresholdHeight),
              let taller = resolveFull(height: OverlayLayout.thresholdHeight + 200)
        else { return }

        #expect(taller.lineCount > base.lineCount)
        #expect(taller.fontSize > base.fontSize)
    }

    @Test("line count and font size are both clamped at a maximum, however tall the Overlay grows")
    func clampedAtMaximum() {
        guard let scale = resolveFull(height: 100_000) else { return }

        #expect(scale.lineCount == OverlayLayout.maximumLineCount)
        #expect(scale.fontSize == OverlayLayout.maximumFontSize)
    }

    @Test("Full Layout's scale grows monotonically with height, never shrinking for a taller Overlay")
    func monotonic() {
        var previous: OverlayLayout.LyricsScale?

        for height in stride(
            from: OverlayLayout.thresholdHeight,
            through: OverlayLayout.thresholdHeight + 400,
            by: 20
        ) {
            guard let scale = resolveFull(height: height) else { return }

            if let previous {
                #expect(scale.lineCount >= previous.lineCount)
                #expect(scale.fontSize >= previous.fontSize)
            }
            previous = scale
        }
    }
}
