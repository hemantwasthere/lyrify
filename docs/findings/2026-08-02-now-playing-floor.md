# Finding — Does browser media appear on the Now Playing Floor?

Investigation for #87, gating the browser path in #86.
Run 2026-08-02 on macOS 26.5.2 (25F84), Apple Silicon.

**Recommendation: PROCEED**, with five amendments to #86 recorded at the end.

**Now Playing Floor** is used throughout for the single application macOS resolves as the
current owner of media playback — the one the media keys and Control Center obey. It is a
new term and needs adding to CONTEXT.md, with an explicit note that it is *not* the
**Now Playing view**, which is the Expanded card showing album art at its centre.

## Method

Built `ungive/mediaremote-adapter` v0.7.6 from source in `/tmp` (cmake, Xcode 26.2) and
drove its `get`, `stream` and `send` commands directly. No Swift written, no dependency
added to the project, nothing installed outside `/tmp`.

The adapter's self-test passed (`test` → exit 0), so the entitlement route still works on
this OS version.

Browser playback was produced with an isolated Chrome instance
(`--user-data-dir` in `/tmp`, `--autoplay-policy=no-user-gesture-required`) so videos
would play without stealing focus or touching the real profile. Arc was already playing a
video and was used as a second browser.

No network traffic was captured, so claims below concern only what this investigation
itself requested — they are not a measurement of what the browser or the adapter did.

## The four assumptions

### 1. Does a browser appear on the Now Playing Floor? — YES

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

That sample alone cannot prove `artist` is the channel, because this channel's name and
the performer's name are the same string. The Arc sample is what settles it:

```json
{"album": "", "elapsedTime": 0, "bundleIdentifier": "company.thebrowser.Browser",
 "title": "INDIA'S GOT LATENT S2 EP4 ft. Karan Aujla, Tanmay Bhat, Gurleen Pannu, Rahul Dua",
 "artist": "Samay Raina", "artworkMimeType": "image/jpeg", "playing": true}
```

"Samay Raina" is the channel and appears nowhere in the title, so `artist` is the channel
rather than anything parsed out of the title.

- `title` = the video title, marketing suffixes and all
- `artist` = the channel name
- `album` = empty in all four samples taken — consistent with skipping the album widening
  step, though four samples is not "always"
- artwork is present (the video thumbnail), so the Disc has something to draw

### 3. Is the reported position usable? — YES for reporting, NOT ESTABLISHED for seeking

`elapsedTime` is static and paired with a `timestamp`; position is
`elapsedTime + (now − timestamp)`. Spotify's readings through the same adapter have the
same shape, so a single Anchor model serves both Players — and that model is the one
`PlaybackClock` already implements.

Launching the video at `&t=90s` reported `elapsedTime: 90` against `duration: 213.061`:

```
[Chrome   ] el=90 ts=2026-08-02T07:21:38Z dur=213.061 playing=True :: Rick Astley - Never Gonna Give You Up
```

This proves the reported position is the video's true position rather than time-since-play.
It does **not** prove the seek behaviour #87 asked for — see "What was NOT established".

Pause and resume are reported: `playing` flips and a fresh anchor is issued.

### 4. Is the reported duration the video's? — YES for the ordinary video tested, NO for live

`duration: 213.061` against a video that is 3:33. Correct, on a single sample.

**A YouTube Premiere or livestream reports `duration: inf`**, which the adapter cannot
encode — it writes a line to stderr and **omits the key entirely**:

```
Invalid JSON value type in dictionary for key 'duration': inf (__NSCFNumber)
{"elapsedTime": 0, "bundleIdentifier": "company.thebrowser.Browser",
 "title": "INDIA'S GOT LATENT S2 EP4 ...", "artist": "Samay Raina", "playing": true}
```

Live content also reports `elapsedTime: 0` in most samples, resetting toward the live edge,
and resumes on its own after a pause. It is not invariably 0 — one paused reading gave
`elapsed=10.435` — so a zero position is a hint about live content, never a test for it.

This was initially mistaken for a general failure of the browser path. It is not: it is
correct behaviour for live content, and an infinite duration is a genuine signal that an
item can never be Matched, because both the exact lookup and the search filter require a
duration. See amendment 1 for why that signal is more delicate than it first appears.

## Additional findings

**`music.youtube.com` returns already-clean metadata.** The same video, same bundle
identifier, different site:

| Source | `title` | `artist` |
|---|---|---|
| `youtube.com` | `Rick Astley - Never Gonna Give You Up (Official Video) (4K Remaster)` | `Rick Astley` |
| `music.youtube.com` | `Never Gonna Give You Up` | `Rick Astley` |

