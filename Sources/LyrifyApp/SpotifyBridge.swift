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

    /// A dedicated read, separate from `source` above: the artwork URL has
    /// no room in the notification path the way the rest of the fields do
    /// (Spotify's own broadcast payload doesn't carry it), so it is always
    /// fetched fresh, live, whenever a caller actually wants it.
    private static let artworkSource = """
        tell application "Spotify"
            if player state is stopped then return ""
            return (artwork url of current track)
        end tell
        """

    private lazy var artworkScript = NSAppleScript(source: Self.artworkSource)

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

    /// The current Track's artwork URL, or nil when Spotify reports none —
    /// no track playing, a Non-Lyrical Item, or a Track that simply has no
    /// artwork. Guarded by the same "never launch Spotify" rule as
    /// `currentState()`.
    func artworkURL() throws -> URL? {
        guard isSpotifyRunning else { return nil }
        guard isAutomationPermitted else { throw BridgeError.automationNotPermitted }

        var errorInfo: NSDictionary?
        let result = artworkScript?.executeAndReturnError(&errorInfo)

        if let errorInfo {
            throw mapError(errorInfo)
        }
        guard let output = result?.stringValue, output.isEmpty == false else {
            return nil
        }
        return URL(string: output)
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
