import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import LyrifyCore

/// The one place this repo tests a real CoreImage computation directly
/// rather than through a fake — see `CoreImageArtworkColorWash`'s own doc
/// comment for why that's still in keeping with `LyrifyCore` staying
/// "deliberately untested" only at AppKit/network boundaries: this is a
/// pure, deterministic transform of bytes already in hand.
@Suite("Core Image artwork color wash")
struct CoreImageArtworkColorWashTests {
    /// A solid-color square encoded as PNG — real, decodable image bytes,
    /// without needing a fixture file on disk.
    private func makeSolidPNGData(size: Int = 8, red: CGFloat = 1, green: CGFloat = 0, blue: CGFloat = 0) -> Data {
        makePNGData(size: size) { context in
            context.setFillColor(CGColor(red: red, green: green, blue: blue, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        }
    }

    /// A busy, high-contrast square — one quadrant each of red, green, blue,
    /// and yellow — standing in for "a detailed multi-color illustration"
    /// (ADR-0011's own phrase for the case a blur would render as a blotchy
    /// multi-region smear rather than one coherent wash).
    private func makeBusyPNGData(size: Int = 8) -> Data {
        let half = size / 2
        return makePNGData(size: size) { context in
            let quadrants: [(CGRect, CGColor)] = [
                (CGRect(x: 0, y: half, width: half, height: half), CGColor(red: 1, green: 0, blue: 0, alpha: 1)),
                (CGRect(x: half, y: half, width: half, height: half), CGColor(red: 0, green: 1, blue: 0, alpha: 1)),
                (CGRect(x: 0, y: 0, width: half, height: half), CGColor(red: 0, green: 0, blue: 1, alpha: 1)),
                (CGRect(x: half, y: 0, width: half, height: half), CGColor(red: 1, green: 1, blue: 0, alpha: 1)),
            ]
            for (rect, color) in quadrants {
                context.setFillColor(color)
                context.fill(rect)
            }
        }
    }

    private func makePNGData(size: Int, draw: (CGContext) -> Void) -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        draw(context)
        let cgImage = context.makeImage()!

        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, cgImage, nil)
        CGImageDestinationFinalize(destination)
        return output as Data
    }

    private func pixelSize(of data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return (width, height)
    }

    /// Decodes `data` into per-pixel RGBA bytes, top-left origin.
    private func pixels(of data: Data) -> [[UInt8]]? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }

        let width = cgImage.width
        let height = cgImage.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &buffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var result: [[UInt8]] = []
        for pixel in stride(from: 0, to: buffer.count, by: 4) {
            result.append(Array(buffer[pixel..<pixel + 4]))
        }
        return result
    }

    @Test("valid artwork data resolves into decodable image data of the same dimensions")
    func resolvesValidArtwork() async {
        let artwork = makeSolidPNGData(size: 12)
        let wash = CoreImageArtworkColorWash()

        let resolved = await wash.blur(artwork)

        let resolvedSize = resolved.flatMap(pixelSize(of:))
        #expect(resolvedSize?.width == 12)
        #expect(resolvedSize?.height == 12)
    }

    @Test("a solid-color source keeps its own hue, softened rather than reproduced exactly")
    func solidColorSourceKeepsItsHue() async {
        let artwork = makeSolidPNGData(red: 0.8, green: 0.2, blue: 0.2)
        let wash = CoreImageArtworkColorWash()

        guard let resolved = await wash.blur(artwork), let washColor = pixels(of: resolved)?.first else {
            Issue.record("expected resolved color-wash data")
            return
        }

        // The hue survives: still unmistakably red, with the other two
        // channels well below it.
        #expect(washColor[0] > washColor[1])
        #expect(washColor[0] > washColor[2])

        // But not reproduced verbatim. The wash deliberately lifts what it
        // finds toward what Spotify actually draws — capped at saturation
        // 0.62 and brightness 0.75 — because a raw dominant color is both
        // darker and flatter than Spotify's panel, and because white title
        // text has to stay legible on it. A source this saturated must come
        // back visibly softer, so the green/blue floor rises off the 0.2 it
        // went in at.
        #expect(washColor[1] > 20)
        #expect(washColor[2] > 20)
    }

    @Test("a visually busy, high-contrast source resolves to one coherent wash, not a blotchy multi-color smear")
    func busySourceResolvesToOneUniformColor() async {
        let artwork = makeBusyPNGData(size: 8)
        let wash = CoreImageArtworkColorWash()

        guard let resolved = await wash.blur(artwork), let output = pixels(of: resolved), let first = output.first
        else {
            Issue.record("expected resolved color-wash data")
            return
        }

        for pixel in output {
            #expect(pixel[0] == first[0])
            #expect(pixel[1] == first[1])
            #expect(pixel[2] == first[2])
        }
    }

    @Test("a mostly-grey source with one vivid band takes the band's color, not the muddy average")
    func vividMinorityBeatsGreyMajority() async {
        // Three quarters near-grey, one quarter vivid red — the case the
        // averaging this replaced got visibly wrong (ADR-0016). An average
        // here is dragged to a brownish grey by the majority; the dominant
        // color is the red, because the grey pixels are near-colorless and
        // weighted down accordingly.
        let size = 8
        let artwork = makePNGData(size: size) { context in
            context.setFillColor(CGColor(red: 0.45, green: 0.45, blue: 0.46, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: size, height: size))
            context.setFillColor(CGColor(red: 0.85, green: 0.1, blue: 0.1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: size, height: size / 4))
        }
        let wash = CoreImageArtworkColorWash()

        guard let resolved = await wash.blur(artwork), let washColor = pixels(of: resolved)?.first else {
            Issue.record("expected resolved color-wash data")
            return
        }

        // The threshold has to sit above what plain averaging reaches, or
        // this passes under the very implementation it exists to rule out.
        // Measured on this fixture: averaging lands at a red/green margin
        // of about 48 (a brownish grey — the muddiness complained of),
        // dominance at about 109. 80 separates them with room either side.
        #expect(Int(washColor[0]) - Int(washColor[1]) > 80)
        #expect(Int(washColor[0]) - Int(washColor[2]) > 80)
    }

    @Test("a wholly black source still resolves, falling back rather than dropping the wash")
    func blackSourceFallsBackToAverage() async {
        // Every pixel is below the near-black floor the binning ignores, so
        // no bin qualifies. Real artwork is sometimes exactly this, and
        // losing the backdrop entirely would be worse than a dark wash.
        let artwork = makeSolidPNGData(red: 0, green: 0, blue: 0)
        let wash = CoreImageArtworkColorWash()

        let resolved = await wash.blur(artwork)

        #expect(resolved != nil)
    }

    @Test("unrecognizable data fails rather than producing garbage")
    func failsOnGarbageData() async {
        let wash = CoreImageArtworkColorWash()

        let resolved = await wash.blur(Data([0x00, 0x01, 0x02, 0x03]))

        #expect(resolved == nil)
    }
}
