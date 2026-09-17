import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

/// How the document is displayed
enum ViewMode: String, CaseIterable {
    case preview, split, editor

    var label: String {
        switch self {
        case .preview: "Preview"
        case .split: "Split"
        case .editor: "Edit"
        }
    }

    var symbol: String {
        switch self {
        case .preview: "book"
        case .split: "rectangle.split.2x1"
        case .editor: "square.and.pencil"
        }
    }

    var showsPreview: Bool { self != .editor }
}

@MainActor
@Observable
final class DocumentStore {
    static let shared = DocumentStore()

    private(set) var url: URL?
    private(set) var blocks: [IdentifiedBlock] = []
    /// Bumped on every re-render. Comparing thousands of AttributedStrings to notice a change
    /// is itself expensive, so everything downstream watches this Int instead.
    private(set) var renderVersion = 0
    /// Heading slug → the block a `#heading` link scrolls to
    private(set) var anchors: [String: Int] = [:]
    private(set) var loadError: String?

    /// The text being edited. The preview renders from this, not from disk.
    var draft: String = "" {
        didSet { if draft != oldValue { scheduleRender() } }
    }

    /// Last known contents on disk — compared against `draft` to detect unsaved work
    @ObservationIgnored private var savedSource = ""
    private(set) var isDirty = false

    /// New contents from disk we refuse to apply because the user has unsaved edits
    private(set) var externalChange: String?

    /// The folder being browsed (nil = a single file is open)
    private(set) var folder: URL?
    private(set) var tree: [FileNode] = []

    /// Sidebar selection — assigning to it opens that file
    var selection: URL? {
        didSet {
            guard !isAdjustingSelection else { return }
            guard let selection, selection != url, !FolderScanner.isDirectory(selection) else { return }
            guard confirmDiscard() else {
                isAdjustingSelection = true
                self.selection = oldValue
                isAdjustingSelection = false
                return
            }
            openFile(selection)
        }
    }

    /// The theme is baked into the AttributedStrings at parse time, so a font-size change needs a re-render
    var theme: Theme = Theme(base: Theme.defaultBase) {
        didSet { if theme != oldValue { renderNow() } }
    }

    @ObservationIgnored private var fileWatcher: FileWatcher?
    /// Watches every directory in the tree, not just the root, so adds/removes inside subfolders show up immediately
    @ObservationIgnored private var folderWatchers: [URL: FileWatcher] = [:]
    @ObservationIgnored private var renderTask: Task<Void, Never>?
    @ObservationIgnored private var isAdjustingSelection = false

    var title: String {
        url?.deletingPathExtension().lastPathComponent
            ?? folder?.lastPathComponent
            ?? "Domark"
    }

    static let readableTypes: [UTType] = [
        UTType(filenameExtension: "md") ?? .plainText,
        UTType(filenameExtension: "markdown") ?? .plainText,
        UTType(filenameExtension: "mdown") ?? .plainText,
        UTType(filenameExtension: "mkd") ?? .plainText,
        .plainText,
    ]

    nonisolated static func isReadable(_ url: URL) -> Bool {
        ["md", "markdown", "mdown", "mkd", "mdx", "txt", "text"]
            .contains(url.pathExtension.lowercased())
    }

    // MARK: - Opening

    /// Accepts a file or a folder — the single entry point for Finder, drag & drop and the open panel
    func open(_ url: URL) {
        guard confirmDiscard() else { return }
        if FolderScanner.isDirectory(url) {
            openFolder(url)
        } else {
            openFile(url)
        }
    }

    func openFile(_ url: URL) {
        self.url = url
        if selection != url {
            isAdjustingSelection = true
            selection = url
            isAdjustingSelection = false
        }
        externalChange = nil
        reload()
        fileWatcher = FileWatcher(url: url) { [weak self] in self?.reload() }
    }

    func openFolder(_ url: URL) {
        folder = url
        rescan()
        // Open the first file right away so the window is never blank
        if let first = FolderScanner.flatten(tree).first {
            openFile(first)
        } else {
            closeDocument()
        }
    }

    func rescan() {
        guard let folder else { return }
        let result = FolderScanner.scan(folder)
        // Only assign when something actually changed, otherwise the sidebar flickers on every event
        if tree != result.tree { tree = result.tree }
        syncFolderWatchers(result.directories)
    }

    /// Attach/detach watchers to match the current set of directories — called after every scan
    private func syncFolderWatchers(_ directories: [URL]) {
        let wanted = Set(directories)
        for (url, watcher) in folderWatchers where !wanted.contains(url) {
            watcher.stop()
            folderWatchers[url] = nil
        }
        for url in wanted where folderWatchers[url] == nil {
            folderWatchers[url] = FileWatcher(url: url) { [weak self] in self?.rescan() }
        }
    }

