import AppKit
import LyrifyCore

/// Live Captions, from the switch down.
///
/// Owns the preference, the window and — on a macOS new enough to have one —
/// the engine. Everything about it is inert until the listener switches it on:
/// no audio is captured, no permission is asked for, and no window appears.
///
/// What is captioned follows the Now Playing Floor, so the words describe the
/// thing being played. When the Floor moves, the tap moves with it; when the
/// Floor empties, there is nothing to caption and the window says so.
@MainActor
final class LiveCaptionsController {
    private let preference = LiveCaptionsPreference()
    private var window: CaptionsWindowController?

    /// The engine, held loosely because its type only exists on macOS 26. A
    /// stored property cannot carry an availability annotation, so this is the
    /// price of the whole feature being version-gated.
    private var engine: AnyObject?

    var isEnabled: Bool { preference.isEnabled }

    /// Whether this machine can run Live Captions at all.
    static var isSupported: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }

    /// Restores the switch at launch. A listener who left it on gets it back.
    func restore() {
        guard preference.isEnabled, Self.isSupported else {
            // A preference left on by a newer macOS, now running on an older
            // one, is quietly ignored rather than half-started.
            return
        }
        setEnabled(true)
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled, Self.isSupported else {
            preference.isEnabled = false
            stop()
            return
        }

        // Said before macOS asks, not after: the system dialog is one sentence
        // and a pair of buttons, which is no place to learn what you are
        // agreeing to. Declining here leaves everything exactly as it was.
        guard preference.hasBeenExplained || Self.explainAndAsk() else {
            preference.isEnabled = false
            return
        }
        preference.hasBeenExplained = true
        preference.isEnabled = true

        start()
    }

    /// Explains what turning this on means, and answers whether to go ahead.
    ///
    /// Deliberately says the awkward part out loud — that it follows whatever
    /// is playing, including something the listener did not have in mind — and
    /// says how to stop it. Someone who reads this and declines should feel
    /// they were told the truth rather than sold something.
    private static func explainAndAsk() -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Turn on Live Captions?"
        alert.informativeText = [
            "Lyrify will listen to the one app that is currently playing, and show what"
                + " it is saying in a window of its own.",
            "Everything is transcribed on your Mac. No audio and no text is sent anywhere,"
                + " and nothing is written to disk. macOS shows an indicator in the menu bar"
                + " the whole time it is listening.",
            "It follows whatever is playing, so if you switch to something private it hears"
                + " that too. Turning Live Captions off stops it, and you can take the"
                + " permission back at any time in System Settings.",
            "macOS will ask for permission to record system audio next.",
        ].joined(separator: "\n\n")

        alert.addButton(withTitle: "Turn On")
        alert.addButton(withTitle: "Not Now")

        // A menu bar agent is never the active app, so without this the alert
        // opens behind whatever is in front and looks like nothing happened.
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func start() {
        guard #available(macOS 26.0, *) else { return }

        let window = self.window ?? CaptionsWindowController()
        self.window = window
        window.show()

        let engine = (self.engine as? LiveCaptionsEngine) ?? LiveCaptionsEngine()
        self.engine = engine
        engine.onChange = { [weak self] in self?.redraw() }
        redraw()
    }

    private func stop() {
        if #available(macOS 26.0, *), let engine = engine as? LiveCaptionsEngine {
            engine.stop()
        }
        engine = nil
        window?.hide()
    }

    /// Points the engine at whichever process now holds the Floor. Called on
    /// every Anchor, and cheap when nothing has changed.
    func follow(process pid: Int?) {
        guard preference.isEnabled, #available(macOS 26.0, *),
            let engine = engine as? LiveCaptionsEngine
        else { return }
        engine.follow(process: pid.map { pid_t($0) })
    }

    private func redraw() {
        guard #available(macOS 26.0, *), let engine = engine as? LiveCaptionsEngine else { return }
        window?.update(captions: engine.captions, status: Self.message(for: engine.status))
    }


    /// What to say when there are no words yet. Each of these is an ordinary
    /// situation rather than a fault, and says what would change it.
    @available(macOS 26.0, *)
    private static func message(for status: LiveCaptionsEngine.Status) -> String {
        switch status {
        case .listening:
            return "Listening…"
        case .nothingPlaying:
            return "Nothing is playing"
        case .waitingForSound:
            return "Waiting for sound"
        case .permissionRefused:
            return
                "Lyrify needs permission to hear this app's audio.\n"
                + "System Settings → Privacy & Security → System Audio Recording"
        case .failed(let reason):
            return "Live Captions stopped: \(reason)"
        }
    }
}
