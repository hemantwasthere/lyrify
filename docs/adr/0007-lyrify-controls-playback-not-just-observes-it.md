# Lyrify controls playback, not just observes it

Every prior ticket treated Lyrify as a read-only observer of Spotify (ADR-0002): it scripts Spotify to read state, never to change it. The Expanded Overlay's Now Playing view adds play/pause, skip, seek, and volume controls, which means Lyrify now sends commands to Spotify — `playpause`, `next track`, `previous track`, `set player position`, `set sound volume` — through the same AppleScript/Automation channel it already reads through. No new permission prompt is needed, but the trust footprint is different: a bug here can now change what's playing, not just misreport it.

Album art is fetched via `artwork url of current track` — the same local, no-OAuth scripting dictionary already used for everything else — but it is a second external network dependency (an image fetch from Spotify's CDN) alongside LRCLIB's lyrics API.

## Consequences

The read/write distinction ADR-0002 didn't have to make now matters: a failed or malformed write — sending a command while Spotify is unreachable, mid-quit, or not running — needs the same fail-quiet treatment reads already get, not a surfaced error.

A Track with no artwork, or a Non-Lyrical Item, needs an honest placeholder in the Disc and Now Playing view, the same way a Track with no Synced Lyrics gets the Idle State rather than a blank space.
