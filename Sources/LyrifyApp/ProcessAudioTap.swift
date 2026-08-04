import AVFoundation
import CoreAudio
import Foundation

/// Listens to one process's audio output.
///
/// A *process* tap, never a global one. A global tap hears everything the
/// machine plays and mixes it into a single stream, which during the
/// investigation stitched an unrelated voice conversation together with the
/// audio under test into one confident, wrong sentence. Tapping the process that
/// is actually playing is what makes a caption describe the thing it claims to.
/// It also means Lyrify hears one application rather than the whole machine,
/// which is a far smaller thing to ask permission for. See
/// `docs/findings/2026-08-03-system-audio-captions.md`.
///
/// `nonisolated` throughout, deliberately. A Core Audio IO proc runs on a
/// real-time thread, and touching main-actor state from it does not merely race
/// — the concurrency runtime traps, which is exactly how the first version of
/// this crashed.
///
/// Nothing is muted. `CATapUnmuted` is the default and is left alone: the
/// listener goes on hearing what they were hearing.
@available(macOS 14.2, *)
final class ProcessAudioTap: @unchecked Sendable {
    enum TapError: Error {
        /// Core Audio has no process object for this pid — which is normal for a
        /// process that has never played anything.
        case processHasNoAudio(pid_t)
        case failed(String, OSStatus)
    }

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?

    /// The shape the tap answers, once started.
    private(set) var format: AVAudioFormat?

    private static func defaultOutputUID() throws -> String {
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)

        var status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        guard status == noErr else { throw TapError.failed("default output device", status) }

        var uid = "" as CFString
        var uidSize = UInt32(MemoryLayout<CFString>.size)
        address.mSelector = kAudioDevicePropertyDeviceUID
        status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &uidSize, &uid)
        guard status == noErr else { throw TapError.failed("output device UID", status) }

        return uid as String
    }

    /// Starts listening to everything `owner` plays through, handing each
    /// buffer to `onAudio` **on the audio thread**. Whatever it does must be
    /// cheap and must not hop actors.
    ///
    /// `owner` is the process the Floor named, but the sound often comes from a
    /// descendant of it — a browser plays through a helper. Every audio process
    /// in that tree is tapped together, so whichever one is playing is heard
    /// without having to guess which, and nothing outside the application is.
    func start(owner: pid_t, onAudio: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws {
        let objects = AudioProcesses.objects(ownedBy: owner)
        guard objects.isEmpty == false else { throw TapError.processHasNoAudio(owner) }

        // A mono mixdown, because the transcriber wants mono anyway — one fewer
        // conversion between the tap and the words.
        let description = CATapDescription(monoMixdownOfProcesses: objects)
        description.uuid = UUID()
        description.isPrivate = true

        var status = AudioHardwareCreateProcessTap(description, &tapID)
        guard status == noErr else { throw TapError.failed("create process tap", status) }

        // A tap is read through a device, so it is wrapped in a private
        // aggregate that nothing else on the machine can see or select.
        let outputUID = try Self.defaultOutputUID()
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Lyrify Live Captions",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: description.uuid.uuidString,
            ]],
        ]
        status = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID)
        guard status == noErr else { throw TapError.failed("create aggregate device", status) }

        var streamDescription = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        status = AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &streamDescription)
        guard status == noErr, let tapFormat = AVAudioFormat(streamDescription: &streamDescription)
        else { throw TapError.failed("tap format", status) }
        format = tapFormat

        status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, nil) {
            _, input, _, _, _ in
            guard let buffer = AVAudioPCMBuffer(pcmFormat: tapFormat, bufferListNoCopy: input)
            else { return }
            onAudio(buffer)
        }
        guard status == noErr, let procID else {
            throw TapError.failed("create IO proc", status)
        }

        status = AudioDeviceStart(aggregateID, procID)
        guard status == noErr else { throw TapError.failed("start device", status) }
    }

    /// Stops listening and gives every Core Audio object back. Safe to call
    /// when never started, and safe to call twice.
    func stop() {
        if let procID {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
            self.procID = nil
        }
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
        format = nil
    }

    deinit { stop() }
}

@available(macOS 14.2, *)
extension ProcessAudioTap {
    /// Asks macOS for permission to record system audio, and answers whether it
    /// was given.
    ///
    /// Asks by *trying*: there is no public way to read this permission's state,
    /// so the only honest question is whether a tap can be made.
    ///
    /// The tap is described globally rather than over an empty list of
    /// processes. An empty mixdown captures nothing by construction, and macOS
    /// lets it through without asking — which made the first version of this
    /// answer yes to a listener who had just said no. Nothing is ever captured
    /// through it regardless: no device is built behind it and no IO proc is
    /// attached, and it is destroyed on the next line.
    static func hasPermission() -> Bool {
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.uuid = UUID()
        description.isPrivate = true

        var tapID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateProcessTap(description, &tapID)

        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
        }
        return status == noErr
    }
}
