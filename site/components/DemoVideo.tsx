"use client";

import { useEffect, useRef } from "react";

import { Note } from "@/components/primitives";

/**
 * A silent loop of the real Overlay, sitting under the hero as the first thing
 * on the page that isn't a simulation.
 *
 * The one client component on the site, and only because CSS cannot reach this.
 * `prefers-reduced-motion` can stop an animation but not an `autoplay`
 * attribute, so the attribute is left off entirely and playback is started from
 * here. Doing it the other way — autoplay, then pause once JS notices — would
 * show a reduced-motion visitor exactly the burst of movement they asked not to
 * see. With scripting off nothing plays and the first frame stands, which is
 * the same place this lands while the recording is still missing.
 *
 * No `poster`. A browser draws the first frame of a video it has metadata for,
 * so the poster would be a second copy of a frame we already ship, one more
 * asset to keep in step with the recording.
 */
export function DemoVideo() {
  const videoRef = useRef<HTMLVideoElement>(null);

  useEffect(() => {
    const video = videoRef.current;
    if (!video) return;

    // Set here as well as in the markup: React has historically dropped `muted`
    // when hydrating, and an unmuted video is one the browser refuses to
    // autoplay at all.
    video.muted = true;

    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)");
    const apply = () => {
      if (reduced.matches) {
        video.pause();
        return;
      }
      // Rejects when there is no playable source — which is exactly the state
      // this section ships in until the recording lands, and is not an error
      // worth surfacing to a visitor.
      void video.play().catch(() => {});
    };

    apply();
    reduced.addEventListener("change", apply);
    return () => reduced.removeEventListener("change", apply);
  }, []);

  return (
    <section className="pb-[clamp(40px,7vw,72px)]">
      <div className="rounded-[20px] border border-border bg-surface p-[clamp(10px,1.6vw,16px)] shadow-card">
        {/* The ratio is held by the element itself rather than by a wrapper, so
            the space is reserved from first paint and nothing shifts under the
            reader when the video's own dimensions arrive. It matches the
            recording exactly — 1280x720 — so there is no matting to see.

            `contain` rather than `cover` even so: if the recording is ever
            replaced at a different shape, this shows all of the new one instead
            of quietly slicing the edge off the widget the section exists to
            show. The failure mode is visible bars, which is the one you want. */}
        <video
          ref={videoRef}
          className="aspect-[16/9] w-full rounded-[12px] bg-bg object-contain"
          src="/lyrify-demo.mp4"
          muted
          loop
          playsInline
          preload="metadata"
          aria-label="Screen recording of the Lyrify overlay following a song, being resized, and revealing its controls on hover"
        />
      </div>
      <Note className="mt-4">
        Screen recording — the overlay running on a real Mac.
      </Note>
    </section>
  );
}
