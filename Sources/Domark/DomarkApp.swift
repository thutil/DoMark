import AppKit
import SwiftUI

@main
struct DomarkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = DocumentStore.shared
    @State private var find = FindSession.shared

    var body: some Scene {
        Window("Domark", id: "main") {
            ContentView()
                .environment(store)
                .environment(find)
        }
        .defaultSize(width: 1060, height: 780)
        .windowToolbarStyle(.unified)
        .commands { DomarkCommands(store: store, find: find) }

        Settings {
            SettingsView()
        }
    }
}

struct DomarkCommands: Commands {
    let store: DocumentStore
    let find: FindSession
    @AppStorage(FontSize.key) private var baseFontSize: Double = Theme.defaultBase
    @AppStorage(ViewModeSetting.key) private var modeRaw: String = ViewMode.preview.rawValue
    @AppStorage(AppearanceSetting.key) private var appearanceRaw: String = AppearanceSetting.system.rawValue

    var body: some Commands {
        // Single-document app — there is no New
        CommandGroup(replacing: .newItem) {
            Button("Open File…") { store.showOpenPanel() }
                .keyboardShortcut("o")
            Button("Open Folder…") { store.showOpenFolderPanel() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save") { store.save() }
                .keyboardShortcut("s")
                .disabled(!store.isDirty)

            Button("Reload") { store.refresh() }
                .keyboardShortcut("r")
                .disabled(store.url == nil)

            Divider()

            Button("Close") { store.close() }
                .keyboardShortcut("w", modifiers: [.command, .shift])
                .disabled(store.url == nil && store.folder == nil)
        }

        CommandGroup(after: .textEditing) {
            Divider()
            Button("Find…") { startFind() }
                .keyboardShortcut("f")
            Button("Find Next") { stepFind(1) }
                .keyboardShortcut("g")
            Button("Find Previous") { stepFind(-1) }
                .keyboardShortcut("g", modifiers: [.command, .shift])
        }

        CommandGroup(after: .toolbar) {
            ForEach(Array(ViewMode.allCases.enumerated()), id: \.element) { index, mode in
                Button(mode.label) { modeRaw = mode.rawValue }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [.command, .control])
            }
            Divider()
            ForEach(AppearanceSetting.allCases, id: \.self) { setting in
                Button(setting.label) { appearanceRaw = setting.rawValue }
            }
            Divider()
            Button("Actual Size") { baseFontSize = Theme.defaultBase }
                .keyboardShortcut("0")
            Button("Bigger") { baseFontSize = FontSize.clamp(baseFontSize + 1) }
                .keyboardShortcut("+")
            Button("Smaller") { baseFontSize = FontSize.clamp(baseFontSize - 1) }
                .keyboardShortcut("-")
            Divider()
            Button("Next File") { store.step(1) }
                .keyboardShortcut("]")
                .disabled(!store.canStep)
            Button("Previous File") { store.step(-1) }
                .keyboardShortcut("[")
                .disabled(!store.canStep)
            Divider()
        }
    }

    // MARK: - Find

    private var mode: ViewMode { ViewMode(rawValue: modeRaw) ?? .preview }

    /// There are two find bars in this app — NSTextView's inside the editor and our own over
    /// the preview. The menu item owns ⌘F once it exists, so it has to route the key itself.
    private var editorIsFocused: Bool {
        if let textView = NSApp.keyWindow?.firstResponder as? NSTextView {
            // Our own find field is backed by a field editor, which is an NSTextView too —
            // typing in it must not make ⌘F jump over to the editor pane
            return !textView.isFieldEditor
        }
        return mode == .editor
    }

    private func startFind() {
        if editorIsFocused {
            forwardToEditor(.showFindInterface)
        } else {
            find.present()
        }
    }

    private func stepFind(_ delta: Int) {
        if editorIsFocused {
            forwardToEditor(delta > 0 ? .nextMatch : .previousMatch)
        } else {
            find.step(delta)
        }
    }

    /// NSTextView reads the action off the sender's tag, so the responder chain needs a sender carrying one
    private func forwardToEditor(_ action: NSTextFinder.Action) {
        let sender = NSMenuItem()
        sender.tag = action.rawValue
        NSApp.sendAction(#selector(NSTextView.performTextFinderAction(_:)), to: nil, from: sender)
    }
}