    // MARK: - Reading and writing

    func reload() {
        guard let url else { return }

        let text: String
        do {
            text = try String(contentsOf: url, encoding: .utf8)
        } catch {
            // The file may not be UTF-8 — fall back to another encoding
            if let fallback = try? String(contentsOf: url, encoding: .isoLatin1) {
                text = fallback
            } else {
                loadError = error.localizedDescription
                draft = ""
                savedSource = ""
                isDirty = false
                renderNow()
                return
            }
        }
        loadError = nil

        // Disk matches what we already know — nothing to do.
        // The case that matters: the echo of our own save. Without this guard it would clobber whatever was typed after saving.
        guard text != savedSource else { return }

        // Someone changed the file elsewhere while we have unsaved edits — never clobber, let the user decide
        guard !isDirty else {
            externalChange = text
            return
        }

        savedSource = text
        draft = text
        isDirty = false
        renderNow()
    }

    func save() {
        guard let url, isDirty else { return }
        do {
            try draft.write(to: url, atomically: true, encoding: .utf8)
            savedSource = draft
            isDirty = false
            externalChange = nil
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn’t Save"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    /// ⌘R — re-read the file, and rescan the file list too when a folder is open
    func refresh() {
        rescan()
        guard confirmDiscard() else { return }
        savedSource = "" // force reload() to actually re-read
        isDirty = false
        reload()
    }

    // MARK: - Conflicts with outside edits

    func acceptExternalChange() {
        guard let text = externalChange else { return }
        savedSource = text
        draft = text
        isDirty = false
        externalChange = nil
        renderNow()
    }

    func keepMyChanges() {
        guard let text = externalChange else { return }
        // Disk now holds that text, but we keep ours — so the draft stays unsaved
        savedSource = text
        isDirty = draft != text
        externalChange = nil
    }

    /// Asks before discarding unsaved work. Returns true when it is safe to continue.
    @discardableResult
    func confirmDiscard() -> Bool {
        guard isDirty, let url else { return true }
        let alert = NSAlert()
        alert.messageText = "Unsaved changes in “\(url.lastPathComponent)”"
        alert.informativeText = "Your edits will be lost if you continue."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don’t Save")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn: save(); return !isDirty
        case .alertSecondButtonReturn: return true
        default: return false
        }
    }

    // MARK: - Stepping between files

    var siblings: [URL] { FolderScanner.flatten(tree) }

    func step(_ offset: Int) {
        let files = siblings
        guard !files.isEmpty else { return }
        let current = url.flatMap { files.firstIndex(of: $0) } ?? -1
        let next = (current + offset + files.count) % files.count
        selection = files[next]
    }

    var canStep: Bool { siblings.count > 1 }

    // MARK: - Closing

    func closeDocument() {
        fileWatcher?.stop()
        fileWatcher = nil
        url = nil
        isAdjustingSelection = true
        selection = nil
        isAdjustingSelection = false
        draft = ""
        savedSource = ""
        isDirty = false
        externalChange = nil
        blocks = []
        loadError = nil
    }

    func close() {
        guard confirmDiscard() else { return }
        closeDocument()
        folderWatchers.values.forEach { $0.stop() }
        folderWatchers.removeAll()
        folder = nil
        tree = []
    }

    // MARK: - Open panel

    func showOpenPanel() {
        guard confirmDiscard() else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = Self.readableTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Open"
        if panel.runModal() == .OK, let picked = panel.url { openFile(picked) }
    }

    func showOpenFolderPanel() {
        guard confirmDiscard() else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Open Folder"
        if panel.runModal() == .OK, let picked = panel.url { openFolder(picked) }
    }

    // MARK: - Rendering

    /// Re-parsing on every keystroke is wasteful — coalesce into one parse once typing pauses
    private func scheduleRender() {
        isDirty = draft != savedSource
        render(debounced: true)
    }

    private func renderNow() {
        render(debounced: false)
    }

    /// Parsing a long document — building an AttributedString for every inline run — is the
    /// heaviest thing this app does. Off the main thread it no longer freezes typing,
    /// zooming or scrolling while it runs.
    private func render(debounced: Bool) {
        let source = draft
        let theme = theme
        let baseURL = url

        renderTask?.cancel()
        renderTask = Task { @MainActor [weak self] in
            if debounced {
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { return }
            }
            let parsed = await Task.detached(priority: .userInitiated) {
                let blocks = BlockBuilder.parse(source: source, theme: theme, baseURL: baseURL).identified
                return (blocks, Anchor.map(for: blocks))
            }.value
            guard !Task.isCancelled, let self else { return }
            self.blocks = parsed.0
            self.anchors = parsed.1
            self.renderVersion += 1
        }
    }
}
