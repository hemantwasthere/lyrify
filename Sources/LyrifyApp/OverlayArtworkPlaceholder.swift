import AppKit

/// The placeholder art shown before a Track's real artwork is known, or
/// when a confirmed no-artwork outcome comes back — shared by the Disc and
/// the Now Playing card so the two forms can't drift on what "no art yet"
/// looks like.
enum OverlayArtworkPlaceholder {
    static let tint = NSColor.white.withAlphaComponent(0.6)

    static func image(pointSize: CGFloat) -> NSImage? {
        NSImage(systemSymbolName: "music.note", accessibilityDescription: "Lyrify")?
            .withSymbolConfiguration(.init(pointSize: pointSize, weight: .regular))
    }
}
