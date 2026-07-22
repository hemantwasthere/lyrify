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

    /// Resolves `width`/`height` and unwraps the Compact Layout tier,
    /// failing the test if Full was resolved instead — mirrors
    /// `resolveFull(height:)` for the Compact-tier scenarios below.
    private func resolveCompact(width: CGFloat, height: CGFloat, sourceLocation: SourceLocation = #_sourceLocation) -> OverlayLayout.CompactTier? {
        guard case .compact(let tier) = OverlayLayout.resolve(size: CGSize(width: width, height: height)) else {
            Issue.record("expected Compact Layout", sourceLocation: sourceLocation)
            return nil
        }
        return tier
    }

    @Test("at or above the full tier's minimum width resolves Compact Layout's full tier")
    func compactFullTier() {
        #expect(resolveCompact(width: OverlayLayout.fullTierMinimumWidth, height: OverlayLayout.thresholdHeight - 1) == .full)
    }

    @Test("just below the full tier's minimum width resolves the reduced tier")
    func compactReducedTier() {
        #expect(resolveCompact(width: OverlayLayout.fullTierMinimumWidth - 1, height: OverlayLayout.thresholdHeight - 1) == .reduced)
    }

    @Test("just below the reduced tier's minimum width, at an ordinary height, resolves the minimal tier")
    func compactMinimalTier() {
        #expect(resolveCompact(width: OverlayLayout.reducedTierMinimumWidth - 1, height: OverlayLayout.thresholdHeight - 1) == .minimal)
    }

    @Test("narrow and very short resolves the bare tier")
    func compactBareTier() {
        #expect(resolveCompact(width: OverlayLayout.reducedTierMinimumWidth - 1, height: OverlayLayout.minimalTierMinimumHeight - 1) == .bare)
    }

    @Test("exactly at the reduced tier's minimum width resolves the reduced tier, not the minimal tier")
    func reducedTierBoundary() {
        #expect(resolveCompact(width: OverlayLayout.reducedTierMinimumWidth, height: OverlayLayout.thresholdHeight - 1) == .reduced)
    }

    @Test("exactly at the minimal tier's minimum height resolves the minimal tier, not the bare tier")
    func minimalTierBoundary() {
        #expect(resolveCompact(width: OverlayLayout.reducedTierMinimumWidth - 1, height: OverlayLayout.minimalTierMinimumHeight) == .minimal)
    }

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

    @Test("Compact Layout's tier only ever gets richer as width grows, never poorer, for a fixed height")
    func compactTierMonotonic() {
        // A tier's index in this list is its "richness rank" — later is
        // richer. Independent of `OverlayLayout`'s own case order, so this
        // doesn't just restate the production code's own ordering.
        let richnessRank: [OverlayLayout.CompactTier] = [.bare, .minimal, .reduced, .full]
        var previousRank: Int?

        for width in stride(from: CGFloat(1), through: OverlayLayout.fullTierMinimumWidth + 40, by: 10) {
            let size = CGSize(width: width, height: OverlayLayout.thresholdHeight - 1)
            guard case .compact(let tier) = OverlayLayout.resolve(size: size) else {
                Issue.record("expected Compact Layout below the threshold height")
                return
            }
            guard let rank = richnessRank.firstIndex(of: tier) else {
                Issue.record("unranked tier \(tier)")
                return
            }

            if let previousRank {
                #expect(rank >= previousRank)
            }
            previousRank = rank
        }
    }

    @Test("extreme sizes resolve to a defined tier rather than crashing or falling through")
    func extremeSizes() {
        #expect(resolveCompact(width: 0, height: 0) == .bare)
        #expect(resolveCompact(width: -100, height: -100) == .bare)
        #expect(resolveCompact(width: 1_000_000, height: OverlayLayout.thresholdHeight - 1) == .full)
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
