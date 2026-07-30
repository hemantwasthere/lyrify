import Foundation
import Testing

@testable import LyrifyCore

/// The tint mapping, checked against what Spotify's own miniplayer measured at.
@Suite("Artwork tint")
struct ArtworkTintTests {
    private func luminance(_ c: (red: Double, green: Double, blue: Double)) -> Double {
        ArtworkTint.relativeLuminance(red: c.red, green: c.green, blue: c.blue)
    }

    /// Bright art of any hue lands at the same darkness. This is what capping HSB
    /// brightness could not do — two covers came out at 0.129 and 0.484 under the
    /// old rule.
    @Test("bright art of any hue is pulled down to the ceiling")
    func constantLuminance() {
        for hueDegrees in stride(from: 0, through: 350, by: 10) {
            for saturation in [0.0, 0.05, 0.2, 0.52, 0.8, 1.0] {
                let c = ArtworkTint.components(hue: Double(hueDegrees) / 360, saturation: saturation, brightness: 1)
                #expect(
                    abs(luminance(c) - ArtworkTint.luminanceCeiling) < 0.002,
                    "hue \(hueDegrees)° saturation \(saturation) landed at \(luminance(c))"
                )
            }
        }
    }

    /// Measured off Spotify: a vivid pink sleeve whose extracted saturation was
    /// 0.52 rendered as rgb(102, 0, 17) — hue 350°, fully saturated, and dark.
    @Test("a vivid cover reproduces Spotify's deep, saturated card")
    func vividCover() {
        let c = ArtworkTint.components(hue: 350.0 / 360, saturation: 0.52, brightness: 0.52)

        #expect(c.red > c.blue && c.blue > c.green, "the red hue must survive the solve")
        #expect(abs(c.red * 255 - 102) < 14)
        #expect(luminance(c) < 0.04)
    }

    /// The other measured cover: nearly grey, extracted saturation 0.05, which
    /// Spotify rendered as rgb(48, 54, 55) — dark, not the near-white wash the
    /// old brightness clamp produced.
    @Test("a near-grey cover stays dark rather than washing out")
    func nearGreyCover() {
        let c = ArtworkTint.components(hue: 188.0 / 360, saturation: 0.05, brightness: 0.59)

        #expect(c.red * 255 < 80, "a grey cover used to come out at 179")
        #expect(abs(luminance(c) - 0.032) < 0.002)
    }

    /// The measurement that turned the ceiling into a ceiling. Spotify drew this
    /// cover's card at rgb(21, 17, 16) — luminance 0.006, five times darker than
    /// the other two — because the sleeve itself is nearly black. A fixed target
    /// would *brighten* it to 0.032, and a black sleeve would come out glowing.
    @Test("art already darker than the ceiling is left alone")
    func darkCoverKeepsItsDarkness() {
        let c = ArtworkTint.components(hue: 20.0 / 360, saturation: 0.1, brightness: 0.09)

        #expect(luminance(c) < ArtworkTint.luminanceCeiling / 3)
        #expect(c.red * 255 < 30)
    }

    /// Saturation is amplified, and has to stop at fully saturated rather than
    /// wrapping or overshooting into a nonsense colour.
    @Test("saturation is boosted but clamps at fully saturated")
    func saturationClamps() {
        let boosted = ArtworkTint.components(hue: 0, saturation: 0.1, brightness: 1)
        let clamped = ArtworkTint.components(hue: 0, saturation: 0.9, brightness: 1)

        // 0.1 × 2.5 leaves some grey in it; 0.9 × 2.5 clamps, so green and blue
        // both bottom out.
        #expect(boosted.green > 0.001)
        #expect(clamped.green < 0.001 && clamped.blue < 0.001)
    }

    @Test("a fully desaturated hue is neutral grey at the target luminance")
    func grey() {
        let c = ArtworkTint.components(hue: 0.5, saturation: 0, brightness: 1)

        #expect(abs(c.red - c.green) < 0.0001 && abs(c.green - c.blue) < 0.0001)
        #expect(abs(luminance(c) - ArtworkTint.luminanceCeiling) < 0.002)
    }

    /// Bisection needs luminance to rise with brightness; if it ever didn't, the
    /// solve would converge on the wrong side and every tint would be off.
    @Test("luminance rises with brightness, which is what the solve assumes")
    func monotonic() {
        var previous = -1.0
        for step in 0...20 {
            let c = ArtworkTint.rgb(hue: 0.1, saturation: 0.6, brightness: Double(step) / 20)
            let l = luminance(c)
            #expect(l > previous)
            previous = l
        }
    }

    @Test("hue wraps rather than falling off the end of the sector table")
    func hueWraps() {
        let zero = ArtworkTint.components(hue: 0, saturation: 0.8, brightness: 1)
        let one = ArtworkTint.components(hue: 1, saturation: 0.8, brightness: 1)

        #expect(abs(zero.red - one.red) < 0.0001)
        #expect(abs(zero.green - one.green) < 0.0001)
        #expect(abs(zero.blue - one.blue) < 0.0001)
    }
}
