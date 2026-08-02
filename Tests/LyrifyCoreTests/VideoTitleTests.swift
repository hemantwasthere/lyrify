import Foundation
import Testing

@testable import LyrifyCore

/// Reading an artist and a track name out of a video's title and channel.
/// Every title below is a real-world form.
@Suite("Video title")
struct VideoTitleTests {
    private func read(_ title: String, channel: String = "a channel") -> VideoTitle.Reading {
        VideoTitle.read(title: title, channel: channel)
    }

    // MARK: - Separators

    @Test("a hyphen splits artist from track name")
    func hyphenSplits() {
        let reading = read("Rick Astley - Never Gonna Give You Up")
        #expect(reading.artist == "Rick Astley")
        #expect(reading.name == "Never Gonna Give You Up")
    }

    @Test("en dash, em dash and pipe all split")
    func otherSeparatorsSplit() {
        #expect(read("Tame Impala – Let It Happen").name == "Let It Happen")
        #expect(read("Tame Impala — Let It Happen").name == "Let It Happen")
        #expect(read("Tame Impala | Let It Happen").name == "Let It Happen")
        #expect(read("Tame Impala | Let It Happen").artist == "Tame Impala")
    }

    /// Only the first separator divides: what follows belongs to the name, and
    /// a name containing a dash is not an invitation to keep cutting.
    @Test("only the first separator divides")
    func onlyFirstSeparatorDivides() {
        let reading = read("Sufjan Stevens - Death with Dignity - Live")
        #expect(reading.artist == "Sufjan Stevens")
        #expect(reading.name == "Death with Dignity - Live")
    }

    /// A hyphen inside a word is not a separator; only a spaced one is.
    @Test("a hyphenated word is not a separator")
    func hyphenatedWordIsNotASeparator() {
        let reading = read("Jay-Z Song Without A Separator", channel: "JayZVEVO")
        #expect(reading.name == "Jay-Z Song Without A Separator")
        #expect(reading.artist == "JayZ")
    }

    // MARK: - The fall-through, which music.youtube.com depends on

    /// `music.youtube.com` reports an already-clean title with no separator.
    /// It must survive untouched and take the channel as the artist.
    @Test("an already-clean title survives and takes the channel as artist")
    func cleanTitleFallsThrough() {
        let reading = read("Never Gonna Give You Up", channel: "Rick Astley")
        #expect(reading.name == "Never Gonna Give You Up")
        #expect(reading.artist == "Rick Astley")
    }

    /// The two YouTube sites reach the same answer by different routes.
    @Test("both YouTube sites read the same song")
    func bothSitesAgree() {
        let watch = read(
            "Rick Astley - Never Gonna Give You Up (Official Video) (4K Remaster)",
            channel: "Rick Astley"
        )
        let music = read("Never Gonna Give You Up", channel: "Rick Astley")
        #expect(watch == music)
    }

    // MARK: - Marketing noise

    @Test("marketing and format suffixes are stripped")
    func marketingSuffixesStripped() {
        #expect(read("A - B (Official Video)").name == "B")
        #expect(read("A - B (Official Music Video)").name == "B")
        #expect(read("A - B [Official Audio]").name == "B")
        #expect(read("A - B (Lyrics)").name == "B")
        #expect(read("A - B (Lyric Video)").name == "B")
        #expect(read("A - B (Visualizer)").name == "B")
        #expect(read("A - B (Audio)").name == "B")
        #expect(read("A - B (HD)").name == "B")
        #expect(read("A - B (4K Remaster)").name == "B")
        #expect(read("A - B (Remastered)").name == "B")
        #expect(read("A - B (Explicit)").name == "B")
    }

    @Test("several suffixes at once are all stripped")
    func severalSuffixesStripped() {
        #expect(read("A - B (Official Video) (4K Remaster) [HD]").name == "B")
    }

    /// A marker that names a *different recording* is left alone. Stripping it
    /// would invite a Match against the studio take whose timings do not fit —
    /// the duration gate would usually catch that, but inviting it is wrong.
    @Test("markers naming a different recording are left alone")
    func versionMarkersSurvive() {
        #expect(read("A - B (Live)").name == "B (Live)")
        #expect(read("A - B (Acoustic)").name == "B (Acoustic)")
        #expect(read("A - B (Remix)").name == "B (Remix)")
        #expect(read("A - B (Sped Up)").name == "B (Sped Up)")
    }

    @Test("a featured artist is kept, being part of how the song is named")
    func featuredArtistKept() {
        #expect(read("A - B (feat. C)").name == "B (feat. C)")
    }

    // MARK: - Channels

    /// YouTube's auto-generated artist channels are named "Artist - Topic", and
    /// they are the cleanest source of metadata there is.
    @Test("a Topic channel names the artist")
    func topicChannel() {
        #expect(read("Let It Happen", channel: "Tame Impala - Topic").artist == "Tame Impala")
    }

    @Test("a VEVO channel names the artist")
    func vevoChannel() {
        #expect(read("Some Song", channel: "RickAstleyVEVO").artist == "RickAstley")
        #expect(read("Some Song", channel: "Dua Lipa VEVO").artist == "Dua Lipa")
    }

    @Test("an ordinary channel is taken as it is")
    func ordinaryChannel() {
        #expect(read("Some Song", channel: "fireb0rn").artist == "fireb0rn")
    }

    // MARK: - Degenerate input

    @Test("whitespace is tidied rather than carried into a lookup")
    func whitespaceTidied() {
        #expect(read("  A   -   B  ").artist == "A")
        #expect(read("  A   -   B  ").name == "B")
    }

    /// Stripping everything would leave nothing to look up, so the original
    /// stands rather than being reduced to emptiness.
    @Test("a title that is nothing but noise keeps its original text")
    func allNoiseKeepsOriginal() {
        #expect(read("A - (Official Video)").name == "(Official Video)")
    }

    @Test("an empty title falls back to the channel and stays empty")
    func emptyTitle() {
        let reading = read("", channel: "someone")
        #expect(reading.name.isEmpty)
        #expect(reading.artist == "someone")
    }

    /// A separator with nothing before it is not a split.
    @Test("a leading separator is not a split")
    func leadingSeparator() {
        let reading = read("- Just A Name", channel: "someone")
        #expect(reading.name == "- Just A Name")
        #expect(reading.artist == "someone")
    }
}
