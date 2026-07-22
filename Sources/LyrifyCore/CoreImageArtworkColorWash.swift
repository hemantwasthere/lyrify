import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The production `ArtworkBlurring`: a flat wash of a single color sampled
/// from the artwork's own average, approximating Spotify Mini Player's own
/// backdrop (ADR-0011). Kept free of AppKit like the rest of `LyrifyCore`
/// (see `SyncedLyricsParser`'s own doc comment): CoreImage and ImageIO are
/// deterministic, offline compute frameworks, not a rendering or system-I/O
/// boundary, so this is tested directly rather than only through a fake, the
/// same as any other pure Core seam.
///
/// Supersedes an earlier Gaussian-blur-plus-saturation-boost implementation
/// (ADR-0009): a full set of Spotify reference screenshots showed no
/// blurred shapes at all, even behind visually busy source artwork — what
/// Spotify actually renders is a dominant/average color, not a smeared copy
/// of the image.
public struct CoreImageArtworkColorWash: ArtworkBlurring {
    public init() {}

    public func blur(_ artwork: Data) async -> Data? {
        Self.process(artwork)
    }

    private static func process(_ data: Data) -> Data? {
        guard let source = CIImage(data: data) else { return nil }

        guard let averageFilter = CIFilter(name: "CIAreaAverage") else { return nil }
        averageFilter.setValue(source, forKey: kCIInputImageKey)
        averageFilter.setValue(CIVector(cgRect: source.extent), forKey: kCIInputExtentKey)
        guard let averageImage = averageFilter.outputImage else { return nil }

        let context = CIContext()

        // `CIAreaAverage`'s output is a 1x1-pixel image carrying the
        // average color — rendering it to a single RGBA8 pixel reads that
        // color out directly, without needing a full-size render pass.
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(
            averageImage,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        guard let washFilter = CIFilter(name: "CIConstantColorGenerator") else { return nil }
        let color = CIColor(
            red: CGFloat(pixel[0]) / 255,
            green: CGFloat(pixel[1]) / 255,
            blue: CGFloat(pixel[2]) / 255,
            alpha: 1
        )
        washFilter.setValue(color, forKey: kCIInputColorKey)
        guard let wash = washFilter.outputImage?.cropped(to: source.extent) else { return nil }

        guard let cgImage = context.createCGImage(wash, from: wash.extent) else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
