# The artwork wash samples the dominant colour, not the average

ADR-0011 settled that Full Layout's backdrop is a flat colour sampled from the artwork rather than a blur, and described what to sample as "a dominant/average color" — leaving the two as interchangeable. They are not. `CoreImageArtworkColorWash` implemented the average (`CIAreaAverage` over the whole image), and averaging is the wrong measure: it mixes every colour in the cover into one muddy brown-grey. A vivid red sleeve came out the same dull shade as a photograph, which is worst on exactly the colourful artwork the wash exists to flatter.

The sampler now bins pixels by hue, saturation and brightness and takes the weighted mean of the heaviest bin. Near-black and blown-out pixels are excluded from the vote — letting them count is a large part of what dragged the average toward grey — and saturated pixels are weighted up, so a small band of strong colour can beat a large expanse of near-grey. The winning colour is then lifted to meet what Spotify actually draws (measured side by side with playback paused: saturation near 0.45, brightness near 0.75), since a raw dominant colour comes back both darker and flatter than Spotify's panel.

This was arrived at independently on the `feat/ui-tweaks` miniplayer branch, tuned against a live side-by-side, and is ported here rather than rediscovered.

## Consequences

The `ArtworkBlurring` seam (`func blur(_ artwork: Data) async -> Data?`) is unchanged, as is `BlurredArtworkProvider`'s actor, memoization and Track-URI-keyed dedup — still a pure function of the same artwork bytes. Only the colour chosen changes.

Two of ADR-0011's suggested tests no longer hold, and were replaced rather than relaxed. "A solid-color source resolves to that same color" is now false by design: the lift toward Spotify's own saturation and brightness means a fully saturated source comes back deliberately softened, so the test asserts the *hue* survives and the colour is visibly softened instead. The test asserting the busy fixture resolved to its "true average" asserted the very behaviour being removed, and is replaced by one that pits a vivid minority against a grey majority — the case that motivated the change.

That replacement test carries a measured threshold rather than a nominal one. On its fixture, averaging reaches a red/green margin of about 48 and dominance about 109; the assertion is set at 80. A margin chosen for looking "clearly red" would have sat under 48 and passed under both implementations, making the regression test useless for the one regression it exists to catch.

A wholly black or wholly white cover has every pixel excluded by the near-black/blown-out filter, so no bin qualifies. Rather than returning nil and dropping the backdrop — real artwork is sometimes exactly this — the sampler falls back to the plain average for that case, which always exists. Nil is still returned for genuinely undecodable bytes, so `BlurredArtworkProvider`'s `.unavailable` memoization keeps its meaning.
