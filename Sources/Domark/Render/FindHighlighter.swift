import Foundation
import SwiftUI

/// Marks every occurrence of the find query inside the already-rendered blocks.
///
/// Searching the rendered text rather than the Markdown source is deliberate: the source
/// carries syntax the reader never sees (`**bold**`, link destinations), so a hit there could
/// land on a character that is not on the page. Walking RenderBlocks means what you see is what is found.
///
/// The work is split in two because the two inputs change at very different rates. The needle
/// changes once per keystroke; the *current* match changes on every ⌘G. Scanning the whole
/// document for each ⌘G would cost hundreds of milliseconds in a long file, so a scan is kept
/// and only the one block holding the current match is re-marked.
enum FindHighlighter {
    /// The result of one full scan: every match painted, none of them marked as current.
    struct Highlighted: Sendable {
        var blocks: [IdentifiedBlock]
        var matchCount: Int
        /// Parallel to `blocks`: how many matches come before that block
        var starts: [Int]

        static let empty = Highlighted(blocks: [], matchCount: 0, starts: [])
    }

    /// The expensive pass — run once per (document, query, appearance), off the main thread.
    static func scan(
        query: String,
        caseSensitive: Bool,
        theme: Theme,
        blocks: [IdentifiedBlock]
    ) -> Highlighted {
        guard !query.isEmpty else {
            return Highlighted(blocks: blocks, matchCount: 0, starts: Array(repeating: 0, count: blocks.count))
        }

        let walker = Walker(query: query, current: -1, caseSensitive: caseSensitive, theme: theme)
        var marked: [IdentifiedBlock] = []
        var starts: [Int] = []
        marked.reserveCapacity(blocks.count)
        starts.reserveCapacity(blocks.count)

        for item in blocks {
            starts.append(walker.count)
            marked.append(IdentifiedBlock(id: item.id, block: walker.visit(item.block)))
        }

        return Highlighted(blocks: marked, matchCount: walker.count, starts: starts)
    }

    /// The cheap pass — re-marks only the block that holds match number `current`.
    static func markCurrent(
        _ scanned: Highlighted,
        current: Int,
        query: String,
        caseSensitive: Bool,
        theme: Theme
    ) -> (blocks: [IdentifiedBlock], currentBlockID: Int?) {
        guard !query.isEmpty, current >= 0, current < scanned.matchCount else {
            return (scanned.blocks, nil)
        }

        // The last block that starts at or before this match is the one holding it: blocks with
        // no matches of their own carry the start of the block that follows them.
        var low = 0
        var high = scanned.starts.count - 1
        var index = 0
        while low <= high {
            let mid = (low + high) / 2
            if scanned.starts[mid] <= current {
                index = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        let walker = Walker(
            query: query,
            current: current - scanned.starts[index],
            caseSensitive: caseSensitive,
            theme: theme
        )
        var blocks = scanned.blocks
        let item = blocks[index]
        blocks[index] = IdentifiedBlock(id: item.id, block: walker.visit(item.block))
        return (blocks, item.id)
    }
}

/// A class, not a struct: the walk recurses through nested blocks while carrying a running
/// match counter, and a mutating struct cannot be used from inside the nested calls.
private final class Walker {
    let query: String
    let options: String.CompareOptions
    /// Ordinal of the match to paint as the current one, or -1 for "none of them"
    let current: Int
    let theme: Theme

    /// Matches seen so far — also the ordinal of the next one found
    private(set) var count = 0

    init(query: String, current: Int, caseSensitive: Bool, theme: Theme) {
        self.query = query
        self.current = current
        self.options = caseSensitive ? [] : [.caseInsensitive]
        self.theme = theme
    }

    func visit(_ block: RenderBlock) -> RenderBlock {
        switch block {
        case let .heading(level, text):
            return .heading(level: level, text: mark(text))

        case let .paragraph(text):
            return .paragraph(mark(text))

        case let .codeBlock(language, code, isWide):
            return .codeBlock(language: language, code: mark(code), isWide: isWide)

        case let .quote(children):
            return .quote(visit(children))

        case let .list(ordered, start, items):
            var marked: [ListEntry] = []
            marked.reserveCapacity(items.count)
            for item in items {
                marked.append(ListEntry(checked: item.checked, content: visit(item.content)))
            }
            return .list(ordered: ordered, start: start, items: marked)

        case let .table(header, rows, alignments):
            let markedHeader = header.map(mark)
            var markedRows: [[AttributedString]] = []
            markedRows.reserveCapacity(rows.count)
            for row in rows {
                markedRows.append(row.map(mark))
            }
            return .table(header: markedHeader, rows: markedRows, alignments: alignments)

        case .thematicBreak, .image:
            // Nothing readable to search: a rule has no text, and alt text is not on screen
            return block
        }
    }

    private func visit(_ blocks: [RenderBlock]) -> [RenderBlock] {
        var out: [RenderBlock] = []
        out.reserveCapacity(blocks.count)
        for block in blocks { out.append(visit(block)) }
        return out
    }

    /// Paints every hit in `text`, and counts them in document order
    private func mark(_ text: AttributedString) -> AttributedString {
        let plain = String(text.characters)
        guard !plain.isEmpty,
              let first = plain.range(of: query, options: options)
        else { return text }

        var out = text
        var hit: Range<String.Index>? = first

        while let range = hit {
            // AttributedString indices are its own; walk them by the same character offsets
            let offset = plain.distance(from: plain.startIndex, to: range.lowerBound)
            let length = plain.distance(from: range.lowerBound, to: range.upperBound)
            let start = out.index(out.startIndex, offsetByCharacters: offset)
            let end = out.index(start, offsetByCharacters: length)

            var attrs = AttributeContainer()
            if count == current {
                // The current hit gets a solid fill, so the text on top of it needs its own colour
                attrs.backgroundColor = theme.findCurrentHighlight
                attrs.foregroundColor = theme.findCurrentText
            } else {
                attrs.backgroundColor = theme.findHighlight
            }
            out[start..<end].mergeAttributes(attrs)

            count += 1
            hit = range.upperBound < plain.endIndex
                ? plain.range(of: query, options: options, range: range.upperBound..<plain.endIndex)
                : nil
        }

        return out
    }
}
