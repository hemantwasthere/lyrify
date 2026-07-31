# Lyrify

A menu bar companion for Spotify that follows along with what is playing and
shows its synced lyrics. This is the shared language for talking about it —
a glossary, not a spec.

## Language

### What is playing

**Track**:
One song, as Spotify names it: a URI, a title, an artist, and a duration.
_Avoid_: Song, item

**Non-Lyrical Item**:
A Track that is not a song — a podcast episode, an advert — and so has no
lyrics worth looking for.

**Playback Position**:
How far into the current Track playback has reached.
_Avoid_: Progress, elapsed, timestamp

**Anchor**:
A reading of what Spotify is playing at one instant, from which the Playback
Position between readings is estimated.

### Lyrics

**Synced Lyrics**:
A Track's lyrics with a start time against each line, which is what makes
following along possible. Lyrics without times are of no use here.
_Avoid_: Lyrics (unqualified), LRC

**Lyric Line**:
One timed line of Synced Lyrics.

**Active Line**:
The Lyric Line whose start time is the most recent one to have passed — the
line the Track is currently on. There is exactly one whenever playback has
reached the first Lyric Line, and it may be a Gap Marker.

**Gap Marker**:
A Lyric Line with no text — the Synced Lyrics' own way of saying that nothing
is sung from here. It is an ordinary Lyric Line with a start time, so it can
be the Active Line or sit among the lines around one.

**Instrumental Gap**:
A stretch mid-Track with nothing being sung, marked by a Gap Marker. The
surrounding Lyric Lines still exist and are still shown around it.

**Intro Gap**:
The stretch before the first Lyric Line, where no Active Line exists at all.
Distinct from an Instrumental Gap: there is no lyrical context to show,
because none has happened yet.
_Avoid_: Instrumental gap (they are not the same thing)

**Idle State**:
What is shown for a Track with no Synced Lyrics — the Track named honestly,
and why there are none, rather than a pretence of following it.

### The widget

**Overlay**:
The floating window Lyrify puts on screen. It has three forms: the Disc, and
the Expanded card's two views.
_Avoid_: Widget, HUD — as names for the whole. "Panel" is a surface *within*
the card (the artwork panel, the settings panel), never the Overlay itself.

**Disc**:
The Overlay Minimized — a small circle of album art, spinning while a Track
plays.

**Expanded card**:
The Overlay at full size, shaped after Spotify's miniplayer. Shows one of two
views at its centre.
_Avoid_: Miniplayer, *as a name for the card itself* — that is Spotify's,
which this imitates. It stays in the names of the controls modelled directly
on Spotify's, and in the "Miniplayer settings" panel that mirrors its.

**Now Playing view**:
The Expanded card showing album art at its centre.

**Lyrics view**:
The Expanded card showing Synced Lyrics at its centre — the Active Line
prominent, surrounding lines dimmed around it.

**Info Bar**:
The strip beneath the Expanded card's centre carrying the Track's title, its
artist, and the button that swaps between the two views.

**Lyrics Only**:
A persisted preference that holds the Expanded card on the Lyrics view and
takes away the Info Bar beneath it. It changes what surrounds the Lyrics view,
never what the Lyrics view draws. Lapses while the card is a Band.
_Avoid_: Hide track info, full lyrics, lyrics mode

**Portrait**:
The Expanded card's taller shape: centre view above, Info Bar below.

**Band**:
The Expanded card dragged short enough to become a single horizontal row.
Sheds controls — and Lyrics Only — as it narrows.
