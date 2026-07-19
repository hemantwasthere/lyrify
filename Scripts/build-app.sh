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
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BUILD_DIR/LyrifyApp" "$APP/Contents/MacOS/LyrifyApp"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# Ad-hoc signature. A stable signature matters more than it looks: macOS keys
# the granted Automation permission to it, so an unsigned rebuild would
# re-prompt on every launch.
codesign --force --sign - "$APP" >/dev/null 2>&1

echo "Built $APP"
