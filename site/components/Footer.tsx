import { release } from "@/lib/release";
import { site } from "@/lib/site";

export function Footer() {
  return (
    <footer className="mt-5 border-t border-border pt-10 pb-[60px]">
      <div className="mb-4 flex items-center gap-[10px] font-mono text-[0.78rem] text-text-dim">
        <a
          href={release.repo}
          className="text-text transition-colors duration-200 hover:text-accent focus-visible:outline-2 focus-visible:outline-offset-[3px] focus-visible:outline-accent"
        >
          Source on GitHub
        </a>
        <span aria-hidden="true">·</span>
        <a
          href={site.author.x}
          className="text-text transition-colors duration-200 hover:text-accent focus-visible:outline-2 focus-visible:outline-offset-[3px] focus-visible:outline-accent"
        >
          {site.author.handle} on X
        </a>
      </div>
      <p className="mb-2 max-w-[60ch] font-mono text-[0.74rem] text-text-dim">
        Lyrify is an independent, open-source project. It is not affiliated
        with, endorsed by, or sponsored by Spotify AB.
      </p>
      <p className="mb-2 max-w-[60ch] font-mono text-[0.74rem] text-text-dim">
        © {new Date(release.date).getFullYear()} Lyrify.
      </p>
    </footer>
  );
}
