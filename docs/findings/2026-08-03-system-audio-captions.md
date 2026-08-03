# Finding — Can the machine's own audio be tapped and captioned live?

Investigation for #103, gating Live Captions in #86.
Run 2026-08-03 on macOS 26.5.2 (25F84), Apple Silicon, Xcode 26.2.

**Recommendation: PROCEED**, with one design change that improves both the
feature and its privacy story — see "Tap the Owner, not the machine".

## Method

A throwaway command-line program: a global Core Audio process tap feeding
`SpeechAnalyzer`/`SpeechTranscriber`, printing every result with the time it
arrived. Nothing was added to Lyrify; the program lives in `/tmp` and is deleted.

## The four assumptions

### 1. Can a Core Audio process tap capture system *output*? — YES

`CATapDescription(stereoGlobalTapButExcludeProcesses: [])` wrapped in a private
aggregate device, read through an IO proc:

```
[tap] format 48000.0Hz 2ch
[tap] started
[tap] first audio received
```

`muteBehavior = .unmuted` matters: the listener keeps hearing what they were
hearing. It was never silenced during the run.

### 2. Which permission? — NOT ESTABLISHED

The capture simply worked, with no prompt observed. That is **not** evidence that
no permission is needed: the spike ran as a command-line tool under an already
permissioned parent process, which inherits its consent. A bundled, signed
Lyrify.app is a different TCC subject and will be prompted on its own.

What the API requires is documented as the narrow **System Audio Recording**
permission (`NSAudioCaptureUsageDescription`) rather than ScreenCaptureKit's
broader Screen Recording. **#93 must verify this from the real app bundle**, and
must handle refusal, because this run proves nothing about that path.

Notably, transcription itself never prompted either — a file was transcribed
before any capture existed, with no speech-recognition authorisation. Whether
that holds for live input from a bundled app is likewise unverified.

### 3. Does the transcriber answer while audio is still playing? — YES

Word by word, then a settled line:

```
 19.1s [partial]  … Live capt
 20.1s [partial]  … Live captions should appear
 21.2s [partial]  … Live captions should appear as I speak.
 21.3s [FINAL ]   … Live captions should appear as I speak.
```

This is exactly the volatile-then-final shape #94 needs: a line arrives while it
is being spoken, is revised in place as more arrives, and eventually settles.
`result.isFinal` is what distinguishes them.

The model is an on-demand system asset. `AssetInventory.assetInstallationRequest`
downloaded and installed it on first use without any intervention.

Formats: the tap answers 48kHz stereo, the transcriber wants 16kHz mono, so an
`AVAudioConverter` sits between them. Straightforward, but not optional.

### 4. Is it good enough to read? — YES

Accuracy on clear speech was excellent, including punctuation. On a file, a test
sentence came back verbatim.

**Lag is roughly one second** from a word being spoken to its text appearing —
fine for reading along, and comparable to the live captions on streaming sites.

Numbers are normalised rather than transcribed literally ("2nd" for "second"),
which is worth knowing but not worth fighting.

## Tap the Owner, not the machine

The most important thing this run showed was not in the plan.

A **global** tap captures every sound the machine makes, mixed into one stream.
During the run it picked up unrelated audio — including what was plainly a live
voice conversation — and interleaved it with the audio under test, producing a
single settled line stitched together from two unrelated sources. As a caption
that is worse than useless: it is confidently wrong about what was said.

Two problems, one cause, one fix:

- **Quality.** Captions mixing a call, a notification and a video into one
  sentence are not captions of anything.
- **Privacy.** A global tap hears everything, which is precisely what makes the
  permission frightening and what #96 has to warn about.

`CATapDescription` can tap **specific processes** rather than everything. Lyrify
already knows which process to tap: the Now Playing Floor reports
`processIdentifier` alongside the bundle identifier, and #90 already resolves the
Owner. Tapping only the Owner's process means the captions describe the thing
being played and nothing else, and the app hears only that process rather than
the whole machine.

**#93 should tap the Owner's process, not the machine.** The global tap should
not ship. This also softens #96 considerably — the honest warning becomes "Lyrify
hears the app that is playing" rather than "Lyrify hears everything".

Consequence to accept: with nothing on the Floor there is nothing to tap, so Live
Captions has nothing to caption. That is the correct behaviour anyway.

## Other notes

- `SpeechAnalyzer` and `SpeechTranscriber` are present in the macOS 26 SDK.
  `.progressiveTranscription` is the preset for live partial results; the name in
  much of the writing about this API is wrong.
- `bestAvailableAudioFormat(compatibleWith:)` is on `SpeechAnalyzer`, not on
  `SpeechTranscriber`.
- Live Captions will be **macOS 26+ only**. Lyrify targets 14+, so it must be a
  capability that is absent rather than broken on older systems.

## What was NOT established

- **Which permissions a bundled, signed Lyrify.app is actually prompted for**, and
  what the dialogs say. The spike inherited consent from its parent process.
- **Behaviour on refusal** — untested, and #93 must handle it.
- **Per-process tapping** was reasoned from the API, not exercised. #93 should
  prove it early, since the whole design now rests on it.
- **Music rather than speech** was not tested; a sung track will presumably
  produce poor or empty captions.
- **CPU cost** over a long session was not measured.

## Cleanup

The `/tmp` spike program and its logs are deleted. Nothing was added to the app.
No audio was written to disk at any point.
