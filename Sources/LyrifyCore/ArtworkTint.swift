import Foundation

/// Maps a colour taken off album art to the colour a card can be tinted with.
///
/// The rule this encodes was measured, not guessed. Spotify's miniplayer was
/// sampled with its own "Background color" switch on, against three covers:
///
/// | cover | Spotify's card | relative luminance |
/// |---|---|---|
/// | vivid pink sleeve | rgb(102, 0, 17) | 0.029 |
/// | near-grey photograph | rgb(48, 54, 55) | 0.035 |
/// | very dark neon shot | rgb(21, 17, 16) | 0.006 |
///
/// The first two say the card is held to one darkness. The third says it isn't —
/// it is five times darker, and its sleeve is nearly black. So the rule is a
/// **ceiling**, not a target: art brighter than the ceiling is pulled down to it,
/// art already darker is left alone. Reading the first two alone gives a fixed
/// target, which is wrong in exactly the case that matters most — it *raises* a
/// dark cover's card, and a black sleeve would come out glowing.
///
/// What the ceiling is measured in matters as much as its value. Lyrify used to
/// cap HSB brightness at 0.75 and saturation at 0.62, which put the first two
/// covers at luminance 0.129 and 0.484 — four times and fourteen times too
/// bright, and nowhere near each other. A saturated red at brightness 0.4 is
/// dark, because two of its three channels are near zero; a grey at brightness
/// 0.4 is not. Brightness is the wrong axis to hold. Luminance is what the eye
/// reads, so that is what is capped, and brightness is solved for.
///
/// Saturation is pushed up on the way through. The binning that finds the hue
/// returns it flatter than it looks on the sleeve, because the winning bin's mean
/// pulls in its duller members, and Spotify's card is emphatically not pastel.
public enum ArtworkTint {
    /// The darkest the card is allowed to be, as relative luminance. The mean of
    /// the two measurements that were actually clipped by it.
    public static let luminanceCeiling = 0.032

    /// How much the extracted saturation is amplified before the solve. Fitted to
    /// the same two covers: their extracted saturations were 0.52 and 0.05, and
    /// Spotify rendered them at 1.00 and 0.13.
    public static let saturationGain = 2.5

    /// The tint for art whose dominant colour is `hue`/`saturation`/`brightness`,
    /// as sRGB components in 0...1.
    ///
    /// Hue survives untouched — it is the one thing the art is actually being
    /// asked for. Brightness is kept as the art gave it unless that puts the
    /// colour over the ceiling, in which case it is solved back down.
    public static func components(
        hue: Double,
        saturation: Double,
        brightness: Double
    ) -> (red: Double, green: Double, blue: Double) {
        let boosted = min(saturation * saturationGain, 1)
        let asGiven = rgb(hue: hue, saturation: boosted, brightness: brightness)

        guard relativeLuminance(red: asGiven.red, green: asGiven.green, blue: asGiven.blue) > luminanceCeiling
        else { return asGiven }

        return rgb(hue: hue, saturation: boosted, brightness: brightnessAtCeiling(hue: hue, saturation: boosted))
    }

    /// The brightness at which `hue`/`saturation` sits exactly on the ceiling.
    ///
    /// Solved by bisection rather than algebra. Luminance is a sum of three
    /// gamma-decoded channels, and while it is monotonic in brightness — which is
    /// all bisection needs — inverting it in closed form means inverting the sRGB
    /// transfer function through a weighted sum. Twenty halvings settle far below
    /// one part in 255, and this runs once per Track.
    public static func brightnessAtCeiling(hue: Double, saturation: Double) -> Double {
        var low = 0.0
        var high = 1.0
        for _ in 0..<20 {
            let mid = (low + high) / 2
            let c = rgb(hue: hue, saturation: saturation, brightness: mid)
            if relativeLuminance(red: c.red, green: c.green, blue: c.blue) < luminanceCeiling {
                low = mid
            } else {
                high = mid
            }
        }
        return (low + high) / 2
    }

    /// WCAG relative luminance — the weighted sum of gamma-decoded channels.
    public static func relativeLuminance(red: Double, green: Double, blue: Double) -> Double {
        func linear(_ value: Double) -> Double {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// HSB to RGB, written out rather than taken from AppKit so the whole mapping
    /// is pure and can be tested without a colour space or a screen.
    static func rgb(hue: Double, saturation: Double, brightness: Double) -> (red: Double, green: Double, blue: Double) {
        guard saturation > 0 else { return (brightness, brightness, brightness) }

        let sector = (hue - floor(hue)) * 6
        let offset = sector - floor(sector)
        let p = brightness * (1 - saturation)
        let q = brightness * (1 - saturation * offset)
        let t = brightness * (1 - saturation * (1 - offset))

        switch Int(sector) % 6 {
        case 0: return (brightness, t, p)
        case 1: return (q, brightness, p)
        case 2: return (p, brightness, t)
        case 3: return (p, q, brightness)
        case 4: return (t, p, brightness)
        default: return (brightness, p, q)
        }
    }
}
