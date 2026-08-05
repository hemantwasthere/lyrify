# Lyrify

A menu bar app that follows along with what Spotify is playing and shows its
synced lyrics, and that can caption whatever else the machine is playing. This
is the shared language for talking about it — a glossary, not a spec.

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
A reading of what a Player is playing at one instant, from which the Playback
Position between readings is estimated.

**Player**:
Whatever Lyrify is following — the Spotify desktop client, or a browser. Which
one is being followed is decided once, where the Anchor stream is built;
nothing downstream of that knows there is more than one.

**Now Playing Floor**:
The single application macOS resolves as the owner of media playback — the one
the media keys and Control Center obey. Exactly one application holds it, and a
paused one keeps holding it, so an empty Floor means nothing is playing
anywhere rather than nothing being paused.
_Avoid_: Now Playing (unqualified) — the **Now Playing view** is a form of the
Expanded card and has nothing to do with this.

**Owner**:
Which Player the Floor names, and so the one Lyrify follows. The Floor says
*who*; that Player says *what* — Spotify is still asked over its own bridge,
because the Floor carries neither its URI nor its album nor anything that could
drive its transport. An application that is neither Spotify nor a browser is no
Owner at all, and shows the Idle State rather than a wrong Track.
_Avoid_: Arbitration, source selection — there is no preference to set and
nothing to choose. The listener chose by pressing play.

**Browser Track**:
A Track observed on the Now Playing Floor rather than from Spotify: the video's
title stands in for the name, the channel for the artist, and there is no
album. It has no Spotify URI, so its identity is composed from the application
publishing it and those two fields.

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

**Offset**:
A correction the listener applies by ear when a Match is right but shifted —
a music video carrying an intro card ahead of the song is the same recording
started late. It moves which Lyric Line is Active and nothing else: the
Playback Position, the progress bar and everything reported about the Player
stay as observed. Remembered against the Track, so a video corrected once
stays corrected.
_Avoid_: Delay, sync adjustment, calibration

### Captions

**Live Captions**:
A persisted preference, off until switched on, that transcribes the machine's
own audio and shows the words. Nothing is captured, transcribed or asked
permission for until it is on. It governs the Captions window and nothing
else — the Overlay is Spotify's whether it is on or off.
_Avoid_: Subtitles, transcription mode

**Caption**:
One line of what was said, and whether the transcriber has settled on it. An
unsettled Caption is still being revised and may yet change its words; a
settled one will not. Drawn differently, so a reader can tell what is certain
from what is still arriving.
_Avoid_: Lyric Line — a Caption has no start time and no future, which is the
whole reason it cannot live in the Lyrics view.

**Captions window**:
The separate window Live Captions draws into. Shows Captions and nothing else:
no title, no channel, no application name, no artwork, no transport. Starts as
a strip, grows as Captions arrive, and stops at four lines — after which the
oldest scroll out of sight rather than the window growing without end.
_Avoid_: Overlay — that is the Spotify one, and they are not the same window.

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
takes away the Info Bar beneath it, at every size. It changes what surrounds
the Lyrics view, never what the Lyrics view draws.
_Avoid_: Hide track info, full lyrics, lyrics mode

**Portrait**:
The Expanded card's taller shape: centre view above, Info Bar below.

**Band**:
The Expanded card dragged short enough to become a single horizontal row.
Sheds controls as it narrows. Has two arrangements: a square cover beside
the Track's title, or — under Lyrics Only — a panel stretched across to the
transport, which is the widest the lyrics ever get.
