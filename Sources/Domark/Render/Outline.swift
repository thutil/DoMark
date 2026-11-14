import Foundation

/// The document's table of contents — what the outline panel lists.
///
/// Only H1–H3: an outline is for getting the shape of a document, and H4 and below turn it
/// into a second copy of the page. A document with a single H1 is almost always using it as
/// its title, so that one becomes the panel's title and the list starts at H2 instead of
/// indenting every line under it.
struct Outline: Equatable, Sendable {
    struct Item: Identifiable, Equatable, Sendable {
        /// Position in the list — two headings can share a block (both inside one quote)
        let id: Int
        /// 0 for the shallowest level shown, so the view can indent without knowing the rule
        let depth: Int
        let title: String
        /// The top-level block to scroll to
        let blockID: Int
    }

    var title: String?
    var items: [Item] = []

    static let deepestLevel = 3

    init() {}

    init(blocks: [IdentifiedBlock]) {
        var headings: [(level: Int, title: String, blockID: Int)] = []

        // Same walk as Anchor.map: a heading inside a quote or a list scrolls to its container
        func visit(_ block: RenderBlock, id: Int) {
            switch block {
            case let .heading(level, text):
                let title = String(text.characters).trimmingCharacters(in: .whitespaces)
                if level <= Self.deepestLevel, !title.isEmpty {
                    headings.append((level, title, id))
                }
            case let .quote(children), let .aligned(_, children), let .details(_, children):
                for child in children { visit(child, id: id) }
            case let .list(_, _, items):
                for item in items {
                    for child in item.content { visit(child, id: id) }
                }
            default:
                break
            }
        }
        for item in blocks { visit(item.block, id: item.id) }

        if headings.count(where: { $0.level == 1 }) == 1,
           let index = headings.firstIndex(where: { $0.level == 1 }) {
            title = headings.remove(at: index).title
        }

        let shallowest = headings.map(\.level).min() ?? 1
        items = headings.enumerated().map { offset, heading in
            Item(id: offset, depth: heading.level - shallowest, title: heading.title, blockID: heading.blockID)
        }
    }

    /// The heading the reader is in: the last one that starts at or above the top of the page.
    /// Nil above the first heading — the intro is not part of any section.
    func current(topBlockID: Int?) -> Item.ID? {
        guard let topBlockID else { return nil }
        return items.last(where: { $0.blockID <= topBlockID })?.id
    }
}
