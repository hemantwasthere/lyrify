import AppKit
import Foundation
import LyrifyCore

/// Reads playback state from the Spotify desktop client over Apple Events.
///
/// Two rules govern this type, both from ADR-0002:
///
/// 1. Never script Spotify unless it is already running — scripting a closed
///    app *launches* it, and an overlay that starts Spotify at login would be a
///    genuinely bad bug.
/// 2. All unit conversion happens in `SpotifyScriptOutput`, not here.
@MainActor
final class SpotifyBridge: PlaybackSource {
    enum BridgeError: Error, Equatable {
        /// The user has not granted (or has revoked) Automation permission.
        case automationNotPermitted
        case scriptFailed(String)
    }

    private static let spotifyBundleIdentifier = "com.spotify.client"

    /// Emits one delimited line, or the stopped marker when there is no current
    /// track. Kept in sync with `SpotifyScriptOutput`.
    private static let source = """
        tell application "Spotify"
            set d to (ASCII character 31)
            set s to (player state as text)
            if s is "stopped" then return "stopped"
            set t to current track
            return s & d & (id of t) & d & (name of t) & d & (artist of t) & d ¬
                & (album of t) & d & ((duration of t) as text) & d ¬
                & ((player position) as text)
        end tell
        """

    private lazy var script = NSAppleScript(source: Self.source)

    /// Set once permission is refused, so we stop re-triggering a prompt the
    /// user has already dismissed. Ticket 10 turns this into a visible state.
    private(set) var isAutomationPermitted = true

    var isSpotifyRunning: Bool {
        NSRunningApplication
            .runningApplications(withBundleIdentifier: Self.spotifyBundleIdentifier)
            .isEmpty == false
    }

    func currentState() throws -> PlaybackState {
        guard isSpotifyRunning else { return .notRunning }
        guard isAutomationPermitted else { throw BridgeError.automationNotPermitted }

        var errorInfo: NSDictionary?
        let result = script?.executeAndReturnError(&errorInfo)

        if let errorInfo {
            throw mapError(errorInfo)
        }
        guard let output = result?.stringValue else {
            throw BridgeError.scriptFailed("Spotify returned no value")
        }

        return try SpotifyScriptOutput.parse(output)
    }

    private func mapError(_ info: NSDictionary) -> BridgeError {
        let code = info[NSAppleScript.errorNumber] as? Int ?? 0
        let message = info[NSAppleScript.errorMessage] as? String ?? "unknown error"

        // -1743 is errAEEventNotPermitted: the user declined Automation access.
        // -600 is procNotFound, which we can hit if Spotify quits mid-script.
        switch code {
        case -1743:
            isAutomationPermitted = false
            return .automationNotPermitted
        default:
            return .scriptFailed("\(message) (\(code))")
        }
    }
}
