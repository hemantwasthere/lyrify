import CoreAudio
import Darwin
import Foundation

/// Finds the processes an application actually makes sound through.
///
/// The Floor names an application by its main process, but that is frequently
/// not the process making the noise. A browser plays through a helper: with a
/// video playing in Arc, the Floor reported pid 652 while the audio came from
/// pid 1412, a "Browser Helper" whose parent was 652. Tapping what the Floor
/// named captured silence, which is exactly why Live Captions showed nothing —
/// see `docs/findings/2026-08-03-system-audio-captions.md`.
///
/// So the Owner is treated as a *tree*: the process the Floor named, and any
/// descendant of it. Tapping all of them at once covers whichever one is
/// playing without having to guess, and without widening to the machine.
@available(macOS 14.2, *)
enum AudioProcesses {
    /// Every Core Audio process object belonging to `owner` or to one of its
    /// descendants.
    ///
    /// Empty when the application has made no sound at all — Core Audio only
    /// knows about a process once it has played something.
    static func objects(ownedBy owner: pid_t) -> [AudioObjectID] {
        allProcessObjects().filter { object in
            guard let pid = pid(of: object) else { return false }
            return pid == owner || isDescendant(pid, of: owner)
        }
    }

    private static func allProcessObjects() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)

        var size: UInt32 = 0
        guard
            AudioObjectGetPropertyDataSize(
                AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr
        else { return [] }

        var objects = [AudioObjectID](
            repeating: AudioObjectID(kAudioObjectUnknown),
            count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &objects) == noErr
        else { return [] }

        return objects
    }

    private static func pid(of object: AudioObjectID) -> pid_t? {
        var pid: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)

        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &pid) == noErr
        else { return nil }
        return pid
    }

    /// Whether `pid` sits anywhere beneath `ancestor` in the process tree.
    ///
    /// Bounded rather than looping until it reaches launchd, so a cycle or a
    /// reparented orphan cannot spin here. Browser helpers are one level down;
    /// a handful of steps is generous.
    private static func isDescendant(_ pid: pid_t, of ancestor: pid_t) -> Bool {
        var current = pid
        for _ in 0..<8 {
            guard let parent = parent(of: current), parent > 1 else { return false }
            if parent == ancestor { return true }
            current = parent
        }
        return false
    }

    private static func parent(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]

        let result = sysctl(&name, UInt32(name.count), &info, &size, nil, 0)
        guard result == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }
}
