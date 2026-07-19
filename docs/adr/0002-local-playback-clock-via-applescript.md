# The playback clock is local, and only follows the Spotify desktop client

Line-accurate lyrics need the Playback Position to within a few tens of milliseconds. We take it from the Spotify **desktop client on this Mac** — its broadcast playback-state notification supplies the events, AppleScript supplies each Anchor, and an estimate from a monotonic clock fills the gaps between Anchors, with frequent re-anchoring to bound Drift.

## Considered Options

- **Local, via the desktop client** (chosen) — sub-second position, no network in the path, and push notification of play, pause and track changes. Requires the user to grant Automation permission.
- **Spotify Web API** — the only thing that can see playback on other devices, but its reported progress is stale by an unpredictable, network-dependent margin and it is rate-limited by polling. Too coarse for line-accurate sync, and it would drag in an OAuth flow.
- **The MediaRemote private framework** — historically the best source of elapsed time and playback rate, but Apple has gated it behind a private entitlement and it is not viable on current macOS.

## Consequences

**Lyrify only works when you are playing through the Spotify app on this Mac.** Playing from a phone, another computer, or the web player shows nothing. This was accepted knowingly: the Web API is the only alternative that sees remote playback, and its timing is not good enough for the feature to work anyway.

Two operational constraints follow. Scripting an application that is not running will *launch* it, so every AppleScript call must be guarded by a check that Spotify is already running — otherwise Lyrify would start Spotify at login. And the app depends on a scripting interface Spotify could remove in any client update; there is no fallback if they do.

A trap worth recording: Spotify's scripting definition declares track `duration` in seconds, but it actually returns **milliseconds**, while `player position` really is in seconds. Confusing the two silently breaks every lyrics lookup, since matching is done on duration in seconds.
