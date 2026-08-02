# MediaRemote adapter (vendored)

How Lyrify sees what a browser is playing.

| | |
|---|---|
| **Upstream** | https://github.com/ungive/mediaremote-adapter |
| **Version** | v0.7.6 |
| **Licence** | BSD 3-Clause (`LICENSE`) |
| **Built** | 2026-08-02, cmake + Xcode 26.2 |
| **Architectures** | `x86_64 arm64` (universal) |

## Why this is here as a binary

macOS 15.4 restricted the MediaRemote framework to entitled clients, which is
what broke every third-party "now playing" reader at the time. This adapter
reaches it through `/usr/bin/perl`, which *is* entitled, and streams readings to
standard output.

It is a cmake project. Vendoring the built framework rather than the source
keeps `swift build` working for anyone with nothing but Xcode, and matches how
Lyrify already ships — a hand-rolled universal build. The cost is a binary in
the repository that cannot be diffed, which is why the provenance above is
recorded precisely and the rebuild below is kept reproducible.

## How it is used

The framework is **bundled, never linked against**. Both it and the script are
passed to perl as paths:

```
/usr/bin/perl mediaremote-adapter.pl MediaRemoteAdapter.framework stream
```

`Scripts/build-app.sh` copies the framework into `Contents/Frameworks` and the
script into `Contents/Resources`, and signs the framework before the app —
signing the bundle seals what its Frameworks directory contains.

Lyrify running without either is a supported state. Built from source and run
straight out of the build directory, neither is present, and the browser Player
stays quiet while Spotify works exactly as it always has.

## Rebuilding

```sh
git clone --depth 1 --branch v0.7.6 https://github.com/ungive/mediaremote-adapter.git
cd mediaremote-adapter && mkdir build && cd build
cmake -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" ..
cmake --build .
```

Copy `build/MediaRemoteAdapter.framework` and `bin/mediaremote-adapter.pl` here,
preserving the framework's symlinks (`cp -R`), and update the table above.

Verify with:

```sh
lipo -info MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter
/usr/bin/perl mediaremote-adapter.pl "$PWD/MediaRemoteAdapter.framework" get
```

## If it stops working

This is a workaround for a restriction that was imposed once and could be
imposed again. It must never be able to take Spotify support down with it — if
the adapter cannot be found, will not start, or exits, the browser Player goes
quiet and nothing else changes. That is asserted by the tests around
`NowPlayingFloorSource`, and is the reason `NowPlayingFloorProcess` swallows
every failure it can encounter.
