#!/usr/bin/env node
/**
 * Renders every brand raster from `Resources/Brand/app-icon.svg`, then rebuilds
 * both icon archives from those rasters.
 *
 * One source drawing for all of it, deliberately. The mark lives in three
 * places that must agree — the site header, the browser tab, and the user's
 * Dock — and the only way they stay in step is if none of them is ever touched
 * by hand. Edit the SVG, run this.
 *
 * `LyrifyMark.tsx` is the exception it cannot cover: JSX, so it is a redraw of
 * `logo-mark.svg` rather than a render of it. The two are kept identical by
 * hand and `logo-mark.svg` is `app-icon.svg` without the plate, scaled by 1.5.
 *
 * Uses `sharp` out of the site's `node_modules` rather than taking a dependency
 * of its own — it is already there for Next.js, and libvips rasterises SVG.
 * `iconutil` is a macOS built-in.
 *
 *     node Scripts/render-brand.mjs
 */
import { execFileSync } from "node:child_process";
import { mkdtempSync, mkdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { createRequire } from "node:module";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const require = createRequire(join(root, "site", "package.json"));
const sharp = require("sharp");

const source = join(root, "Resources/Brand/app-icon.svg");

/** Every raster the repo ships, and the pixel size each one is. */
const rasters = [
  ["Resources/Brand/web/favicon-16.png", 16],
  ["Resources/Brand/web/favicon-32.png", 32],
  ["Resources/Brand/web/apple-touch-icon-180.png", 180],
  ["Resources/Brand/web/logo-512.png", 512],
  ["Resources/Brand/web/logo-1024.png", 1024],
  ["site/public/favicon-16.png", 16],
  ["site/public/favicon-32.png", 32],
  ["site/public/apple-touch-icon.png", 180],
];

/** The ten entries `iconutil` expects, as [filename, pixel size]. */
const iconset = [
  ["icon_16x16.png", 16],
  ["icon_16x16@2x.png", 32],
  ["icon_32x32.png", 32],
  ["icon_32x32@2x.png", 64],
  ["icon_128x128.png", 128],
  ["icon_128x128@2x.png", 256],
  ["icon_256x256.png", 256],
  ["icon_256x256@2x.png", 512],
  ["icon_512x512.png", 512],
  ["icon_512x512@2x.png", 1024],
];

// Rasterise from the SVG at each size rather than downscaling one big render:
// the rim and groove are thin enough at 16px that resampling a 1024 bitmap
// turns them to mush, where re-rasterising keeps them on the pixel grid.
const render = (size) => sharp(source, { density: 384 }).resize(size, size).png().toBuffer();

for (const [relative, size] of rasters) {
  await sharp(await render(size)).toFile(join(root, relative));
  console.log(`${String(size).padStart(4)}px  ${relative}`);
}

// The social card is its own drawing rather than the icon at another size — it
// is a composition, with the mark in it at 0.6 scale. Rendered here anyway, so
// no brand raster in the repo is ever produced by hand.
await sharp(join(root, "Resources/Brand/og-image.svg"), { density: 192 })
  .resize(1200, 630)
  .png()
  .toFile(join(root, "site/public/og-image.png"));
console.log("1200x630  site/public/og-image.png");

const staging = mkdtempSync(join(tmpdir(), "lyrify-icons-"));
const iconsetDir = join(staging, "Lyrify.iconset");
mkdirSync(iconsetDir);
for (const [name, size] of iconset) {
  await sharp(await render(size)).toFile(join(iconsetDir, name));
}

for (const target of ["Resources/Lyrify.icns", "Resources/Brand/Lyrify.icns"]) {
  execFileSync("iconutil", ["-c", "icns", iconsetDir, "-o", join(root, target)]);
  console.log(`        ${target}`);
}
rmSync(staging, { recursive: true, force: true });
