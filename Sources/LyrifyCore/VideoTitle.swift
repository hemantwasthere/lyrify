import Foundation

/// Reads an artist and a track name out of a video's title and channel.
///
/// A video is not named the way a lyrics database names a recording. It carries
/// marketing — "(Official Video)", "[4K Remaster]" — and it puts the artist in
/// the title, or in the channel, or in both, or in neither. This is where that
/// is turned into the two fields a lookup needs.
///
/// It happens at the boundary, when a browser Track is built, so the lyrics
/// pipeline receives an ordinary Track and never learns that YouTube exists:
/// no new branch, no video-aware Matching, no second widening sequence.
///
/// **One interpretation is committed to.** Trying "artist first" and then
/// "title first" would mean the provider iterating candidates, which is exactly
/// the YouTube awareness this is here to keep out of it. The search step
/// absorbs what a single reading gets slightly wrong.
public enum VideoTitle {
    public struct Reading: Equatable, Sendable {
        public let artist: String
        public let name: String
    }

    /// Noise a video's title carries that a recording's name does not.
    ///
    /// Deliberately only *marketing and format*. A marker naming a different
    /// recording — live, acoustic, a remix, sped up — is left in place: removing
    /// it would invite a Match against the studio take whose timings do not fit
    /// the audio being played. The duration gate would usually refuse that
    /// anyway, but inviting it would be wrong.
    private static let noise: Set<String> = [
        "official video", "official music video", "official audio",
        "official hd video", "official lyric video", "official visualizer",
        "lyrics", "lyric video", "with lyrics",
        "audio", "visualizer", "visualiser", "music video", "video",
        "hd", "hq", "4k", "8k", "1080p", "720p",
        "remaster", "remastered", "4k remaster", "hd remaster",
        "explicit", "clean", "full song", "full album version",
    ]

    /// Separators that divide an artist from a track name. Spaced, so a
    /// hyphenated word is not mistaken for a division.
    private static let separators = [" - ", " – ", " — ", " | ", " · "]

    /// Divides before stripping, which matters: a title whose track name is
    /// nothing but marketing — "Artist - (Official Video)" — loses its
    /// separator if the noise goes first, and with it the artist that was
    /// sitting in front of it.
    public static func read(title: String, channel: String) -> Reading {
        guard let split = divide(title) else {
            return Reading(artist: self.channel(from: channel), name: strip(noiseFrom: title))
        }
        return Reading(
            artist: strip(noiseFrom: split.artist),
            name: strip(noiseFrom: split.name)
        )
    }

    /// Divides on the first separator, and only when there is something on both
    /// sides of it — a title that merely opens with a dash has not named an
    /// artist.
    private static func divide(_ title: String) -> Reading? {
        var earliest: Range<String.Index>?
        for separator in separators {
            guard let found = title.range(of: separator) else { continue }
            if earliest == nil || found.lowerBound < earliest!.lowerBound {
                earliest = found
            }
        }
        guard let earliest else { return nil }

        let artist = tidy(String(title[title.startIndex..<earliest.lowerBound]))
        let name = tidy(String(title[earliest.upperBound...]))
        guard artist.isEmpty == false, name.isEmpty == false else { return nil }

        return Reading(artist: artist, name: name)
    }

    /// Removes bracketed groups whose whole content is noise, leaving anything
    /// else — a featured artist, a version marker — exactly where it was.
    ///
    /// If that would leave nothing at all, the original stands: an empty name
    /// is not something to look a recording up by.
    private static func strip(noiseFrom title: String) -> String {
        var result = ""
        var group = ""
        var depth = 0

        for character in title {
            if character == "(" || character == "[" {
                depth += 1
                if depth == 1 { group = "" } else { group.append(character) }
                continue
            }
            if character == ")" || character == "]" {
                depth -= 1
                if depth == 0 {
                    let content = group.trimmingCharacters(in: .whitespaces)
                    if noise.contains(content.lowercased()) == false {
                        let bracket = character == ")" ? "(\(content))" : "[\(content)]"
                        result += bracket
                    }
                } else {
                    group.append(character)
                }
                continue
            }
            if depth > 0 { group.append(character) } else { result.append(character) }
        }

        let stripped = tidy(result)
        return stripped.isEmpty ? title : stripped
    }

    /// The artist a channel names, where its name is a convention rather than
    /// simply the artist: YouTube's auto-generated "Artist - Topic" channels,
    /// which are the cleanest metadata there is, and the label-run VEVO ones.
    private static func channel(from channel: String) -> String {
        var name = channel.trimmingCharacters(in: .whitespaces)

        if let topic = name.range(of: " - Topic", options: [.anchored, .backwards]) {
            name = String(name[name.startIndex..<topic.lowerBound])
        }
        if name.count > 4, name.hasSuffix("VEVO") {
            name = String(name.dropLast(4))
        }
        return tidy(name)
    }

    /// Trims, and collapses the runs of spaces that stripping leaves behind.
    private static func tidy(_ value: String) -> String {
        value.split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
