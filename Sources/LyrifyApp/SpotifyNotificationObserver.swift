import Foundation
import LyrifyCore

/// Subscribes to Spotify's broadcast playback-state notification and hands
/// each parsed observation onward.
///
/// Subscribe, parse, hand over — nothing here is worth testing; the parsing
/// lives in `SpotifyNotificationPayload`. A malformed event is dropped rather
/// than surfaced: the notification is an event stream with no guarantee of
/// delivery anyway, and the re-anchor poll quietly repairs whatever a lost or
/// bad event broke.
@MainActor
final class SpotifyNotificationObserver {
    // nonisolated(unsafe) so deinit may remove it; safe because the token is
    // written once in init and never mutated again.
    private nonisolated(unsafe) var observation: NSObjectProtocol?

    init(onObservation: @escaping @MainActor (PlaybackState) -> Void) {
        observation = DistributedNotificationCenter.default().addObserver(
            forName: SpotifyNotificationPayload.notificationName,
            object: nil,
            queue: .main
        ) { notification in
            guard let userInfo = notification.userInfo,
                  let state = try? SpotifyNotificationPayload.parse(userInfo)
            else { return }
            MainActor.assumeIsolated { onObservation(state) }
        }
    }

    deinit {
        if let observation {
            DistributedNotificationCenter.default().removeObserver(observation)
        }
    }
}
