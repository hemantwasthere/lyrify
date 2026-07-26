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

    /// The dominant colour of `image`, saturated and darkened into something
    /// safe to put white text on. Spotify's miniplayer tints the panel behind
    /// the cover this way, but never so brightly that the title stops reading.
    ///
    /// Averages the whole image down to a single pixel rather than clustering:
    /// the gradient only needs a plausible tint, and a 1×1 downsample is both
    /// instant and stable frame to frame.
    static func accent(from image: NSImage) -> NSColor {
        guard let average = averageColor(of: image),
              let srgb = average.usingColorSpace(.sRGB)
        else { return fallbackAccent }

        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        srgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        // Measured against Spotify's own panel: a dark green cover gives it a
        // near-neutral grey (R=G=B=0.28), a bright outdoor one a pale lavender.
        // So the tint is the artwork heavily *desaturated* and left roughly at
        // its own brightness — not pushed toward a saturated colour, which is
        // what made this card read as muddy brown where Spotify's reads as a
        // soft wash.
        return NSColor(
            hue: hue,
            saturation: min(saturation, 0.18),
            brightness: min(max(brightness * 1.1, 0.24), 0.68),
            alpha: 1
        )
    }

    private static func averageColor(of image: NSImage) -> NSColor? {
        guard let tiff = image.tiffRepresentation,
              let source = NSBitmapImageRep(data: tiff),
              let onePixel = NSBitmapImageRep(
                  bitmapDataPlanes: nil,
                  pixelsWide: 1,
                  pixelsHigh: 1,
                  bitsPerSample: 8,
                  samplesPerPixel: 4,
                  hasAlpha: true,
                  isPlanar: false,
                  colorSpaceName: .deviceRGB,
                  bytesPerRow: 4,
                  bitsPerPixel: 32
              )
        else { return nil }

        // Drawing the whole image into a single pixel lets the graphics system
        // do the averaging.
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: onePixel)
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(in: NSRect(x: 0, y: 0, width: 1, height: 1))
        NSGraphicsContext.restoreGraphicsState()

        return onePixel.colorAt(x: 0, y: 0)
    }
}
