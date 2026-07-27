/**
 * The current build, in one place.
 *
 * Cutting a release edits `version` and `date` here and nothing else: the two
 * download buttons, the JSON-LD `softwareVersion` and `downloadUrl`, the
 * version line under each button, and the sitemap's `lastModified` all read
 * from this. The static page had the version written out in four places, and
 * they had already drifted — the bundle shipped as 0.1.0 while the site
 * advertised 0.2.0.
 */
export const release = {
  version: "0.3.0",
  /** Publish date, ISO. Doubles as the site's last meaningful change. */
  date: "2026-07-27",
  repo: "https://github.com/hemantwasthere/lyrify",
} as const;

/**
 * The release asset itself, not the release page — the first click should be
 * the download. Mirrors the name `gh release create` uploads.
 */
export const downloadUrl = `${release.repo}/releases/download/v${release.version}/Lyrify-${release.version}-macOS.zip`;

/** Kept on `/latest` so it stays right even if this constant lags a release. */
export const releaseNotesUrl = `${release.repo}/releases/latest`;

/**
 * Ad-hoc signed, never notarized, so Gatekeeper claims the app is damaged.
 * Linking the zip directly skips the release notes where this used to live,
 * so the page has to carry it.
 */
export const quarantineCommand = "xattr -cr /Applications/Lyrify.app";
