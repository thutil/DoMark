import Foundation
import Observation

struct RecentItem: Codable, Identifiable, Hashable {
    let url: URL
    let isFolder: Bool

    var id: URL { url }
    var name: String { url.lastPathComponent }
    var symbol: String { isFolder ? "folder" : "doc.text" }

    /// `~/Desktop/DoMark` rather than `/Users/someone/Desktop/DoMark`
    var displayPath: String {
        (url.deletingLastPathComponent().path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath
    }

    /// Menu titles are a single line, so two `README.md` from different projects can only be
    /// told apart by adding the folder they live in — and only when there really is a clash
    func menuTitle(among items: [RecentItem]) -> String {
        let clashes = items.contains { $0 != self && $0.name == name }
        return clashes ? "\(name) — \(url.deletingLastPathComponent().lastPathComponent)" : name
    }
}

/// Files and folders opened before, newest first, kept across launches.
/// The app is not sandboxed, so plain URLs stay valid and no security-scoped bookmarks are needed.
@MainActor
@Observable
final class RecentItems {
    static let key = "recentItems"
    static let limit = 10

    private(set) var items: [RecentItem]

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        items = defaults.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode([RecentItem].self, from: $0) } ?? []
    }

    func note(_ url: URL, isFolder: Bool) {
        // Standardized so `/a/../b.md` and `/b.md` count as one entry
        let item = RecentItem(url: url.standardizedFileURL, isFolder: isFolder)
        var updated = items.filter { $0.url != item.url }
        updated.insert(item, at: 0)
        set(Array(updated.prefix(Self.limit)))
    }

    func remove(_ item: RecentItem) {
        set(items.filter { $0.url != item.url })
    }

    func clear() {
        set([])
    }

    private func set(_ updated: [RecentItem]) {
        // Reopening the newest item changes nothing — don't redraw the menu for it
        guard updated != items else { return }
        items = updated
        defaults.set(try? JSONEncoder().encode(updated), forKey: Self.key)
    }
}
