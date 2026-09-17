import SwiftUI

struct ContentView: View {
    @Environment(DocumentStore.self) private var store
    @Environment(FindSession.self) private var find
    @AppStorage(FontSize.key) private var baseFontSize: Double = Theme.defaultBase
    @AppStorage(ViewModeSetting.key) private var modeRaw: String = ViewMode.preview.rawValue
    @AppStorage(AppearanceSetting.key) private var appearanceRaw: String = AppearanceSetting.system.rawValue
    @AppStorage(FontSetting.proseKey) private var proseFamily: String = FontSetting.defaultProse
    @AppStorage(FontSetting.codeKey) private var codeFamily: String = FontSetting.defaultCode

    @State private var isTargeted = false

    private var theme: Theme { Theme(base: baseFontSize, prose: proseFamily, code: codeFamily) }
    private var mode: ViewMode { ViewMode(rawValue: modeRaw) ?? .preview }

    var body: some View {
        @Bindable var store = store
        // Highlighted blocks are produced in the background; until they arrive — and whenever
        // the bar is down — the page draws the store's own blocks unchanged
        let shown = find.blocksVersion == store.renderVersion ? find.blocks : store.blocks

        Group {
            if let folder = store.folder {
                NavigationSplitView {
                    SidebarView(
                        tree: store.tree,
                        folderName: folder.lastPathComponent,
                        selection: $store.selection
                    )
                } detail: {
                    detail(shown)
                }
            } else {
                detail(shown)
            }
        }
        .frame(minWidth: 560, minHeight: 360)
        .navigationTitle(store.title)
        .navigationSubtitle(subtitle)
        .navigationDocument(store.url ?? URL(fileURLWithPath: "/"))
        .toolbar { toolbar }
        .overlay(alignment: .bottomTrailing) { zoomPill }
        .background(DocumentEditedMarker(isEdited: store.isDirty))
        .dropDestination(for: URL.self) { urls, _ in
            // Accepts both .md files and folders
            guard let url = urls.first(where: { DocumentStore.isReadable($0) || FolderScanner.isDirectory($0) })
            else { return false }
            store.open(url)
            return true
        } isTargeted: { isTargeted = $0 }
        // The theme is baked into the AttributedStrings at parse time, so a size or typeface
        // change must trigger a re-render
        .onChange(of: theme, initial: true) { store.theme = theme }
        .onChange(of: appearanceRaw, initial: true) {
            (AppearanceSetting(rawValue: appearanceRaw) ?? .system).apply()
        }
        // One trigger for every input the highlighter depends on
        .onChange(of: findInputs, initial: true) {
            find.update(blocks: store.blocks, version: store.renderVersion, theme: theme)
        }
        // The find bar belongs to the preview; the editor has NSTextView's own
        .onChange(of: modeRaw) { if !mode.showsPreview { find.dismiss() } }
    }

    /// Everything the highlighted blocks are derived from, in one comparable value
    private var findInputs: FindInputs {
        FindInputs(
            version: store.renderVersion,
            query: find.query,
            index: find.index,
            caseSensitive: find.isCaseSensitive,
            isPresented: find.isPresented,
            theme: theme
        )
    }

    @ViewBuilder
    private func detail(_ shown: [IdentifiedBlock]) -> some View {
        if store.url == nil {
            EmptyStateView(
                theme: theme,
                isTargeted: isTargeted,
                onOpenFile: { store.showOpenPanel() },
                onOpenFolder: { store.showOpenFolderPanel() }
            )
        } else if let loadError = store.loadError {
            ContentUnavailableView("Couldn’t Open File", systemImage: "exclamationmark.triangle", description: Text(loadError))
        } else {
            VStack(spacing: 0) {
                if store.externalChange != nil { conflictBanner }
                panes(shown)
            }
        }
    }

    @ViewBuilder
    private func panes(_ shown: [IdentifiedBlock]) -> some View {
        @Bindable var store = store

        switch mode {
        case .preview:
            preview(shown)
        case .editor:
            editor
        case .split:
            HSplitView {
                editor
                    .frame(minWidth: 260)
                preview(shown)
                    .frame(minWidth: 300)
            }
        }
    }

    private var editor: some View {
        @Bindable var store = store
        return SourceEditorView(text: $store.draft, theme: theme)
            // An explicit document surface: without it the pane is transparent and
            // borrows whatever the window paints, which reads wrong in dark mode.
            .background(Color(nsColor: .textBackgroundColor))
    }

