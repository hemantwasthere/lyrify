import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The production `ArtworkBlurring`: a flat wash of a single color sampled
/// from the artwork's *dominant* color, approximating Spotify Mini Player's
/// own backdrop (ADR-0011). Kept free of AppKit like the rest of
/// `LyrifyCore` (see `SyncedLyricsParser`'s own doc comment): CoreImage and
/// ImageIO are deterministic, offline compute frameworks, not a rendering
/// or system-I/O boundary, so this is tested directly rather than only
/// through a fake, the same as any other pure Core seam.
///
/// Supersedes an earlier Gaussian-blur-plus-saturation-boost implementation
/// (ADR-0009): a full set of Spotify reference screenshots showed no
/// blurred shapes at all, even behind visually busy source artwork — what
/// Spotify actually renders is a dominant/average color, not a smeared copy
/// of the image.
///
/// "Dominant", specifically, and not the whole-image average this used to
/// take (ADR-0016). Averaging mixes every color in the cover into one muddy
/// brown-grey, which is why a vivid red sleeve came out the same dull shade
/// as a photograph — the failure is worst on exactly the colorful artwork
/// the wash is meant to flatter. What is wanted is the color that
/// *dominates*, so pixels are binned and the busiest bin wins.
public struct CoreImageArtworkColorWash: ArtworkBlurring {
    public init() {}

    public func blur(_ artwork: Data) async -> Data? {
        Self.process(artwork)
    }

    /// The side length the artwork is reduced to before binning — a few
    /// hundred pixels is plenty to find a dominant color, and reading a
    /// few hundred thousand would not find a different one.
    private static let sampleSide = 40

    private static func process(_ data: Data) -> Data? {
        guard let source = CIImage(data: data) else { return nil }

        let context = CIContext()
        guard let dominant = dominantColor(of: source, context: context) else { return nil }

        guard let washFilter = CIFilter(name: "CIConstantColorGenerator") else { return nil }
        washFilter.setValue(dominant, forKey: kCIInputColorKey)
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

    /// Bins `source`'s pixels by color and returns the weighted mean of the
    /// heaviest bin, softened into something safe to put white text on.
    private static func dominantColor(of source: CIImage, context: CIContext) -> CIColor? {
        guard let pixels = downsampledPixels(of: source, context: context) else { return nil }

        struct Bin {
            var weight = 0.0
            var red = 0.0
            var green = 0.0
            var blue = 0.0
        }
        var bins: [Int: Bin] = [:]

        for pixel in stride(from: 0, to: pixels.count, by: 4) {
            let red = Double(pixels[pixel]) / 255
            let green = Double(pixels[pixel + 1]) / 255
            let blue = Double(pixels[pixel + 2]) / 255
            let (hue, saturation, brightness) = hsb(red: red, green: green, blue: blue)

            // Near-black and blown-out pixels say nothing about the
            // artwork's color; letting them vote is what pulls the result
            // toward grey.
            guard brightness > 0.12, brightness < 0.96 else { continue }

            // Hue matters most, so it gets the finest bins; a coarse
            // brightness split keeps a dark and a light red apart.
            let key = Int(hue * 24) * 10
                + Int(Swift.min(saturation, 0.999) * 3) * 3
                + Int(Swift.min(brightness, 0.999) * 3)

            // A strongly colored pixel counts for more than a washed-out
            // one, so a small band of vivid color beats a large expanse of
            // near-grey.
            let weight = 0.35 + saturation
            var bin = bins[key] ?? Bin()
            bin.weight += weight
            bin.red += red * weight
            bin.green += green * weight
            bin.blue += blue * weight
            bins[key] = bin
        }

        // Every pixel was near-black or blown out, so no bin qualified —
        // a wholly black or wholly white cover, which is real artwork and
        // common enough that dropping the wash for it would be worse than
        // falling back to the plain average this used to take. The average
        // of an unfiltered image always exists, so there is no third case.
        let winner: (red: Double, green: Double, blue: Double)
        if let best = bins.values.max(by: { $0.weight < $1.weight }), best.weight > 0 {
            winner = (best.red / best.weight, best.green / best.weight, best.blue / best.weight)
        } else {
            winner = average(of: pixels)
        }

        let (hue, saturation, brightness) = hsb(red: winner.red, green: winner.green, blue: winner.blue)

        // Calibrated by sampling both panels side by side with playback
        // paused, so the same cover is under each: Spotify lands near
        // saturation 0.45 and brightness 0.75. Binning finds the hue but
        // returns it darker and a little flatter than Spotify draws it,
        // since the winning bin's mean pulls in its duller members, so both
        // are lifted to meet it.
        let (red, green, blue) = rgb(
            hue: hue,
            saturation: Swift.min(saturation * 1.15, 0.62),
            brightness: Swift.min(Swift.max(brightness * 1.25, 0.32), 0.75)
        )
        return CIColor(red: red, green: green, blue: blue, alpha: 1)
    }

    /// The plain mean of every pixel, used only when binning finds nothing
    /// to bin.
    private static func average(of pixels: [UInt8]) -> (red: Double, green: Double, blue: Double) {
        var red = 0.0, green = 0.0, blue = 0.0
        let count = Double(pixels.count / 4)
        guard count > 0 else { return (0, 0, 0) }

        for pixel in stride(from: 0, to: pixels.count, by: 4) {
            red += Double(pixels[pixel])
            green += Double(pixels[pixel + 1])
            blue += Double(pixels[pixel + 2])
        }
        return (red / count / 255, green / count / 255, blue / count / 255)
    }

    /// Renders `source` down to `sampleSide` square and reads it back as
    /// RGBA8 bytes.
    private static func downsampledPixels(of source: CIImage, context: CIContext) -> [UInt8]? {
        let extent = source.extent
        guard extent.width > 0, extent.height > 0, extent.isInfinite == false else { return nil }

        let side = CGFloat(sampleSide)
        let scaled = source
            .transformed(by: CGAffineTransform(scaleX: side / extent.width, y: side / extent.height))
            .transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))

