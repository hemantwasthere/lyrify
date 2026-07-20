import Foundation
import Testing

@testable import LyrifyCore

/// DisplaySelection's one decision, made pure: given the listener's
/// remembered display and what's currently attached, which display actually
/// carries the Overlay — without ever forgetting the remembered choice.
@Suite("Display selection")
struct DisplaySelectionTests {
    private let mainDisplay: UInt32 = 1
    private let external: UInt32 = 2

    @Test("no remembered choice resolves to the main display")
    func noRememberedChoice() {
        let resolved = DisplaySelection.resolve(
            remembered: nil,
            attached: [mainDisplay, external],
            mainDisplay: mainDisplay
        )

        #expect(resolved == mainDisplay)
    }

    @Test("a remembered choice that is attached is used")
    func rememberedAndAttached() {
        let resolved = DisplaySelection.resolve(
            remembered: external,
            attached: [mainDisplay, external],
            mainDisplay: mainDisplay
        )

        #expect(resolved == external)
    }

    /// A vanished display falls back to main, but the preference itself is
    /// this function's caller's to keep — this seam only ever answers which
    /// display to use right now.
    @Test("a remembered choice that is not attached falls back to the main display")
    func rememberedButUnattached() {
        let resolved = DisplaySelection.resolve(
            remembered: external,
            attached: [mainDisplay],
            mainDisplay: mainDisplay
        )

        #expect(resolved == mainDisplay)
    }

    @Test("a remembered choice equal to the main display is used")
    func rememberedIsMain() {
        let resolved = DisplaySelection.resolve(
            remembered: mainDisplay,
            attached: [mainDisplay, external],
            mainDisplay: mainDisplay
        )

        #expect(resolved == mainDisplay)
    }
}
