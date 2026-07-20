import CoreGraphics
import Foundation
import Testing

@testable import LyrifyCore

/// Placement's one decision, made pure: given a display's reported top
/// safe-area inset and the safe margins either side of a notch, resolve
/// which form the Overlay takes. See ADR-0004 — the notch is a Placement,
/// not a premise.
@Suite("Placement")
struct PlacementTests {
    private let leftMargin = CGRect(x: 0, y: 0, width: 200, height: 24)
    private let rightMargin = CGRect(x: 600, y: 0, width: 200, height: 24)

    @Test("no top safe-area inset resolves to the pill, regardless of margins")
    func noInsetIsPill() {
        let placement = Placement.resolve(
            topSafeAreaInset: 0,
            leftMargin: leftMargin,
            rightMargin: rightMargin
        )

        #expect(placement == .pill)
    }

    @Test("a positive top safe-area inset resolves to the notch, carrying the margins")
    func positiveInsetIsNotch() {
        let placement = Placement.resolve(
            topSafeAreaInset: 32,
            leftMargin: leftMargin,
            rightMargin: rightMargin
        )

        #expect(placement == .notch(leftMargin: leftMargin, rightMargin: rightMargin))
    }

    /// Never reported by AppKit, but a defensive answer all the same: an
    /// inset can only ever mean "no notch" or "a notch," never a third form.
    @Test("a negative top safe-area inset resolves to the pill")
    func negativeInsetIsPill() {
        let placement = Placement.resolve(
            topSafeAreaInset: -1,
            leftMargin: leftMargin,
            rightMargin: rightMargin
        )

        #expect(placement == .pill)
    }
}
