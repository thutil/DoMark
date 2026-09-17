import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Applied before the first window is drawn, otherwise a dark-mode launch
    /// flashes light for a frame
    func applicationWillFinishLaunching(_ notification: Notification) {
        AppearanceSetting.current.apply()
    }

    /// Receives files from Finder (double-click) and from `open -a Domark.app file.md`
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first(where: DocumentStore.isReadable) ?? urls.first else { return }
        DocumentStore.shared.open(url)
    }

    /// Never let the app quit and silently throw away unsaved work
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        DocumentStore.shared.confirmDiscard() ? .terminateNow : .terminateCancel
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
