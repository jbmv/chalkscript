#if os(macOS)
import CoreServices
import Foundation

/// Calls `onChange` on the main queue when anything in a folder or below it changes, through
/// FSEvents, so that a document changed by another program is read again.
///
/// Changes that arrive within `latency` seconds of one another are reported once.
final class FolderWatcher {
    private final class Box: Sendable {
        let onChange: @MainActor () -> Void
        init(_ onChange: @escaping @MainActor () -> Void) { self.onChange = onChange }
    }

    private var stream: FSEventStreamRef?
    private let box: Box

    init?(folder: URL, latency: Double = 0.15, onChange: @escaping @MainActor () -> Void) {
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
    }

    func stop() {
        guard let s = stream else { return }
        FSEventStreamStop(s)
        FSEventStreamInvalidate(s)
        FSEventStreamRelease(s)
        stream = nil
    }

    deinit { stop() }
}
#endif
