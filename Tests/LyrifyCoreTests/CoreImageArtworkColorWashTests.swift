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

    @Test("a solid-color source resolves to that same color, not a desaturated or shifted one")
    func solidColorSourceResolvesToItsOwnColor() async {
        let artwork = makeSolidPNGData(red: 0.8, green: 0.2, blue: 0.2)
        let wash = CoreImageArtworkColorWash()

        // Compares against the source's own decoded pixel — not a
        // hand-computed 0.8/0.2/0.2-derived literal — since PNG encode/decode
        // alone (independent of any wash processing) already shifts raw
        // component values via color management.
        guard let sourceColor = pixels(of: artwork)?.first,
              let resolved = await wash.blur(artwork),
              let washColor = pixels(of: resolved)?.first
        else {
            Issue.record("expected resolved color-wash data")
            return
        }

        #expect(abs(Int(washColor[0]) - Int(sourceColor[0])) <= 2)
        #expect(abs(Int(washColor[1]) - Int(sourceColor[1])) <= 2)
        #expect(abs(Int(washColor[2]) - Int(sourceColor[2])) <= 2)
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

    @Test("a busy source's wash color sits strictly between its quadrants' extremes, not an arbitrary sampled pixel")
    func busySourceResolvesToItsTrueAverage() async {
        let artwork = makeBusyPNGData(size: 8)
        let wash = CoreImageArtworkColorWash()

        guard let resolved = await wash.blur(artwork), let washColor = pixels(of: resolved)?.first else {
            Issue.record("expected resolved color-wash data")
            return
        }

        // Every quadrant color here (red/green/blue/yellow) is pure 0s and
        // 1s per channel, and every channel has both a 0-quadrant and a
        // 1-quadrant among them. Comparing against one hand-computed
        // "expected average" pixel isn't reliable — CoreImage's own
        // color-managed averaging doesn't numerically match a same-value
        // solid swatch pushed through a *different* encode path (CGContext
        // vs. CIContext each apply their own color management, verified
        // empirically to diverge). But *any* true multi-pixel average of
        // these quadrants must land strictly inside (0, 255) on every
        // channel, however CoreImage's internal color management encodes
        // it — a monotonic transform still sends a strictly-interior value
        // to a strictly-interior value. A wash that constant-filled from
        // one arbitrary sampled pixel would instead land on an exact 0 or
        // 255 in at least one channel, since every quadrant is pure at the
        // channel level.
        #expect(washColor[0] > 0 && washColor[0] < 255)
        #expect(washColor[1] > 0 && washColor[1] < 255)
        #expect(washColor[2] > 0 && washColor[2] < 255)
    }

    @Test("unrecognizable data fails rather than producing garbage")
    func failsOnGarbageData() async {
        let wash = CoreImageArtworkColorWash()

        let resolved = await wash.blur(Data([0x00, 0x01, 0x02, 0x03]))

        #expect(resolved == nil)
    }
}
