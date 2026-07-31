import Foundation

/// One line of Synced Lyrics together with the Playback Position at which it
/// begins. A Lyric Line has no recorded end — it remains current until the
/// next one begins.
///
/// An empty `text` is meaningful: it is how the source marks the start of an
/// Instrumental Gap, and the display treats it differently from words.
public struct LyricLine: Equatable, Sendable {
    public let text: String

    /// The Playback Position, in seconds, at which this line begins.
    public let start: TimeInterval

    public init(text: String, start: TimeInterval) {
        self.text = text
        self.start = start
    }

    /// Whether this is a Gap Marker — the empty-text line declaring an
    /// Instrumental Gap rather than carrying words.
    ///
    /// Named because it is a domain concept the display has to recognise
    /// wherever a Lyric Line turns up, not only when it happens to be the
    /// Active Line. Spelling it inline as `text.isEmpty` at one site is what
    /// let a marker sitting *beside* the Active Line render as a blank row.
    public var isGapMarker: Bool { text.isEmpty }
}
