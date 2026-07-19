# Lyrify

An always-on macOS overlay that displays the time-synchronised lyrics of the track currently playing in Spotify, two lines at a time, positioned in the notch or near the top of the screen.

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
A trusted observation pairing a Playback Position with the moment it was observed. Between Anchors, the current Playback Position is estimated by elapsed time; each new Anchor corrects the accumulated error.
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
The single always-visible, click-through window in which the Active Line and Next Line are shown. It never takes keyboard focus and follows the listener across desktops and fullscreen apps.
_Avoid_: Widget, HUD, window, panel

**Placement**:
Where on a chosen display the Overlay sits. When that display has a notch the Overlay straddles it; otherwise the Overlay is a pill near the top edge. The notch is a Placement, not a premise.
_Avoid_: Position, anchor (reserved above), docking

**Idle State**:
The reduced form the Overlay takes when it has no Synced Lyrics to show but playback is still happening — naming the Track without pretending to follow it.
_Avoid_: Empty state, fallback view
