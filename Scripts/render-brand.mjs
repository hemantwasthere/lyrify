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
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
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
  // The site's icons live in `site/app/` rather than `site/public/` on purpose.
  // Next's file conventions serve these under a content hash and cache them
  // immutably, so a recoloured mark reaches the tab as a new URL. Served from
  // `public/` the path never changes, and a browser that cached the old icon
  // keeps drawing it — favicon caches are famously indifferent to
  // `must-revalidate`, which is how the green disc outlived the green theme.
  ["site/app/icon.png", 32],
  ["site/app/apple-icon.png", 180],
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

/**
 * Packs PNGs into an ICO container: a 6-byte header, then one 16-byte entry per
 * image, then the images themselves. The entries carry the offsets, so the
 * directory has to be sized before any of it can be written.
 *
 * The images stay PNG rather than the format's original BMP — every browser has
 * read PNG-in-ICO since Vista, and sharp cannot write BMP anyway. A 256px entry
 * would record its size as 0 (the field is one byte); nothing here is that big.
 */
const ico = (images) => {
  const header = Buffer.alloc(6);
  header.writeUInt16LE(1, 2); // type: 1 = icon
  header.writeUInt16LE(images.length, 4);

  let offset = header.length + images.length * 16;
  const directory = images.map(({ size, png }) => {
    const entry = Buffer.alloc(16);
    entry.writeUInt8(size, 0); // width
    entry.writeUInt8(size, 1); // height
    entry.writeUInt16LE(1, 4); // colour planes
    entry.writeUInt16LE(32, 6); // bits per pixel
    entry.writeUInt32LE(png.length, 8);
    entry.writeUInt32LE(offset, 12);
    offset += png.length;
    return entry;
  });

  return Buffer.concat([header, ...directory, ...images.map((i) => i.png)]);
};

// `/favicon.ico` 404'd before this existed. Next serves `app/favicon.ico` at the
// root path, which is the URL browsers ask for unprompted — and the one that
// ends up in bookmarks and history, where a stale icon lingers longest.
const icoSizes = [16, 32, 48];
writeFileSync(
  join(root, "site/app/favicon.ico"),
  ico(await Promise.all(icoSizes.map(async (size) => ({ size, png: await render(size) })))),
);
console.log(`${icoSizes.join("/")}px  site/app/favicon.ico`);

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
