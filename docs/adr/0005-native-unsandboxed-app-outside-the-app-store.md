# Native, unsandboxed, and distributed outside the Mac App Store

Lyrify is built natively against Cocoa — a pure, testable core package holding the lyrics parsing, lookup and timing logic, plus a thin menu-bar-agent app target for the Overlay — and it is shipped unsandboxed outside the Mac App Store.

## Considered Options

A web-based shell (Electron or Tauri) was considered and rejected. Every platform capability this app depends on — an overlay window above the menu bar, notch geometry, the system-wide playback notification, and scripting another application — is a first-class Cocoa API and a workaround in the alternatives. The deciding factor was idle cost: this app runs all day, every day, and an overlay that permanently consumes a hundred megabytes and a slice of CPU is one that gets uninstalled.

The Mac App Store was considered and rejected as effectively closed to this app. A sandboxed app may only send Apple Events under a temporary-exception entitlement that Apple has scrutinised or refused for years — and Apple Events *are* the playback clock (see ADR-0002). Designing for the sandbox would mean giving up the feature.

## Consequences

We deliberately do not enable the sandbox and do not contort the architecture around entitlements we will never be granted. Distribution starts as a locally-built, ad-hoc-signed personal app; a Developer ID signature, notarisation and a disk image are deferred until the app has proved it earns daily use, since that path costs an annual developer subscription.

The app must declare why it needs to control other applications and must handle the user *declining* that permission as a first-class state, explaining how to reverse it. Without it Lyrify is permanently inert, and a silently dead menu-bar app is indistinguishable from a broken one.

Keeping the timing and matching logic in a UI-free core package is a testability decision as much as a structural one: timing bugs are miserable to diagnose through an animated overlay and obvious against a command-line harness that prints the Active Line as music plays.
