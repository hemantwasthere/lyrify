import { PlayerMock } from "@/components/PlayerMock";
import { DownloadButton, Eyebrow, Note } from "@/components/primitives";
import { release } from "@/lib/release";

export function Hero() {
  return (
    <section className="grid grid-cols-[1.1fr_1fr] items-center gap-[clamp(32px,6vw,56px)] pt-[clamp(8px,2vw,24px)] pb-[clamp(48px,8vw,88px)] max-[760px]:grid-cols-1">
      <div>
        <Eyebrow>Menu bar app for Spotify · macOS</Eyebrow>
        <h1 className="mt-[14px] mb-5 text-[clamp(2.4rem,5vw,3.4rem)] leading-[1.08]">
          Lyrics that keep up
          <br />
          with <em className="italic text-accent">the music.</em>
        </h1>
        <p className="max-w-[42ch] text-[1.05rem] text-text-dim">
          Lyrify floats a small, time-synced lyrics overlay over whatever you&apos;re
          doing — it follows the song line by line, and follows you across every
          desktop and every fullscreen window.
        </p>
        <div className="mt-7 flex flex-wrap items-center gap-[18px]">
          <DownloadButton />
          <Note as="span">v{release.version} · Free during early access</Note>
        </div>
      </div>

      <PlayerMock />
    </section>
  );
}
