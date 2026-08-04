import Foundation
import LyrifyCore

/// Runs the bundled MediaRemote adapter and feeds its output to the browser
/// Player.
///
/// The adapter exists because direct access to the system's now-playing
/// information was restricted to entitled clients in macOS 15.4. It reaches it
/// through `/usr/bin/perl`, which is entitled, and streams readings to standard
/// output. See `docs/findings/2026-08-02-now-playing-floor.md`.
///
/// Everything here is failure-tolerant on purpose. The adapter is a workaround
/// for a restriction that was imposed once and could be imposed again, so it
/// must never be able to take Spotify support down with it: if it cannot be
/// found, will not start, or exits, the browser Player simply goes quiet and
/// the Spotify path is untouched.
@MainActor
final class NowPlayingFloorProcess {
    private let source: NowPlayingFloorSource
    private var process: Process?

    /// Called after each reading is merged, so the Anchor stream can re-derive.
    /// Readings arrive when the Floor changes rather than on a clock, which is
    /// exactly when a fresh Anchor is worth taking.
    var onReading: (() -> Void)?

    init(source: NowPlayingFloorSource) {
        self.source = source
    }

    deinit {
        process?.terminate()
    }

    /// Stops the adapter.
    ///
    /// Must be called on the way out. Nothing reaps a child process when its
    /// parent exits, and `deinit` is not reached on quit — the app delegate is
    /// still alive when the process ends — so relying on it leaves a perl
    /// process behind holding a subscription nobody reads. Observed doing
    /// exactly that before this existed.
    ///
    /// A kill the app cannot handle — `SIGKILL`, or a `pkill` that AppKit
    /// never gets to answer — orphans the adapter, and it has been seen
    /// surviving one. It does not notice the pipe has gone until it next tries
    /// to write, which on a quiet Floor may be a long time. Nothing here can
    /// prevent that; it is recorded so the next person does not read the code
    /// and believe otherwise.
    func stop() {
        process?.terminationHandler = nil
        process?.terminate()
        process = nil
        source.forget()
    }

    /// Locates the adapter inside the app bundle.
    ///
    /// Answers `nil` when running unbundled — straight out of the build
    /// directory during development — because neither piece is there to find.
    /// That is a supported way to run Lyrify, so it is quiet rather than loud:
    /// Spotify still works, and only the browser Player is missing.
    private static func adapter() -> (script: URL, framework: URL)? {
        guard let script = Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl"),
            let frameworks = Bundle.main.privateFrameworksURL
        else { return nil }

        let framework = frameworks.appendingPathComponent("MediaRemoteAdapter.framework")
        guard FileManager.default.fileExists(atPath: framework.path) else { return nil }

        return (script, framework)
    }

    func start() {
        guard let adapter = Self.adapter() else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [adapter.script.path, adapter.framework.path, "stream"]

        let output = Pipe()
        process.standardOutput = output
        // The adapter reports live content's infinite duration as a diagnostic
        // every time it appears. Those go to standard error and are of no
        // interest here; the reading itself arrives on standard output with the
        // duration simply absent.
        process.standardError = FileHandle.nullDevice

        // Readings can be split across reads and more than one can arrive in a
        // single read, so output is buffered and cut on newlines. Touched only
        // from the pipe's own serial queue.
        nonisolated(unsafe) var buffer = Data()

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard chunk.isEmpty == false else { return }
            buffer.append(chunk)

            var lines: [Data] = []
            while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                lines.append(buffer[buffer.startIndex..<newline])
                buffer = buffer[buffer.index(after: newline)...]
            }
            guard lines.isEmpty == false else { return }

            Task { @MainActor in self?.receive(lines) }
        }

        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in self?.stopped() }
        }

        do {
            try process.run()
            self.process = process
        } catch {
            // Nothing to say and nothing to do: the browser Player stays quiet.
        }
    }

    private func receive(_ lines: [Data]) {
        for line in lines where line.isEmpty == false {
            source.receive(line)
        }
        onReading?()
    }

    private func stopped() {
        process = nil
        source.forget()
        onReading?()
    }
}