        var pixels = [UInt8](repeating: 0, count: sampleSide * sampleSide * 4)
        context.render(
            scaled,
            toBitmap: &pixels,
            rowBytes: sampleSide * 4,
            bounds: CGRect(x: 0, y: 0, width: side, height: side),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return pixels
    }

    /// Hue/saturation/brightness for an sRGB triple, hue normalized to
    /// 0..<1. Hand-rolled rather than taken from a color type, since
    /// `LyrifyCore` stays clear of AppKit and `CIColor` offers no such
    /// conversion.
    private static func hsb(red: Double, green: Double, blue: Double) -> (hue: Double, saturation: Double, brightness: Double) {
        let maximum = Swift.max(red, green, blue)
        let minimum = Swift.min(red, green, blue)
        let delta = maximum - minimum

        guard delta > 0, maximum > 0 else { return (0, 0, maximum) }

        let hue: Double
        switch maximum {
        case red: hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
        case green: hue = (blue - red) / delta + 2
        default: hue = (red - green) / delta + 4
        }
        return ((hue < 0 ? hue + 6 : hue) / 6, delta / maximum, maximum)
    }

    /// The inverse of `hsb(red:green:blue:)`.
    private static func rgb(hue: Double, saturation: Double, brightness: Double) -> (red: Double, green: Double, blue: Double) {
        guard saturation > 0 else { return (brightness, brightness, brightness) }

        let sector = (hue - hue.rounded(.down)) * 6
        let offset = sector - sector.rounded(.down)
        let p = brightness * (1 - saturation)
        let q = brightness * (1 - saturation * offset)
        let t = brightness * (1 - saturation * (1 - offset))

        switch Int(sector) {
        case 0: return (brightness, t, p)
        case 1: return (q, brightness, p)
        case 2: return (p, brightness, t)
        case 3: return (p, q, brightness)
        case 4: return (t, p, brightness)
        default: return (brightness, p, q)
        }
    }
}
