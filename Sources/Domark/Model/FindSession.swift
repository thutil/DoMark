import Foundation
import Observation

/// Find-in-preview state: the query, where we are in the match list, and the highlighted
/// blocks the preview draws.
///
/// The scan runs off the main thread and its result is cached, so typing in the field costs
/// one background pass and ⌘G costs almost nothing.
@MainActor
@Observable
final class FindSession {
    static let shared = FindSession()

    private(set) var isPresented = false

    /// A new needle always starts over at the first match
    var query: String = "" {
        didSet { if query != oldValue { index = 0 } }
    }

    var isCaseSensitive = false {
        didSet { if isCaseSensitive != oldValue { index = 0 } }
    }

    /// Which match is the current one, 0-based
    private(set) var index = 0
    private(set) var matchCount = 0

    /// Bumped on every ⌘F so the field takes focus again even when the bar is already open
    private(set) var focusToken = 0

    /// What the preview should draw, and which document revision it was built from
    private(set) var blocks: [IdentifiedBlock] = []
    private(set) var blocksVersion = -1
    private(set) var currentBlockID: Int?

    /// Highlights are only drawn while the bar is up — a dismissed bar leaves a clean page
    var isHighlighting: Bool { isPresented && !query.isEmpty }

    @ObservationIgnored private var scan: Scan?
    @ObservationIgnored private var scanTask: Task<Void, Never>?

    /// Everything a scan depends on. The current match is deliberately not part of it —
    /// moving between matches reuses the scan instead of redoing it.
    private struct ScanKey: Equatable {
        var version: Int
        var query: String
        var caseSensitive: Bool
        var theme: Theme
    }

    private struct Scan {
        var key: ScanKey
        var value: FindHighlighter.Highlighted
    }

    // MARK: - The bar

    func present() {
        isPresented = true
        focusToken += 1
    }

    func dismiss() {
        isPresented = false
        clearHighlights()
    }

    /// ⌘G / ⇧⌘G — wraps around, and brings the bar back when it was dismissed
    func step(_ delta: Int) {
        isPresented = true
        guard matchCount > 0 else { index = 0; return }
        index = ((index + delta) % matchCount + matchCount) % matchCount
    }

    // MARK: - Highlighting

    /// Called by the preview whenever the document, the query or the current match changed
    func update(blocks source: [IdentifiedBlock], version: Int, theme: Theme) {
        guard isHighlighting else {
            clearHighlights()
            return
        }

        let key = ScanKey(version: version, query: query, caseSensitive: isCaseSensitive, theme: theme)
        if let scan, scan.key == key {
            // Only the current match moved — repaint the one block that holds it
            applyCurrent(scan)
            return
        }

        let query = query
        let caseSensitive = isCaseSensitive
        scanTask?.cancel()
        scanTask = Task { @MainActor [weak self] in
            // Scanning a long document is measured in hundreds of milliseconds — never on the main thread
            let scanned = await Task.detached(priority: .userInitiated) {
                FindHighlighter.scan(query: query, caseSensitive: caseSensitive, theme: theme, blocks: source)
            }.value
            guard !Task.isCancelled, let self, self.isHighlighting else { return }

            let scan = Scan(key: key, value: scanned)
            self.scan = scan
            self.matchCount = scanned.matchCount
            // The document (or the needle) changed under us — never point past the end of the list
            if self.index >= scanned.matchCount { self.index = 0 }
            self.applyCurrent(scan)
        }
    }

    private func applyCurrent(_ scan: Scan) {
        let marked = FindHighlighter.markCurrent(
            scan.value,
            current: index,
            query: query,
            caseSensitive: isCaseSensitive,
            theme: scan.key.theme
        )
        blocks = marked.blocks
        blocksVersion = scan.key.version
        currentBlockID = marked.currentBlockID
    }

    private func clearHighlights() {
        scanTask?.cancel()
        scanTask = nil
        scan = nil
        blocks = []
        blocksVersion = -1
        currentBlockID = nil
        matchCount = 0
    }
}
