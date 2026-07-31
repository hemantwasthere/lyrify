"use client";

import { useCallback, useEffect, useRef, useState } from "react";

import { Note } from "@/components/primitives";

/**
 * A loop of the real Overlay, sitting under the hero as the first thing on the
 * page that isn't a simulation.
 *
 * The one client component on the site, and only because CSS cannot reach any
 * of this. `prefers-reduced-motion` can stop an animation but not an
 * `autoplay` attribute, so the attribute is left off entirely and playback is
 * started from here. Doing it the other way — autoplay, then pause once JS
 * notices — would show a reduced-motion visitor exactly the burst of movement
 * they asked not to see. With scripting off nothing plays and the first frame
 * stands.
 *
 * The recording carries sound, so it starts muted: every browser refuses to
 * autoplay a video that would make noise, and one that opens loud on a landing
 * page deserves that refusal. The speaker button is the gesture that lifts it.
 *
 * No `poster`. A browser draws the first frame of a video it has metadata for,
 * so the poster would be a second copy of a frame we already ship, one more
 * asset to keep in step with the recording.
 */
export function DemoVideo() {
  const videoRef = useRef<HTMLVideoElement>(null);
  const [muted, setMuted] = useState(true);

  useEffect(() => {
    const video = videoRef.current;
    if (!video) return;

    // Set here as well as in the markup: React has historically dropped
    // `muted` when hydrating, and an unmuted video is one the browser refuses
    // to autoplay at all.
    video.muted = true;

    // Read the state back off the element rather than trusting our own
    // bookkeeping — this also catches a mute driven from outside React, so the
    // icon can never disagree with what you are hearing.
    const sync = () => setMuted(video.muted);
    video.addEventListener("volumechange", sync);
    sync();

    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)");
    const apply = () => {
      if (reduced.matches) {
        video.pause();
        return;
      }
      // Rejects when autoplay is denied outright, which leaves the first frame
      // standing — not an error worth surfacing to a visitor.
      void video.play().catch(() => {});
    };

    apply();
    reduced.addEventListener("change", apply);
    return () => {
      video.removeEventListener("volumechange", sync);
      reduced.removeEventListener("change", apply);
    };
  }, []);

  const toggleMuted = useCallback(() => {
    const video = videoRef.current;
    if (!video) return;

    video.muted = !video.muted;

    // Asking for sound is asking for the recording to run. A reduced-motion
    // visitor is holding a still frame, and unmuting that would be a button
    // with nothing to play — so this one deliberate gesture starts it.
    if (!video.muted && video.paused) void video.play().catch(() => {});
  }, []);

  return (
    <section className="pb-[clamp(40px,7vw,72px)]">
      <div className="rounded-[20px] border border-border bg-surface p-[clamp(10px,1.6vw,16px)] shadow-card">
        {/* `relative` so the speaker sits inside the picture rather than in the
            card's padding — the control belongs to the footage. */}
        <div className="relative">
          {/* The ratio is held by the element itself rather than by a wrapper,
              so the space is reserved from first paint and nothing shifts
              under the reader when the video's own dimensions arrive. It
              matches the recording exactly — 1110x720, the Mac display's own
              shape — so there is no matting to see.

              `contain` rather than `cover` even so: if the recording is ever
              replaced at a different shape, this shows all of the new one
              instead of quietly slicing the edge off the widget the section
              exists to show. The failure mode is visible bars, which is the
              one you want. */}
          <video
            ref={videoRef}
            className="block aspect-[1110/720] w-full rounded-[12px] bg-bg object-contain"
            src="/lyrify-demo-2.mp4"
            muted
            loop
            playsInline
            preload="metadata"
            aria-label="Screen recording of the Lyrify overlay following a song, being resized, and revealing its controls on hover"
          />

          {/* Always drawn, never hover-revealed: a touch visitor has no hover,
              and a control they cannot find is one that isn't there. Its own
              dark scrim rather than a site colour, since it lays over footage
              whose brightness we do not control. */}
          <button
            type="button"
            onClick={toggleMuted}
            aria-pressed={!muted}
            aria-label={muted ? "Unmute the demo" : "Mute the demo"}
            title={muted ? "Unmute" : "Mute"}
            className="absolute right-[clamp(10px,2.2vw,22px)] bottom-[clamp(10px,2.2vw,22px)] grid size-[clamp(46px,5.4vw,64px)] place-items-center rounded-full bg-[rgba(20,17,12,0.55)] text-[#fdf6e8] backdrop-blur-sm transition-[background-color,transform] duration-150 ease-out hover:scale-105 hover:bg-[rgba(20,17,12,0.78)] focus-visible:outline-2 focus-visible:outline-offset-[3px] focus-visible:outline-text"
          >
            <SpeakerIcon muted={muted} />
          </button>
        </div>
      </div>
      <Note className="mt-4">
        Screen recording — the overlay running on a real Mac. Sound is off until
        you ask for it.
      </Note>
    </section>
  );
}

/**
 * One speaker, two tails: arcs when it is sounding, a cross when it is not.
 * Sized as a fraction of the button so both scale on the one clamp above.
 */
function SpeakerIcon({ muted }: { muted: boolean }) {
  return (
    <svg
      className="size-[52%]"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={1.9}
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <path d="M11 4.5 5.8 9H2.5v6h3.3l5.2 4.5V4.5Z" />
      {muted ? (
        <>
          <path d="m15.5 9.5 5 5" />
          <path d="m20.5 9.5-5 5" />
        </>
      ) : (
        <>
          <path d="M15.4 8.6a4.8 4.8 0 0 1 0 6.8" />
          <path d="M18.6 5.4a9.3 9.3 0 0 1 0 13.2" />
        </>
      )}
    </svg>
  );
}
