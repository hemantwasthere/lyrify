import CoreGraphics
import Foundation
import Testing

@testable import LyrifyCore

/// Given the Overlay's current size, resolves Compact Layout (a small
/// thumbnail-and-text bar) or Full Layout (Spotify Mini Player–style
/// artwork, seek bar, and chrome) — and, for Full Layout, the Lyrics
/// Face's line count and font size for that height. Directly modelled on
/// the retired `LyricsViewScaleTests` for the height-scaling shapes, and
/// on `OverlayOriginTests` for the boundary-decision shapes.
@Suite("Overlay layout")
struct OverlayLayoutTests {
    /// An arbitrary, unvarying width — every scenario here turns on height
    /// alone.
    private let width: CGFloat = 220

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

    @Test("below the threshold height resolves Compact Layout")
    func belowThreshold() {
        let size = CGSize(width: width, height: OverlayLayout.thresholdHeight - 1)

        #expect(OverlayLayout.resolve(size: size) == .compact)
    }

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