Lyrify cannot tell the two sites apart — both are `com.google.Chrome`. It does not need to,
but the two rows reach the same answer by *different* routes, which is worth stating
precisely: the `youtube.com` title contains a separator and is split into artist and track
name, while the `music.youtube.com` title contains none, falls through unchanged, and takes
the channel as artist. Both land on artist "Rick Astley" and track "Never Gonna Give You
Up". The normalization in #91 therefore needs no knowledge of which site it is looking at —
but it must handle both routes, not just the split.

**The update stream carries diffs, not whole observations.** `stream` emits partial
payloads containing only changed keys — several captured events had a single field and no
bundle identifier at all:

```
el=91.511747  ts=None  dur=absent  playing=None  title=None
playing=False  everything else absent
```

#89 must merge these into a running snapshot. Treating each event as a complete observation
would produce Tracks with no title and no owner.

**Exactly one application holds the Floor, and a paused one keeps it.** With Arc paused and
Chrome playing, the Floor moved to Chrome; with Chrome quit, it returned to Arc *while still
paused*. So "nothing is happening" presents as a retained owner with `playing: false`, not
as an absent owner. #90 must decide on `playing`, not on presence alone.

Note this cuts against #90's stated shape as well as for it: the Floor is single-valued, so
there is no way to observe two Players at once. #90 describes arbitration over "the two
candidate states", which is not what the system offers — the Floor *is* the arbitration, and
the second Player is simply invisible while it is not the owner.

## What was NOT established

Reported against #87's checklist. Five criteria are unmet or partial:

- **Seeking was never tested.** #87 asks whether position "is corrected after seeking
  forwards and backwards". The `&t=90s` evidence above is a *start offset*, not a seek of a
  playing video, and backwards seeking was not attempted at all. A `seek` command was issued
  during the session but the Floor was contested at that moment and the reading could not be
  attributed to a browser, so it is not reported here. **This gates #86 user story 19 and
  should be settled inside #89 rather than assumed.**
- **No browser publishing from a helper process was found.** Arc and Chrome both publish
  under their main bundle, and `parentApplicationBundleIdentifier` was absent in every
  sample. #86 asserts browsers "frequently publish from a helper process"; this
  investigation found no evidence for that. #90 should still consult it as a fallback, since
  it costs nothing, but the claim is unsupported.
- **No long *ordinary* video was measured.** The long item tested was a Premiere, i.e. live.
  Duration is confirmed for one 3½-minute video only.
- **The empty case was never observed.** A paused browser retained the Floor throughout, so
  `null` output never occurred. The adapter documents `null` when nothing is playing;
  unverified here.
- **Arc was only ever observed on live content**, so its title, artist and duration
  behaviour for an ordinary video is untested. Only Chrome was measured on a VOD.

Safari, Zen and Firefox were not tested at all.

## Amendments this implies for #86

1. **Duration is optional, and the live signal must be read off the merged snapshot.** Live
   content omits it, and an item with no duration can never be Matched. But this interacts
   badly with amendment 2: on a *diff* event a missing key means "unchanged", not "absent",
   so the signal is only meaningful once events are merged. It is also load-bearing on an
   adapter encoding bug — `inf` failing to serialise — which a fixed adapter would silently
   turn into a real `inf` value. #89 should therefore treat *either* an absent duration on a
   merged snapshot *or* a non-finite one as the same condition, rather than keying on
   absence alone. Note this is a *matchability* test, not the glossary's **Non-Lyrical
   Item**, which is about an item not being a song: a livestreamed concert is lyrical and
   still unmatchable.
2. **The update stream carries diffs** and #89 must merge into a running snapshot rather
   than treating each event as complete.
3. **Arbitration keys on `playing`, not on presence** (#90), because a paused application
   retains the Floor.
4. **#90's framing needs adjusting.** It describes a decision over two candidate states, but
   the Floor is single-valued and the non-owning Player is unobservable. The pure decision
   is over the Floor's identity and *one* state, which is simpler than specified.
5. **#86's browser-coverage claim is unevidenced.** "Works in every browser" (user story 18)
   rests on Safari, Zen and Firefox, none of which were tested, and on a helper-process
   fallback for which no evidence was found. Either test them inside #89 or soften the
   claim.

None of these change the shape of the design. The zero-permission story holds for
everything actually observed: no automation prompt and no browser setting was needed at any
point.

## Cleanup

`/tmp` scratch directory (adapter clone, build, Chrome profile, logs) removed. Chrome was
launched by this investigation and has been quit. Arc was paused during measurement and
returned to playing. Spotify was played briefly as a control and returned to paused at its
original position (86.51s).

Two mutations of live state were made that #87 did not ask for, recorded for honesty: the
adapter's `send` command was used to pause and resume playback. #86 lists transport control
over the browser as out of scope, so this is not a capability finding — only a note that the
investigation moved state it then restored.
