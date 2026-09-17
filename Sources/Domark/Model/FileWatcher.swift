import Darwin
import Dispatch
import Foundation

/// Watches a single file and calls `onChange` when its contents change.
///
/// Most editors (vim, VS Code, TextEdit) save atomically: they write a temp file and
/// `rename()` over the original, so the old file descriptor still points at a deleted inode.
/// That is why we **reopen the fd from the same path after every event** — otherwise it fires once and then goes silent.
@MainActor
final class FileWatcher {
    private let url: URL
    private let onChange: () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var descriptor: CInt = -1
    private var pending: Task<Void, Never>?

    init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
        arm()
    }

    deinit {
        pending?.cancel()
        source?.cancel()
    }

    func stop() {
        pending?.cancel()
        pending = nil
        source?.cancel() // the cancel handler closes the fd
        source = nil
        descriptor = -1
    }

    /// Reopen the fd and attach a DispatchSource. Safe to call repeatedly.
    private func arm() {
        stop()

        let fd = Darwin.open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        descriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .delete, .rename, .revoke],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor in self?.schedule() }
        }
        source.setCancelHandler { Darwin.close(fd) }
        source.resume()
        self.source = source
    }

    private func schedule() {
        pending?.cancel()
        pending = Task { @MainActor [weak self] in
            // coalesce bursts of events into one
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled, let self else { return }

            // during an atomic replace the file can vanish for a moment — wait and retry
            if !FileManager.default.fileExists(atPath: self.url.path) {
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
            }

            self.arm()
            self.onChange()
        }
    }
}
