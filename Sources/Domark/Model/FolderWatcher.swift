import CoreServices
import Foundation

/// Watches a whole folder tree with **one FSEvents stream** and calls `onChange` when something inside it changes.
///
/// One `O_EVTONLY` fd per directory looked simpler, but a GUI app's soft limit is 256 descriptors:
/// a big project ran out, and then even opening a file failed with "Too many open files".
/// FSEvents is recursive and costs no descriptors per directory.
@MainActor
final class FolderWatcher {
    // nonisolated(unsafe) so deinit can tear it down; only touched on the main actor otherwise
    nonisolated(unsafe) private var stream: FSEventStreamRef?
    private let onChange: () -> Void
    private let root: String

    init(url: URL, onChange: @escaping () -> Void) {
        self.onChange = onChange
        // FSEvents reports resolved paths (/private/var/…, no symlinks) — compare against the same form
        root = url.resolvingSymlinksInPath().path(percentEncoded: false)

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
            let changed = (unsafeBitCast(paths, to: NSArray.self) as? [String]) ?? []
            MainActor.assumeIsolated { watcher.handle(Array(changed.prefix(count))) }
        }
        guard let stream = FSEventStreamCreate(
            nil, callback, &context,
            [url.path(percentEncoded: false)] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.2, // latency: FSEvents coalesces bursts within this window
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer)
        ) else { return }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    deinit {
        // the stream holds an unretained pointer to self — it must not outlive us
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    /// Skip churn the sidebar never shows (git, node_modules, build output) — otherwise every build triggers a rescan
    private func handle(_ paths: [String]) {
        let relevant = paths.contains { path in
            let inside = path.hasPrefix(root) ? String(path.dropFirst(root.count)) : path
            return !inside.split(separator: "/").contains { part in
                part.hasPrefix(".") || FolderScanner.ignored.contains(String(part))
            }
        }
        if relevant { onChange() }
    }
}
