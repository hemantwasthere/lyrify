import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import LyrifyCore

/// The one place this repo tests a real CoreImage computation directly
/// rather than through a fake — see `CoreImageArtworkBlur`'s own doc
/// comment for why that's still in keeping with `LyrifyCore` staying
/// "deliberately untested" only at AppKit/network boundaries: this is a
/// pure, deterministic transform of bytes already in hand.
@Suite("Core Image artwork blur")
struct CoreImageArtworkBlurTests {
    /// A tiny, solid-color square encoded as PNG — real, decodable image
    /// bytes, without needing a fixture file on disk.
    private func makePNGData(size: Int = 8, red: CGFloat = 1, green: CGFloat = 0, blue: CGFloat = 0) -> Data {
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
        context.setFillColor(CGColor(red: red, green: green, blue: blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
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

    @Test("valid artwork data blurs into decodable image data of the same dimensions")
    func blursValidArtwork() async {
        let artwork = makePNGData(size: 12)
        let blur = CoreImageArtworkBlur()

        let blurred = await blur.blur(artwork)

        let blurredSize = blurred.flatMap(pixelSize(of:))
        #expect(blurredSize?.width == 12)
        #expect(blurredSize?.height == 12)
    }

    @Test("unrecognizable data fails rather than producing garbage")
    func failsOnGarbageData() async {
        let blur = CoreImageArtworkBlur()

        let blurred = await blur.blur(Data([0x00, 0x01, 0x02, 0x03]))

        #expect(blurred == nil)
    }
}
