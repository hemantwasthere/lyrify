# Lyrify

An always-on macOS companion widget for the track currently playing in Spotify: a draggable, resizable Overlay that shows time-synchronised lyrics, playback controls, and album art, and follows the listener across every desktop Space and fullscreen app.

## Language

### Playback

**Track**:
A single recording playing in Spotify, identified by its Spotify URI. The URI is the canonical identity used everywhere a track must be named or remembered.
_Avoid_: Song, item

**Non-Lyrical Item**:
Anything Spotify can play that is not a Track we could ever find lyrics for — an advertisement, a podcast episode, or a user's local file. Distinguished from a Track by its URI.
_Avoid_: Ad, non-song

**Playback Position**:
How far into the Track playback has reached, expressed in seconds.
_Avoid_: Progress, elapsed, timestamp

**Anchor**:
A trusted observation of playback — its state and Playback Position — paired with the moment it was observed. Between Anchors, the current Playback Position is estimated by elapsed time; each new Anchor corrects the accumulated error.
_Avoid_: Sample, tick, sync point

**Drift**:
The growing divergence between the estimated Playback Position and the real one, in the interval since the last Anchor.

### Lyrics

**Synced Lyrics**:
Lyrics in which every Lyric Line carries the time at which it begins. The only kind Lyrify can display.
_Avoid_: Timed lyrics, LRC

**Plain Lyrics**:
Lyrics with no timing information. Treated as equivalent to having no lyrics at all, because a two-line overlay cannot know which line is current.
_Avoid_: Unsynced lyrics, static lyrics

**Lyric Line**:
One line of Synced Lyrics together with the Playback Position at which it begins. A Lyric Line has no recorded end — it remains current until the next one begins.

**Active Line**:
The Lyric Line whose start time is the latest one not yet passed by the current Playback Position. Displayed prominently.
_Avoid_: Current lyric, highlighted line

**Next Line**:
The Lyric Line immediately following the Active Line, displayed dimmed so the listener can anticipate it.
_Avoid_: Upcoming lyric, preview

**Instrumental Gap**:
A stretch between two Lyric Lines long enough that nothing is being sung. Displayed differently from an Active Line, so the overlay does not imply words are being sung when they are not.
_Avoid_: Break, silence, interlude

### Matching

**Match**:
The act of deciding that a set of Synced Lyrics belongs to a specific Track. A Match is only accepted when the evidence — title, artist, and above all duration — is strong.

**Fail Closed**:
The governing policy for uncertain Matches: when Lyrify cannot be confident the lyrics belong to this exact recording, it shows none. Wrong lyrics drift out of time and read as a broken app; no lyrics reads as an honest gap.
_Avoid_: Best guess, fallback match

**Coverage**:
The proportion of Tracks a listener plays for which Synced Lyrics can be found. The principal quality limit on the product.

### Timing correction

**Offset**:
A manual time correction applied to lyric timing, compensating for the delay between what Spotify reports and what the listener hears. Global Offset covers the listener's audio setup; Per-Track Offset covers an individual set of badly-timed lyrics.
_Avoid_: Delay, latency adjustment, calibration

### Display

**Overlay**:
The single always-visible companion widget for the current Track: draggable anywhere by clicking and dragging its body directly, resizable, and never taking keyboard focus even though it accepts clicks — so it never steals focus from whatever the listener is doing elsewhere. Follows the listener across every desktop Space and fullscreen app.
_Avoid_: HUD (implies non-interactive; this one is dragged and clicked directly)

**Minimized**:
The Overlay's resting state: a small spinning Disc of album art and nothing else. Click the Disc to reach Expanded.
_Avoid_: Collapsed, docked

**Disc**:
The Minimized Overlay's shape — a small circle of the current Track's album art, spinning while the Track plays and freezing at its current angle when paused, resuming from that angle on play.
_Avoid_: Bubble, sphere

**Expanded**:
The Overlay's larger, resizable state, reached by clicking the Disc: a card alternating between its Now Playing view (playback controls, revealed on hover so the resting card stays uncluttered) and its Lyrics view (the Active Line and Next Line, or more surrounding lines as the card is resized larger), toggled by the lyrics button. Clicking the album art again returns to Minimized.
_Avoid_: Popover, panel (as the user-facing term — fine as an implementation detail)

**Idle State**:
What the Lyrics view shows when the current Track has no Synced Lyrics to display — an honest "nothing found" message rather than stale or empty lines. The Track is still named via the album art and title shown throughout the Overlay regardless of lyrics availability.
_Avoid_: Empty state, fallback view
