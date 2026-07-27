import { DownloadButton, Note } from "@/components/primitives";
import { quarantineCommand, release, releaseNotesUrl } from "@/lib/release";
import { site } from "@/lib/site";

export function DownloadSection() {
  return (
    <section id="download" className="py-[clamp(40px,7vw,72px)]">
      <div className="flex flex-col items-center gap-[18px] rounded-[20px] border border-border bg-surface px-[clamp(24px,6vw,48px)] py-[clamp(40px,8vw,64px)] text-center">
        <div
          aria-hidden="true"
          className="vinyl-lg size-[84px] rounded-full border border-border"
        />
        <h2 className="max-w-[20ch] text-[clamp(1.5rem,3vw,2rem)]">
          Download Lyrify
        </h2>
        {/* One expression rather than an interpolation followed by text: JSX
            trims each line of a multi-line text node, which ate the space
            before the separator. */}
        <Note className="my-[1em] max-w-[40ch]">
          {`${site.requirements} · Apple Silicon & Intel · requires Spotify installed`}
        </Note>

        <DownloadButton />
        <Note as="span">v{release.version} · Free during early access</Note>

        {/* `my-[1em]` on both paragraphs reproduces the default `<p>` margin
            the static page inherited. Preflight zeroes it, which quietly
            tightened this card by 50px against the live design. */}
        <Note className="my-[1em] max-w-[58ch] leading-[1.9]">
          Signed ad-hoc, so the first launch needs one command: move Lyrify to
          Applications, then run{" "}
          <code className="whitespace-nowrap rounded-[5px] border border-border bg-surface-2 px-[5px] py-px font-mono text-text">
            {quarantineCommand}
          </code>{" "}
          in Terminal.
          <br />
          <a href={releaseNotesUrl} className="underline">
            Release notes
          </a>
        </Note>
      </div>
    </section>
  );
}
