#!/bin/bash
# Assembles Lyrify.app from the SwiftPM build products.
#
# A bundle is not optional: the Automation permission prompt needs a bundle
# identifier and NSAppleEventsUsageDescription to attach to, and LSUIElement is
# what keeps Lyrify out of the Dock. See ADR-0005 — unsandboxed, ad-hoc signed,
# distributed outside the App Store.
set -euo pipefail

CONFIGURATION="${1:-debug}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$(swift build --configuration "$CONFIGURATION" --show-bin-path)"
APP="$ROOT/.build/Lyrify.app"

swift build --configuration "$CONFIGURATION"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

cp "$BUILD_DIR/LyrifyApp" "$APP/Contents/MacOS/LyrifyApp"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/Lyrify.icns" "$APP/Contents/Resources/Lyrify.icns"

# The MediaRemote adapter, which is how Lyrify sees what a browser is playing.
# Bundled, never linked against: the framework is loaded by the script, which
# is run by /usr/bin/perl, and both are passed to it as paths. Lyrify running
# without them is a supported state — the browser Player simply stays quiet.
cp -R "$ROOT/Vendor/mediaremote-adapter/MediaRemoteAdapter.framework" "$APP/Contents/Frameworks/"
cp "$ROOT/Vendor/mediaremote-adapter/mediaremote-adapter.pl" "$APP/Contents/Resources/"

# Ad-hoc signature. A stable signature matters more than it looks: macOS keys
# the granted Automation permission to it, so an unsigned rebuild would
# re-prompt on every launch.
#
# Nested code is signed first: signing the bundle seals what its Frameworks
# directory contains, so a framework signed afterwards invalidates the
# enclosing signature rather than joining it.
codesign --force --sign - "$APP/Contents/Frameworks/MediaRemoteAdapter.framework" >/dev/null 2>&1
codesign --force --sign - "$APP" >/dev/null 2>&1

echo "Built $APP"
