# Finding — Does browser media appear on the Now Playing floor?

Investigation for #87, gating the browser path in #86.
Run 2026-08-02 on macOS 26.5.2 (25F84), Apple Silicon.

**Recommendation: PROCEED**, with four amendments to #86 recorded at the end.

## Method

Built `ungive/mediaremote-adapter` v0.7.6 from source in `/tmp` (cmake, Xcode 26.2) and
drove its `get`, `stream`, `send` and `seek` commands directly. No Swift written, no
dependency added to the project, nothing installed outside `/tmp`, all of it removed
afterwards.

The adapter's self-test passed (`test` → exit 0), so the entitlement route still works on
this OS version.

Browser playback was produced with an isolated Chrome instance
(`--user-data-dir` in `/tmp`, `--autoplay-policy=no-user-gesture-required`) so videos
would play without stealing focus or touching the real profile. Arc was already playing a
video and was used as a second browser.

## The four assumptions

### 1. Does a browser appear as the owner of media playback? — YES

Both browsers tested appeared, under their **main** bundle identifier:

| Browser | `bundleIdentifier` | `parentApplicationBundleIdentifier` |
|---|---|---|
| Arc | `company.thebrowser.Browser` | absent |
| Chrome | `com.google.Chrome` | absent |

Spotify appeared as `com.spotify.client`, so routing Spotify vs browser vs other is
straightforward.

### 2. Do the video title and channel arrive as title and artist? — YES

`youtube.com/watch?v=dQw4w9WgXcQ` in Chrome:

```json
{"playbackRate": 1, "album": "", "elapsedTime": 0.002122,
 "timestamp": "2026-08-02T07:18:58Z", "bundleIdentifier": "com.google.Chrome",
 "title": "Rick Astley - Never Gonna Give You Up (Official Video) (4K Remaster)",
 "artist": "Rick Astley", "duration": 213.061,
 "artworkMimeType": "image/jpeg", "playing": true}
```

- `title` = the video title, marketing suffixes and all
- `artist` = **the channel name**
- `album` = empty string, always — confirms skipping the album widening step
- artwork is present (the video thumbnail), so the Disc has something to draw

### 3. Is elapsed time usable, and does it reflect real position? — YES

`elapsedTime` is static and paired with a `timestamp`; position is
`elapsedTime + (now − timestamp)`. **This is exactly the Anchor model `PlaybackClock`
already implements** — Spotify behaves identically, so both Players anchor the same way.

Launching the same video at `&t=90s` reported `elapsedTime: 90` against
`duration: 213.061`, proving elapsed reflects the true position rather than time-since-play:

```
[Chrome   ] el=90 ts=2026-08-02T07:21:38Z dur=213.061 playing=True :: Rick Astley - Never Gonna Give You Up
```

Pause/resume is reported (`playing` flips, a fresh anchor is issued).

### 4. Is the reported duration the video's? — YES for ordinary videos, NO for live

`duration: 213.061` against a video that is 3:33 (213s). Exact.

**But a YouTube Premiere or livestream reports `duration: inf`**, and the adapter cannot
encode that — it writes a line to stderr and **omits the key entirely**:

```
Invalid JSON value type in dictionary for key 'duration': inf (__NSCFNumber)
{"elapsedTime": 0, "bundleIdentifier": "company.thebrowser.Browser",
 "title": "INDIA'S GOT LATENT S2 EP4 ...", "artist": "Samay Raina", "playing": true}
```

Such items also report `elapsedTime: 0` permanently, resetting to the live edge, and
resume on their own after a pause.

This was initially mistaken for a general failure of the browser path. It is not — it is
correct behaviour for live content, and it is **useful**: a missing or infinite duration
is a free, reliable signal that an item is live and therefore a Non-Lyrical Item.

## Additional findings

**`music.youtube.com` returns already-clean metadata.** The same video, same bundle
identifier, different site:

| Source | `title` | `artist` |
|---|---|---|
| `youtube.com` | `Rick Astley - Never Gonna Give You Up (Official Video) (4K Remaster)` | `Rick Astley` |
| `music.youtube.com` | `Never Gonna Give You Up` | `Rick Astley` |

Lyrify cannot tell the two sites apart — both are `com.google.Chrome`. It does not need
to: a title with no separator falls through normalization unchanged and takes the channel
as artist, which is the correct answer for both. The design in #91 handles this without
knowing which site it is looking at.

**The stream is a diff stream.** `stream` emits partial payloads carrying only changed
keys — several captured events contained a single field and no bundle identifier:

```
[True ?] el=91.511747 ts=None dur=INF/MISSING playing=None ::
[True ?] el=None ts=None dur=INF/MISSING playing=False ::
```

#89 must merge these into a running snapshot. Treating each event as a complete
observation would produce Tracks with no title and no owner.

**Exactly one application holds the floor, and a paused one keeps it.** With Arc paused
and Chrome playing, the floor moved to Chrome; with Chrome quit, it returned to Arc
*while still paused*. So "nothing is happening" presents as a retained owner with
`playing: false`, not as an absent owner. #90 must decide on `playing`, not on presence
alone — and there is no way to observe two Players at once, which confirms the arbitration
design rather than undermining it.

**Playback can be driven.** `send 0`/`send 1` (play/pause) worked against the browser. Out
of scope for #86, which observes browsers rather than controlling them, but recorded
because it was free to learn.

## What was NOT established

Reported honestly — three acceptance criteria on #87 are not fully met:

- **No browser publishing from a helper process was found.** Arc and Chrome both publish
  under their main bundle. Safari and Firefox-based browsers were not tested, so whether
  `parentApplicationBundleIdentifier` is ever needed remains open. #89 should still consult
  it as a fallback, since it costs nothing.
- **No long *ordinary* video was measured.** The long item tested was a Premiere, i.e.
  live. Duration is confirmed correct for a 3½-minute VOD only; nothing suggests length
  matters, but it is untested.
- **The truly-empty case was never observed.** A paused browser retained the floor for the
  whole session, so `null` output was never produced. The adapter documents `null` when
  nothing is playing; unverified here.

Safari and Zen were not tested at all.

## Amendments this implies for #86

1. **Duration is optional, not guaranteed.** Live content omits it. Treat a Track with no
   duration as a Non-Lyrical Item — it cannot be Matched anyway, since both the exact
   lookup and the search filter require a duration. This is a cheap, correct livestream
   gate that the spec did not anticipate.
2. **The adapter's output must be parsed defensively.** A missing key is normal, not
   malformed input, and the stderr line about `inf` is noise rather than an error.
3. **The stream is a diff stream** and #89 must merge into a running snapshot.
4. **Arbitration keys on `playing`, not on presence** (#90), because a paused app retains
   the floor.

None of these change the shape of the design. The zero-permission story holds: everything
above was obtained with no automation prompt, no browser setting, and no network call to
Google.

## Cleanup

Adapter clone, build and Chrome scratch profile deleted from `/tmp`. Chrome was launched
by this investigation and has been quit. Arc was paused during measurement and returned to
playing. Spotify was played briefly as a control and returned to paused at its original
position (86.51s).
