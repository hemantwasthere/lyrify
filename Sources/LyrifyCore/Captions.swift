import Foundation

/// What has been said, as the transcriber reports it.
///
/// On-device transcription answers a line *while it is still being spoken* and
/// revises it as more arrives, then settles it — usually with different words
/// from the last revision, because the model changes its mind as it commits.
/// Keeping that straight is the whole job here: a revision replaces what it
/// revises, so the window shows one sentence firming up rather than a column of
/// fragments of the same thought.
///
/// A pure value. Nothing about audio, permissions or windows reaches in.
public struct Captions: Equatable, Sendable {
    /// One line of what was said.
    public struct Line: Equatable, Sendable, Identifiable {
        public let id: Int
        public let text: String

        /// Whether the transcriber has committed to these words. An unsettled
        /// line is still being revised and may yet change; a view can say so
        /// rather than presenting a guess as fact.
        public let isSettled: Bool
    }

    /// How many lines are kept. A machine left playing all day would otherwise
    /// grow this without limit, and nobody scrolls back through a day.
    public static let limit = 200

    public private(set) var lines: [Line] = []
    private var nextID = 0

    public init() {}

    /// The line currently being spoken, if one is.
    public var current: Line? {
        guard let last = lines.last, last.isSettled == false else { return nil }
        return last
    }

    /// Takes one result from the transcriber.
    ///
    /// `isFinal` is the transcriber's own distinction between a line it is still
    /// revising and one it has committed to. An unsettled line is replaced by
    /// whatever comes next; a settled one is kept and the next result starts a
    /// new line.
    ///
    /// Blank text is not a line. Pauses produce empty and whitespace-only
    /// results, and a window full of blank rows says nothing.
    public mutating func receive(_ text: String, isFinal: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Drop the unsettled line a blank result replaces, so a pause clears
        // what was mid-revision rather than freezing it on screen.
        if trimmed.isEmpty {
            if lines.last?.isSettled == false { lines.removeLast() }
            return
        }

        if let last = lines.last, last.isSettled == false {
            // Still the same line: keep its identity so a view can tell a
            // revision from an arrival.
            lines[lines.index(before: lines.endIndex)] = Line(
                id: last.id, text: trimmed, isSettled: isFinal)
        } else {
            lines.append(Line(id: nextID, text: trimmed, isSettled: isFinal))
            nextID += 1
        }

        if lines.count > Self.limit {
            lines.removeFirst(lines.count - Self.limit)
        }
    }

    /// Forgets everything. Live Captions being switched off leaves nothing
    /// behind, and nothing is written down in the first place.
    public mutating func clear() {
        lines.removeAll()
    }
}
