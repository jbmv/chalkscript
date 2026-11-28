#if os(macOS)
import CoreServices
import Foundation

/// Calls `onChange` on the main queue when anything in a folder or below it changes, through
/// FSEvents, so that a document changed by another program is read again.
///
/// Changes that arrive within `latency` seconds of one another are reported once.
///
/// FSEvents reports a change after a delay that the system sets and that grows when the machine is
/// busy: measured here, from 0.2 to more than 10 seconds for a file written by another program,
/// while a kqueue watch of the same folder fires within 5 milliseconds. So the folder's documents
/// are also compared every `poll` seconds, by file, modification time and size, and a difference
/// is reported as a change too. A change is then seen within about `poll` seconds, whichever of the
/// two finds it first, and a change reported by both is read twice, which costs nothing.
final class FolderWatcher {
    private final class Box: Sendable {
        let onChange: @MainActor () -> Void
        init(_ onChange: @escaping @MainActor () -> Void) { self.onChange = onChange }
    }

    private var stream: FSEventStreamRef?
    private var timer: DispatchSourceTimer?
    private let box: Box

    /// What the folder's documents are: each file with its modification time and size.
    static func signature(of folder: URL) -> [String: [Int64]] {
        var out: [String: [Int64]] = [:]
        for (name, url) in ProjectFolder.scan(folder) {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let time = values?.contentModificationDate.map { Int64($0.timeIntervalSinceReferenceDate * 1_000_000) } ?? 0
            out[name] = [time, Int64(values?.fileSize ?? 0)]
        }
        return out
    }

    init?(folder: URL, latency: Double = 0.15, poll: Double = 0.5, onChange: @escaping @MainActor () -> Void) {
        box = Box(onChange)
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(box).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let box = Unmanaged<Box>.fromOpaque(info).takeUnretainedValue()
            // The stream is scheduled on the main queue.
            MainActor.assumeIsolated { box.onChange() }
        }
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        guard let s = FSEventStreamCreate(
            nil, callback, &context, [folder.path] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags)
        else { return nil }
        stream = s
        FSEventStreamSetDispatchQueue(s, DispatchQueue.main)
        guard FSEventStreamStart(s) else {
            FSEventStreamInvalidate(s)
            FSEventStreamRelease(s)
            stream = nil
            return nil
        }
        // What changed between the folder being read and the stream starting is in neither
        // report, so the folder is read once more, and then each time its documents differ.
        var known = Self.signature(of: folder)
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(deadline: .now() + poll, repeating: poll, leeway: .milliseconds(Int(poll * 250)))
        let box = box
        timer.setEventHandler {
            let now = Self.signature(of: folder)
            guard now != known else { return }
            known = now
            MainActor.assumeIsolated { box.onChange() }
        }
        timer.resume()
        self.timer = timer
        DispatchQueue.main.async { MainActor.assumeIsolated { box.onChange() } }
    }

    func stop() {
        timer?.cancel()
        timer = nil
        guard let s = stream else { return }
        FSEventStreamStop(s)
        FSEventStreamInvalidate(s)
        FSEventStreamRelease(s)
        stream = nil
    }

    deinit { stop() }
}
#endif
