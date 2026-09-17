import AppKit
import Foundation
import Markdown
import SwiftUI

/// Turns a Markdown AST into [RenderBlock].
///
/// Plain recursion instead of MarkupVisitor: `theme` and `baseURL` have to be carried down every level,
/// and the visitor protocol would force that state into the struct, which reads worse here.
struct BlockBuilder {
    var theme: Theme
    var baseURL: URL?

    static func parse(source: String, theme: Theme, baseURL: URL?) -> [RenderBlock] {
        // swift-markdown turns on cmark's SMART option by default, which rewrites
        // " into “ ”, -- into – and ... into …  That silently corrupts anything meant to be
        // copied back out — a `--flag` in a sentence would come out as an en dash.
        let document = Document(parsing: source, options: [.disableSmartOpts])
        let builder = BlockBuilder(theme: theme, baseURL: baseURL)
        return builder.blocks(in: document)
    }

    private var inlineResolver: InlineBuilder {
        InlineBuilder(theme: theme, size: theme.base, baseURL: baseURL)
    }

    func blocks(in markup: Markup) -> [RenderBlock] {
        markup.children.flatMap { block($0) }
    }

    private func block(_ markup: Markup) -> [RenderBlock] {
        switch markup {
        case let node as Heading:
            let level = min(max(node.level, 1), 6)
            let inline = InlineBuilder(
                theme: theme,
                size: theme.base * Theme.headingScale(level),
                weight: level <= 2 ? .bold : .semibold,
                baseURL: baseURL
            )
            return [.heading(level: level, text: inline.attributed(node))]

        case let node as Paragraph:
            // A paragraph holding nothing but an image becomes a real image, not alt text
            if let image = soleImage(in: node) {
                return [.image(url: inlineResolver.url(for: image.source), alt: image.plainText)]
            }
            let inline = InlineBuilder(theme: theme, size: theme.base, baseURL: baseURL)
            return [.paragraph(inline.attributed(node))]

        case let node as CodeBlock:
            let language = node.language?.trimmingCharacters(in: .whitespaces)
            let code = node.code.trimmingCharacters(in: .newlines)
            return [.codeBlock(
                language: (language?.isEmpty ?? true) ? nil : language,
                code: AttributedString(code),
                isWide: Self.needsHorizontalScroll(code)
            )]

        case let node as HTMLBlock:
            // Raw HTML is not rendered — show it as code so nothing is hidden
            let html = node.rawHTML.trimmingCharacters(in: .newlines)
            return [.codeBlock(language: "html", code: AttributedString(html), isWide: Self.needsHorizontalScroll(html))]

        case let node as BlockQuote:
            return [.quote(blocks(in: node))]

        case let node as UnorderedList:
            return [.list(ordered: false, start: 1, items: entries(of: node))]

        case let node as OrderedList:
            return [.list(ordered: true, start: Int(node.startIndex), items: entries(of: node))]

        case let node as Markdown.Table:
            return [table(node)]

        case is ThematicBreak:
            return [.thematicBreak]

        default:
            // BlockDirective, CustomBlock and friends — descend rather than drop them
            return blocks(in: markup)
        }
    }

    private func entries(of list: ListItemContainer) -> [ListEntry] {
        list.listItems.map { item in
            ListEntry(
                checked: item.checkbox.map { $0 == .checked },
                content: blocks(in: item)
            )
        }
    }

    private func table(_ node: Markdown.Table) -> RenderBlock {
        let inline = InlineBuilder(theme: theme, size: theme.base, baseURL: baseURL)

        func cells(_ row: Markup) -> [AttributedString] {
            row.children.compactMap { $0 as? Markdown.Table.Cell }.map { inline.attributed($0) }
        }

        let header = cells(node.head)
        let rows = node.body.children
            .compactMap { $0 as? Markdown.Table.Row }
            .map { cells($0) }

        let columnCount = max(header.count, rows.map(\.count).max() ?? 0)
        let alignments: [ColumnAlign] = (0..<columnCount).map { index in
            guard index < node.columnAlignments.count else { return .leading }
            return switch node.columnAlignments[index] {
            case .center: .center
            case .right: .trailing
            default: .leading
            }
        }

        // Pad every row to the same length, otherwise the grid goes crooked
        let padded = rows.map { row in
            row + Array(repeating: AttributedString(), count: columnCount - row.count)
        }
        let paddedHeader = header + Array(repeating: AttributedString(), count: columnCount - header.count)

        return .table(header: paddedHeader, rows: padded, alignments: alignments)
    }

    /// Decided once here rather than in the view: wrapping every code block in its own
    /// nested ScrollView costs real time per frame while scrolling, and most blocks are narrow.
    private static func needsHorizontalScroll(_ code: String) -> Bool {
        code.split(separator: "\n", omittingEmptySubsequences: false).contains { $0.count > 64 }
    }

    private func soleImage(in paragraph: Paragraph) -> Markdown.Image? {
        let meaningful = paragraph.children.filter { child in
            if child is SoftBreak || child is LineBreak { return false }
            if let text = child as? Markdown.Text {
                return !text.string.trimmingCharacters(in: .whitespaces).isEmpty
            }
            return true
        }
        guard meaningful.count == 1 else { return nil }
        return meaningful.first as? Markdown.Image
    }
}
