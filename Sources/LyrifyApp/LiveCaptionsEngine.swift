import AVFoundation
import Foundation
import LyrifyCore
import Speech

/// Turns one process's audio into captions.
///
/// The tap supplies the sound and `SpeechTranscriber` supplies the words, both
/// on-device: no audio is written to disk and none leaves the machine. What is
/// captioned is whichever process holds the Now Playing Floor, so the words
/// describe the thing being played rather than everything the machine happens to
/// be making noise about.
///
/// Every failure here is a state to explain rather than an error to raise.
/// Refusing the permission, having nothing playing, or running on a macOS
/// without the transcriber are all ordinary situations a listener can be in, and
/// none of them may disturb Spotify, the browser Player, or the Overlay.
@available(macOS 26.0, *)
@MainActor
final class LiveCaptionsEngine {
    /// What the captions window should say when there are no words.
    enum Status: Equatable {
        case listening
        case nothingPlaying
        /// The process holds the Floor but has no audio object yet — it has not
        /// actually made a sound.
        case waitingForSound
        case permissionRefused
        case failed(String)
    }

    private(set) var captions = Captions()
    private(set) var status: Status = .nothingPlaying

    /// Called whenever the captions or the status change.
    var onChange: (() -> Void)?

    private var tap: ProcessAudioTap?
    private var analyzer: SpeechAnalyzer?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var results: Task<Void, Never>?
    private var listeningTo: pid_t?

    /// The process being captioned, or nothing.
    ///
    /// Called whenever the Floor moves. Changing process tears the old tap down
    /// and stands a new one up; the window and everything already said survive
    /// it, because the listener has not stopped listening — the sound merely
    /// moved.
    func follow(process pid: pid_t?) {
        guard pid != listeningTo else { return }

        stopListening()
        listeningTo = pid

        guard let pid else {
            status = .nothingPlaying
            onChange?()
            return
        }
        Task { await startListening(to: pid) }
    }

    /// Stops everything and forgets what was said. Nothing is retained after
    /// Live Captions is switched off.
    func stop() {
        stopListening()
        listeningTo = nil
        captions.clear()
        status = .nothingPlaying
        onChange?()
    }

    private func stopListening() {
        tap?.stop()
        tap = nil
        continuation?.finish()
        continuation = nil
        results?.cancel()
        results = nil
        analyzer = nil
    }

    private func startListening(to pid: pid_t) async {
        do {
            let locale = Locale(identifier: "en-US")
            let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)

            // The model is an on-demand system asset, absent until first asked
            // for. Installing it can take a moment on a slow connection.
            if let request = try await AssetInventory.assetInstallationRequest(
                supporting: [transcriber])
            {
                try await request.downloadAndInstall()
            }

            guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
                compatibleWith: [transcriber])
            else {
                status = .failed("no usable audio format")
                onChange?()
                return
            }

            let analyzer = SpeechAnalyzer(modules: [transcriber])
            let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
            try await analyzer.start(inputSequence: stream)

            self.analyzer = analyzer
            self.continuation = continuation

            results = Task { [weak self] in
                do {
                    for try await result in transcriber.results {
                        guard let self else { return }
                        self.captions.receive(
                            String(result.text.characters), isFinal: result.isFinal)
                        self.onChange?()
                    }
                } catch {
                    self?.status = .failed(error.localizedDescription)
                    self?.onChange?()
                }
            }

            // The converter is built lazily: the tap decides its own format, and
            // it is not known until it starts.
            nonisolated(unsafe) var converter: AVAudioConverter?
            let tap = ProcessAudioTap()
            try tap.start(pid: pid) { buffer in
                guard let tapFormat = tap.format else { return }
                if converter == nil {
                    converter = AVAudioConverter(from: tapFormat, to: analyzerFormat)
                }
                guard let converter,
                    let converted = Self.convert(buffer, with: converter, to: analyzerFormat)
                else { return }
                continuation.yield(AnalyzerInput(buffer: converted))
            }
            self.tap = tap
            status = .listening
            onChange?()

        } catch ProcessAudioTap.TapError.processHasNoAudio {
            // Normal: the process holds the Floor but has not made a sound yet.
            status = .waitingForSound
            onChange?()
        } catch {
            // A refused permission surfaces here as a Core Audio failure. It is
            // reported as refusal rather than as a fault, because that is
            // overwhelmingly what it is — and either way Lyrify carries on.
            status = .permissionRefused
            onChange?()
        }
    }

    /// The tap answers 48kHz; the transcriber wants 16kHz mono. Runs on the
    /// audio thread, so it allocates only what it must.
    private nonisolated static func convert(
        _ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter, to format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity)
        else { return nil }

        var supplied = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, output.frameLength > 0 else { return nil }
        return output
    }
}
