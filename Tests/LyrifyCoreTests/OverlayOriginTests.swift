import CoreGraphics
import Foundation
import Testing

@testable import LyrifyCore

/// A screen or display change between launches can silently invalidate a
/// remembered Overlay position — this is the seam that decides whether to
/// trust it or fall back, so the Overlay can never be stranded off every
/// currently attached screen with no way back except clearing preferences
/// by hand.
@Suite("Overlay origin")
struct OverlayOriginTests {
    private let size = CGSize(width: 56, height: 56)
    private let mainScreen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let fallback = CGPoint(x: 1000, y: 900)

    @Test("no remembered origin uses the fallback")
    func noRemembered() {
        let origin = OverlayOrigin.resolve(remembered: nil, size: size, screens: [mainScreen], fallback: fallback)

        #expect(origin == fallback)
    }

    @Test("a remembered origin still on screen is used as-is")
    func rememberedOnScreen() {
        let remembered = CGPoint(x: 100, y: 100)

        let origin = OverlayOrigin.resolve(remembered: remembered, size: size, screens: [mainScreen], fallback: fallback)

        #expect(origin == remembered)
    }

    /// The exact scenario that motivated this seam: a position saved with a
    /// different screen attached, now off every currently attached one.
    @Test("a remembered origin off every screen falls back")
    func rememberedOffScreen() {
        let remembered = CGPoint(x: 2382, y: -196)

        let origin = OverlayOrigin.resolve(remembered: remembered, size: size, screens: [mainScreen], fallback: fallback)

        #expect(origin == fallback)
    }

    @Test("on-screen for any one of several screens is enough")
    func onScreenForAnyScreen() {
        let secondScreen = CGRect(x: 1512, y: 0, width: 1512, height: 982)
        let remembered = CGPoint(x: 1600, y: 100)

        let origin = OverlayOrigin.resolve(
            remembered: remembered,
            size: size,
            screens: [mainScreen, secondScreen],
            fallback: fallback
        )

        #expect(origin == remembered)
    }

    @Test("a vanished second screen falls back even though the position used to be valid")
    func vanishedScreenFallsBack() {
        // Valid only when a second screen to the right of the main one
        // still exists.
        let remembered = CGPoint(x: 1600, y: 100)

        let origin = OverlayOrigin.resolve(remembered: remembered, size: size, screens: [mainScreen], fallback: fallback)

        #expect(origin == fallback)
    }

    @Test("empty screens (nothing currently attached) falls back")
    func noScreensAttached() {
        let origin = OverlayOrigin.resolve(remembered: CGPoint(x: 100, y: 100), size: size, screens: [], fallback: fallback)

        #expect(origin == fallback)
    }
}
