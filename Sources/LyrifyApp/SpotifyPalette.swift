import AppKit

/// Spotify's own colour values, so every surface in the Overlay reads as one
/// system rather than each view inventing its own greys. Taken from Spotify's
/// design system and matched against its miniplayer: a near-black card, `#B3B3B3`
/// subdued text, and `#1ED760` for anything switched on.
///
/// Deliberately untested — a table of constants with no decision of its own.
enum SpotifyPalette {
    /// The card's background. Spotify's miniplayer is flat and near-black —
    /// it does not tint itself from the album art.
    static let base = NSColor(srgbRed: 0.05, green: 0.05, blue: 0.05, alpha: 1)

    static let textPrimary = NSColor.white
    static let textSubdued = NSColor(srgbRed: 0.70, green: 0.70, blue: 0.70, alpha: 1)

    /// Transport glyphs at rest. Brighter than `textSubdued`, which is right for
    /// text on black but disappears into album art — these sit over the artwork
    /// itself and have to hold up against a light cover.
    static let glyphRest = NSColor(srgbRed: 0.92, green: 0.92, blue: 0.92, alpha: 1)
    static let green = NSColor(srgbRed: 0.118, green: 0.843, blue: 0.376, alpha: 1)

    /// The unfilled part of a progress or volume bar — white at 30%, exactly
    /// what Spotify draws behind its own.
    static let barTrack = NSColor.white.withAlphaComponent(0.3)

    /// Darkens the album art while the transport controls sit on top of it, so
    /// white glyphs stay legible over bright artwork.
    static let scrim = NSColor.black.withAlphaComponent(0.55)

    /// The tint behind the art before any artwork is known — a neutral lift over
    /// `base`, so the gradient never disappears entirely between Tracks.
    static let fallbackAccent = NSColor(srgbRed: 0.28, green: 0.28, blue: 0.29, alpha: 1)

    /// The same colour with its hue removed. Spotify's "Background color" switch
    /// does not black the panel out — turning it off leaves the identical wash in
    /// neutral grey, which is what it measures as with the switch down.
    static func desaturated(_ color: NSColor) -> NSColor {
        guard let srgb = color.usingColorSpace(.sRGB) else { return color }
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        srgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return NSColor(hue: hue, saturation: 0, brightness: brightness, alpha: 1)
    }

    /// The colour Spotify tints the panel behind the cover with: the artwork's
    /// dominant colour, softened enough to put white text on.
    ///
    /// Averaging the whole image to a single pixel — the obvious approach, and
    /// the one this used to take — is the wrong measure. Averaging mixes every
    /// colour in the cover into one muddy brown-grey, which is why a vivid red
    /// sleeve came out the same dull shade as a photograph. What is wanted is the
    /// colour that *dominates*, so the pixels are binned by hue and the busiest
    /// bin wins, with saturated bins weighted up so a small band of strong colour
    /// beats a large expanse of near-grey.
    static func accent(from image: NSImage) -> NSColor {
        guard let dominant = dominant(of: image),
              let srgb = dominant.usingColorSpace(.sRGB)
        else { return fallbackAccent }

        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        srgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        // Calibrated by sampling both panels side by side with playback paused,
        // so the same cover is under each: Spotify lands near saturation 0.45 and
        // brightness 0.75. Binning finds the hue but returns it darker and a
        // little flatter than Spotify draws it, since the winning bin's mean
        // pulls in its duller members, so both are lifted to meet it.
        return NSColor(
            hue: hue,
            saturation: min(saturation * 1.15, 0.62),
            brightness: min(max(brightness * 1.25, 0.32), 0.75),
            alpha: 1
        )
    }

    /// Bins the artwork's pixels and returns the mean colour of the heaviest bin.
    private static func dominant(of image: NSImage) -> NSColor? {
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

                // A strongly coloured pixel counts for more than a washed-out one.
                let weight = 0.35 + saturation
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
