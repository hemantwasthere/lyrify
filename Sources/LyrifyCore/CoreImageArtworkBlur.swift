import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The production `ArtworkBlurring`: a strong Gaussian blur plus a
/// saturation boost, approximating Spotify Mini Player's own blurred
/// backdrop — a wash of the artwork's own color, not a muddy, plain smear.
/// Kept free of AppKit like the rest of `LyrifyCore` (see
/// `SyncedLyricsParser`'s own doc comment): CoreImage and ImageIO are
/// deterministic, offline compute frameworks, not a rendering or
/// system-I/O boundary, so this is tested directly rather than only through
/// a fake, the same as any other pure Core seam.
public struct CoreImageArtworkBlur: ArtworkBlurring {
    /// Wide enough to read as a soft color wash rather than a legible,
    /// merely-fuzzy copy of the artwork.
    private static let blurRadius: Double = 40

    /// Blurring alone tends to look muddy/desaturated next to the sharp
    /// copy in front of it; a boost keeps the backdrop feeling like the
    /// artwork's own color rather than a grayed-out version of it.
    private static let saturationBoost: Double = 1.3

    public init() {}

    public func blur(_ artwork: Data) async -> Data? {
        Self.process(artwork)
    }

    private static func process(_ data: Data) -> Data? {
        guard let source = CIImage(data: data) else { return nil }

        // Blurring a finite-extent image darkens/fades toward transparent
        // at its edges, since the filter has no real pixels beyond the
        // frame to sample. Clamping first extends the edge pixels outward
        // to infinity, so the blur has real color to sample everywhere,
        // and cropping back to the original extent afterwards discards the
        // (now-unneeded) infinite surround.
        guard let blurFilter = CIFilter(name: "CIGaussianBlur") else { return nil }
        blurFilter.setValue(source.clampedToExtent(), forKey: kCIInputImageKey)
        blurFilter.setValue(blurRadius, forKey: kCIInputRadiusKey)
        guard let blurred = blurFilter.outputImage else { return nil }

        guard let saturationFilter = CIFilter(name: "CIColorControls") else { return nil }
        saturationFilter.setValue(blurred, forKey: kCIInputImageKey)
        saturationFilter.setValue(saturationBoost, forKey: kCIInputSaturationKey)
        let vivid = saturationFilter.outputImage ?? blurred

        let cropped = vivid.cropped(to: source.extent)

        let context = CIContext()
        guard let cgImage = context.createCGImage(cropped, from: cropped.extent) else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