    private func preview(_ shown: [IdentifiedBlock]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: theme.blockSpacing) {
                    ForEach(shown) { item in
                        BlockView(block: item.block, theme: theme)
                            .equatable()
                            .id(item.id) // the anchor the find bar scrolls to
                    }
                }
                .frame(maxWidth: theme.contentWidth, alignment: .leading)
                .padding(.horizontal, mode == .split ? theme.base * 1.6 : theme.pagePadding)
                .padding(.vertical, theme.pagePadding)
                .frame(maxWidth: .infinity) // centre the column in the window
            }
            // A new file should start at the top, not inherit the previous file's scroll offset
            .id(store.url)
            // Both are needed: stepping onto a hit in another block changes the id, while
            // stepping between two hits inside the same block only changes the index.
            .onChange(of: find.currentBlockID) { reveal(find.currentBlockID, with: proxy) }
            .onChange(of: find.index) { reveal(find.currentBlockID, with: proxy) }
            .environment(\.openURL, OpenURLAction { url in
                guard let target = Anchor.target(of: url) else { return .systemAction }
                if let id = Anchor.block(for: target, in: store.anchors) {
                    reveal(id, with: proxy, anchor: .top)
                }
                // A link to a heading that is not there does nothing — it must never
                // escape to the browser as a made-up URL
                return .handled
            })
        }
        .textSelection(.enabled)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(alignment: .top) {
            if find.isPresented {
                FindBarView(find: find, theme: theme)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .padding(6)
                    .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.18), value: isTargeted)
        .animation(.snappy(duration: 0.2), value: find.isPresented)
    }

    /// Find lands a match in the middle of the page; a heading belongs at the top of it
    private func reveal(_ blockID: Int?, with proxy: ScrollViewProxy, anchor: UnitPoint = .center) {
        guard let blockID else { return }
        withAnimation(.snappy(duration: 0.25)) {
            proxy.scrollTo(blockID, anchor: anchor)
        }
    }

    /// The file changed on disk while the user has unsaved edits — let them choose, never silently clobber either side
    private var conflictBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("This file changed on disk while you were editing")
                .font(.system(size: 12))
            Spacer(minLength: 8)
            Button("Use Disk Version") { store.acceptExternalChange() }
            Button("Keep Mine") { store.keepMyChanges() }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .background(.orange.opacity(0.14))
        .overlay(alignment: .bottom) { Divider() }
    }

    private var subtitle: String {
        guard let url = store.url else { return "" }
        let dirty = store.isDirty ? " • Unsaved" : ""
        // With a folder open, show the path relative to it — shorter and easier to read
        if let folder = store.folder {
            let relative = url.path(percentEncoded: false)
                .replacingOccurrences(of: folder.path(percentEncoded: false), with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return relative + dirty
        }
        return url.deletingLastPathComponent().path(percentEncoded: false) + dirty
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if store.canStep {
            ToolbarItem(placement: .navigation) {
                Button { store.step(-1) } label: {
                    Label("Previous File", systemImage: "chevron.left")
                }
                .help("Previous file (⌘[)")
            }
            ToolbarItem(placement: .navigation) {
                Button { store.step(1) } label: {
                    Label("Next File", systemImage: "chevron.right")
                }
                .help("Next file (⌘])")
            }
        }

        ToolbarItem(placement: .principal) {
            Picker("Mode", selection: Binding(get: { mode }, set: { modeRaw = $0.rawValue })) {
                ForEach(ViewMode.allCases, id: \.self) { mode in
                    Label(mode.label, systemImage: mode.symbol).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(store.url == nil)
        }

        ToolbarItem(placement: .primaryAction) {
            Button { store.save() } label: {
                Label("Save", systemImage: "tray.and.arrow.down")
            }
            .disabled(!store.isDirty)
            .help("Save (⌘S)")
        }
        ToolbarSpacer(.fixed, placement: .primaryAction)
        ToolbarItem(placement: .primaryAction) {
            Button { store.showOpenFolderPanel() } label: {
                Label("Open Folder…", systemImage: "folder")
            }
            .help("Open folder (⇧⌘O)")
        }
        ToolbarItem(placement: .primaryAction) {
            Button { store.refresh() } label: {
                Label("Reload", systemImage: "arrow.clockwise")
            }
            .disabled(store.url == nil)
            .help("Reload (⌘R)")
        }
    }

    /// Floating font-size control, built with Tahoe's Liquid Glass
    @ViewBuilder
    private var zoomPill: some View {
        if store.url != nil, mode.showsPreview {
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: theme.base * 0.35) {
                    zoomButton("textformat.size.smaller", delta: -1)
                        .disabled(baseFontSize <= Theme.minBase)
                    Text("\(Int(baseFontSize))")
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 20)
                    zoomButton("textformat.size.larger", delta: 1)
                        .disabled(baseFontSize >= Theme.maxBase)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: Capsule())
            }
            .padding(18)
        }
    }

    private func zoomButton(_ symbol: String, delta: Double) -> some View {
        Button {
            baseFontSize = FontSize.clamp(baseFontSize + delta)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .frame(width: 22, height: 18)
        }
        .buttonStyle(.plain)
    }
}

/// The one place that knows how font size is stored and clamped, shared by the views and the commands
enum FontSize {
    static let key = "baseFontSize"
    static func clamp(_ value: Double) -> Double {
        min(max(value, Theme.minBase), Theme.maxBase)
    }
}

enum ViewModeSetting {
    static let key = "viewMode"
}

/// Watched as a single value so one `onChange` covers every input to the find highlighter
struct FindInputs: Equatable {
    var version: Int
    var query: String
    var index: Int
    var caseSensitive: Bool
    var isPresented: Bool
    var theme: Theme
}
