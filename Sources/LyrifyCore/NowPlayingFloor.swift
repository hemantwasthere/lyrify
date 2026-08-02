import Foundation

/// What macOS says is playing, merged from the adapter's stream.
///
/// The Now Playing Floor is the single application macOS resolves as the owner
/// of media playback — the one the media keys and Control Center obey. Exactly
/// one application holds it, and a paused application keeps it, so an empty
/// Floor means nothing is playing anywhere rather than nothing being paused.
///
/// This is a *running snapshot*, not a parser, and that distinction is the
/// whole reason the type exists. The adapter's stream emits **diffs**: an event
/// carries only the keys that changed, so a reading of a video already underway
/// is followed by events consisting of nothing but an elapsed time. Treating
/// each event as a whole reading answers a Track with no title and no owner —
/// see `docs/findings/2026-08-02-now-playing-floor.md`, where that behaviour was
/// first observed.
///
/// Kept free of AppKit and of any subprocess, so every field shape the adapter
/// can emit is testable without a browser running.
public struct NowPlayingFloor: Equatable, Sendable {
    public enum ParseError: Error, Equatable {
        /// The line was not a JSON object or `null` — the adapter also writes
        /// diagnostics to its output, and those are not readings.
        case notAReading
        case invalidNumber(field: String)
    }

    private var bundleIdentifier: String?
    private var parentBundleIdentifier: String?
    private var title: String?
    private var artist: String?
    private var duration: TimeInterval?
    private var elapsedTime: TimeInterval?
    private var isPlaying = false

    public init() {}

    /// Which application currently holds the Floor, if any.
    ///
    /// Exposed because deciding *whose* playback this is belongs to whoever
    /// composes the Players, not here — this type only says what the Floor
    /// reports.
    public var holder: String? { bundleIdentifier }

    /// The application behind the publisher, where the publisher is a helper
    /// process. Absent in every reading observed so far; kept because the
    /// adapter documents it and consulting it costs nothing.
    public var holderParent: String? { parentBundleIdentifier }

    /// Merges one reading into the snapshot.
    ///
    /// Two shapes arrive here, and telling them apart is most of the work:
    ///
    /// - The stream wraps every reading in an envelope — `type`, `diff`,
    ///   `payload` — and says in `diff` whether the payload is the whole
    ///   picture or only what changed. A whole picture *replaces* the snapshot,
    ///   so a field that has gone away goes away; a diff is merged over it.
    /// - A one-shot reading arrives bare, with the fields at the top level, and
    ///   is always a whole picture.
    ///
    /// Nothing playing anywhere is said two ways depending on which shape it
    /// came in: a bare `null`, or an envelope whose payload has no keys at all.
    /// Both empty the snapshot, because otherwise a Track that stopped would
    /// linger on the Overlay.
    ///
    /// Within a diff, an explicit `null` is not "unchanged" — it is the
    /// adapter saying the key has vanished, and it clears the field.
    public mutating func merge(_ event: Data) throws {
        // `.fragmentsAllowed` because the one-shot "nothing is playing" answer
        // is a bare `null`, which is not a container and is otherwise rejected.
        let parsed = try? JSONSerialization.jsonObject(with: event, options: [.fragmentsAllowed])

        if parsed is NSNull {
            self = NowPlayingFloor()
            return
        }
        guard let object = parsed as? [String: Any] else {
            throw ParseError.notAReading
        }

        let fields: [String: Any]
        let isDiff: Bool
        if let payload = object["payload"] as? [String: Any] {
            fields = payload
            isDiff = object["diff"] as? Bool ?? false
        } else {
            fields = object
            isDiff = false
        }

        // A whole picture replaces rather than merges, so that anything it no
        // longer mentions is genuinely gone.
        if isDiff == false { self = NowPlayingFloor() }

        // Present-and-null clears; absent leaves alone. `as? String` on an
        // `NSNull` answers nil, which is exactly the clearing behaviour wanted.
        if let value = fields["bundleIdentifier"] { bundleIdentifier = value as? String }
        if let value = fields["parentApplicationBundleIdentifier"] {
            parentBundleIdentifier = value as? String
        }
        if let value = fields["title"] { title = value as? String }
        if let value = fields["artist"] { artist = value as? String }
        if let value = fields["playing"] { isPlaying = value as? Bool ?? false }
        if fields["duration"] != nil {
            duration = try number(fields["duration"], field: "duration")
        }
        if fields["elapsedTime"] != nil {
            elapsedTime = try number(fields["elapsedTime"], field: "elapsedTime")
        }
    }

    /// What the Floor reports, as a `PlaybackState`.
    ///
    /// A reading without a title or an owner is not something that can be
    /// drawn: the adapter treats media without a title as invalid, and an owner
    /// is what says whose playback this is. Either missing means the Overlay
    /// stays quiet rather than showing half a Track.
    public var state: PlaybackState {
        guard let bundleIdentifier, let title else { return .notRunning }

        let track = Track(
            floorBundleIdentifier: bundleIdentifier,
            title: title,
            channel: artist ?? "",
            duration: duration
        )
        let position = elapsedTime ?? 0

        return isPlaying ? .playing(track, position: position) : .paused(track, position: position)
    }

    /// A number the adapter may report, answering `nil` when the key is simply
    /// absent — which on a diff event means unchanged, not missing.
    ///
    /// `NSNumber` rather than `Double`: `JSONSerialization` answers numbers as
    /// `NSNumber`, and a value present but not numeric is a malformed reading
    /// rather than an absent one.
    private func number(_ value: Any?, field: String) throws -> TimeInterval? {
        guard let value, value is NSNull == false else { return nil }
        guard let number = value as? NSNumber else {
            throw ParseError.invalidNumber(field: field)
        }
        return number.doubleValue
    }
}
