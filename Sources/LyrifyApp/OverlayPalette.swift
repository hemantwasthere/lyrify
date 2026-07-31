import AppKit
import LyrifyCore

/// The Overlay's colour values, so every surface in it reads as one system
/// rather than each view inventing its own greys.
///
/// The greys are still Spotify's, measured against its miniplayer — a near-black
/// card and `#B3B3B3` subdued text — because the Overlay is shaped after that
/// miniplayer and the values are simply the right ones. The accent is not:
/// anything switched on wears Lyrify's own colour, which is why this is named
/// for the Overlay rather than for Spotify.
///
/// Two different things here want the word "accent", so they are kept apart.
/// `accent` is the fixed brand colour marking a control as on. `tint(from:)`
/// and `fallbackTint` are the per-Track colour drawn behind the cover, which
/// the comments throughout have always called the tint.
///
/// Deliberately untested — a table of constants with no decision of its own.
enum OverlayPalette {
    /// The card's background: black, not near-black.
    ///
    /// The difference matters more than it looks. Spotify's card measures 0.00
    /// against the 0.06 this used to be, and that 0.06 was enough to make the
    /// strip above the artwork read as a distinct grey band — space visibly held
    /// open for the chrome. At true black the same strip reads as nothing at all,
    /// which is why Spotify's looks like it reserves no space despite reserving
    /// almost exactly as much.
    static let base = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)

    static let textPrimary = NSColor.white
    static let textSubdued = NSColor(srgbRed: 0.70, green: 0.70, blue: 0.70, alpha: 1)

    /// Transport glyphs at rest. Brighter than `textSubdued`, which is right for
    /// text on black but disappears into album art — these sit over the artwork
    /// itself and have to hold up against a light cover.
    static let glyphRest = NSColor(srgbRed: 0.92, green: 0.92, blue: 0.92, alpha: 1)
    /// Anything switched on. Lyrify's amber, not Spotify's `#1ED760`: the
    /// Overlay stopped being a look-alike, and shipping another company's brand
    /// colour inside a third-party app is a risk with nothing to gain.
    ///
    /// The brighter of the brand's two ambers. The darker one is tuned for the
    /// site's cream ground and goes muddy against this card's black, where the
    /// entire job of this colour is to read as "on" at a glance.
    static let accent = NSColor(srgbRed: 0.902, green: 0.639, blue: 0.224, alpha: 1)

    /// The unfilled part of a progress or volume bar — white at 30%, exactly
    /// what Spotify draws behind its own.
    static let barTrack = NSColor.white.withAlphaComponent(0.3)

    /// Darkens the album art while the transport controls sit on top of it, so
    /// white glyphs stay legible over bright artwork.
    static let scrim = NSColor.black.withAlphaComponent(0.55)

    /// The tint before any artwork is known — neutral, at the same darkness every
    /// tint is held to, so the card doesn't flash a different brightness between
    /// Tracks while the next cover is fetched.
    ///
    /// This measures rgb(50, 50, 50), which is all but exactly the rgb(53, 53, 53)
    /// Spotify's own card shows for a greyscale sleeve — the two agree because
    /// both are a hueless colour at the same luminance.
    static let fallbackTint = tinted(hue: 0, saturation: 0, brightness: 1)

    /// The colour Spotify tints its card with: the artwork's dominant hue, at a
    /// fixed dark luminance.
    ///
    /// Averaging the whole image to a single pixel — the obvious approach, and the
    /// one this used to take — is the wrong measure. Averaging mixes every colour
    /// in the cover into one muddy brown-grey, which is why a vivid red sleeve
    /// came out the same dull shade as a photograph. What is wanted is the colour
    /// that *dominates*, so the pixels are binned by hue and the busiest bin wins,
    /// with saturated bins weighted up so a small band of strong colour beats a
    /// large expanse of near-grey.
    ///
    /// The binning was already right. What was wrong is everything after it — see
    /// `ArtworkTint`, which holds the measurements and does the arithmetic.
    static func tint(
        from image: NSImage,
        ceiling: Double = ArtworkTint.luminanceCeiling,
        gain: Double = ArtworkTint.saturationGain,
        favourVivid: Bool = true,
        exact: Bool = false
    ) -> NSColor {
        guard let dominant = dominant(of: image, favourVivid: favourVivid),
              let srgb = dominant.usingColorSpace(.sRGB)
        else { return fallbackTint }

        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        srgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        return tinted(hue: hue, saturation: saturation, brightness: brightness, ceiling: ceiling, gain: gain, exact: exact)
    }

    private static func tinted(
        hue: CGFloat,
        saturation: CGFloat,
        brightness: CGFloat,
        ceiling: Double = ArtworkTint.luminanceCeiling,
        gain: Double = ArtworkTint.saturationGain,
        exact: Bool = false
    ) -> NSColor {
        let c = ArtworkTint.components(
            hue: Double(hue),
            saturation: Double(saturation),
            brightness: Double(brightness),
            ceiling: ceiling,
            gain: gain,
            exact: exact
        )
        return NSColor(srgbRed: CGFloat(c.red), green: CGFloat(c.green), blue: CGFloat(c.blue), alpha: 1)
    }

    /// The lighter wash the panel behind the cover keeps when "Background color"
    /// is *off* — the same hue, six times the luminance. See
    /// `ArtworkTint.panelLuminanceCeiling`.
    static func panelTint(from image: NSImage) -> NSColor {
        tint(
            from: image,
            ceiling: ArtworkTint.panelLuminanceCeiling,
            gain: ArtworkTint.panelSaturationGain,
            favourVivid: false,
            exact: true
        )
    }

    /// Bins the artwork's pixels and returns the mean colour of the heaviest bin.
    /// `favourVivid` decides which colour "dominant" means, and the two answers
    /// genuinely differ. On the *Babydoll* sleeve — a large beige field with a
    /// narrow yellow band across it — vivid picks the yellow and area picks the
    /// beige. Spotify uses the first for the card with the switch on and the
    /// second for the panel wash with it off, and measurably so: its off-state
    /// panel for that cover is rgb(137, 114, 115), the beige, where cubed
    /// saturation weighting gave rgb(129, 97, 25), the yellow.
    private static func dominant(of image: NSImage, favourVivid: Bool = true) -> NSColor? {
        guard let small = downsample(image, to: 40) else { return nil }

        struct Bin {
            var count = 0.0
            var r = 0.0, g = 0.0, b = 0.0
        }
        var bins: [Int: Bin] = [:]

        for y in 0..<small.pixelsHigh {
            for x in 0..<small.pixelsWide {
                guard let c = small.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
                c.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

                // Near-black and blown-out pixels say nothing about the artwork's
                // colour; letting them vote is what pulls the result toward grey.
                guard brightness > 0.12, brightness < 0.96 else { continue }

                // Hue matters most, so it gets the finest bins; a coarse
                // brightness split keeps a dark and a light red apart.
                let key = Int(hue * 24) * 10
                    + Int(min(saturation, 0.999) * 3) * 3
                    + Int(min(brightness, 0.999) * 3)

                // A strongly coloured pixel counts for more than a washed-out one
                // — and by a lot. This was `0.35 + saturation`, which is barely a
                // preference: it lets a grey pixel cast a third of a vote, so a
                // big washed-out background outvoted a small vivid subject three
                // pixels to one. Measured against Spotify on a cover with a green
                // subject on pale ground, Spotify drew rgb(0, 61, 0) where that
                // weighting gave a near-grey rgb(46, 50, 57).
                //
                // Cubed, a pixel at saturation 0.05 is worth 1/4000th of one at
                // 0.8, so an expanse of near-grey has to be enormous to win. On
                // genuinely greyscale art every weight is tiny but their ordering
                // is unchanged, so the busiest bin still wins and the answer is
                // still grey — the ceiling is what makes that look right.
                let weight = favourVivid
                    ? saturation * saturation * saturation + 0.0001
                    : 1
                var bin = bins[key] ?? Bin()
                bin.count += weight
                bin.r += c.redComponent * weight
                bin.g += c.greenComponent * weight
                bin.b += c.blueComponent * weight
                bins[key] = bin
            }
        }

        guard let best = bins.values.max(by: { $0.count < $1.count }), best.count > 0 else { return nil }
        return NSColor(
            srgbRed: best.r / best.count,
            green: best.g / best.count,
            blue: best.b / best.count,
            alpha: 1
        )
    }

    /// Redraws `image` small, so the binning above reads a few hundred pixels
    /// rather than a few hundred thousand.
    private static func downsample(_ image: NSImage, to side: Int) -> NSBitmapImageRep? {
        guard let tiff = image.tiffRepresentation,
              let source = NSBitmapImageRep(data: tiff),
              let target = NSBitmapImageRep(
                  bitmapDataPlanes: nil,
                  pixelsWide: side,
                  pixelsHigh: side,
                  bitsPerSample: 8,
                  samplesPerPixel: 4,
                  hasAlpha: true,
                  isPlanar: false,
                  colorSpaceName: .deviceRGB,
                  bytesPerRow: side * 4,
                  bitsPerPixel: 32
              )
        else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: target)
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        return target
    }
}
