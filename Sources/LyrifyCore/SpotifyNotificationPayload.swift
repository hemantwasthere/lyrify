import Foundation

/// Turns the user-info dictionary of Spotify's broadcast playback-state
/// notification into a `PlaybackState`.
///
/// Kept free of AppKit so the parsing — including the milliseconds conversion
/// that ADR-0002 warns about — is testable without Spotify running. Malformed
/// payloads are errors, never guesses.
public enum SpotifyNotificationPayload {
    /// The distributed notification Spotify posts on every state change.
    public static let notificationName = Notification.Name("com.spotify.client.PlaybackStateChanged")

    public enum ParseError: Error, Equatable {
        case missingKey(String)
        case invalidValue(key: String)
        case unknownPlayerState(String)
    }

    public static func parse(_ userInfo: [AnyHashable: Any]) throws -> PlaybackState {
        let playerState = try string("Player State", in: userInfo)

        // Stopped arrives with no track fields at all, so bail out before
        // looking for them.
        if playerState == "Stopped" { return .stopped }

        let track = Track(
            uri: try string("Track ID", in: userInfo),
            name: try string("Name", in: userInfo),
            artist: try string("Artist", in: userInfo),
            album: try string("Album", in: userInfo),
            duration: try number("Duration", in: userInfo) / 1000
        )
        let position = try number("Playback Position", in: userInfo)

        return switch playerState {
        case "Playing": .playing(track, position: position)
        case "Paused": .paused(track, position: position)
        default: throw ParseError.unknownPlayerState(playerState)
        }
    }

    private static func string(_ key: String, in userInfo: [AnyHashable: Any]) throws -> String {
        guard let raw = userInfo[key] else { throw ParseError.missingKey(key) }
        guard let value = raw as? String else { throw ParseError.invalidValue(key: key) }
        return value
    }

    private static func number(_ key: String, in userInfo: [AnyHashable: Any]) throws -> TimeInterval {
        guard let raw = userInfo[key] else { throw ParseError.missingKey(key) }
        // CFBoolean is an NSNumber, so `true` would otherwise parse as 1; and
        // a non-finite value must never be anchored into the clock.
        guard let value = raw as? NSNumber,
              CFGetTypeID(value) != CFBooleanGetTypeID(),
              value.doubleValue.isFinite
        else { throw ParseError.invalidValue(key: key) }
        return value.doubleValue
    }
}
