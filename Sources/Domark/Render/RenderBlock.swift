import Foundation

/// The middle layer between the cmark AST and the SwiftUI views.
/// Converted once at parse time and then drawn directly, so no view has to know about Markdown.
indirect enum RenderBlock: Equatable, Sendable {
    case heading(level: Int, text: AttributedString)
    case paragraph(AttributedString)
    case codeBlock(language: String?, code: AttributedString, isWide: Bool)
    case quote([RenderBlock])
    case list(ordered: Bool, start: Int, items: [ListEntry])
    case table(header: [AttributedString], rows: [[AttributedString]], alignments: [ColumnAlign])
    case thematicBreak
    case image(url: URL?, alt: String)
    /// From HTML: `<details>` — collapsed until the reader opens it
    case details(summary: AttributedString, content: [RenderBlock])
    /// From HTML: `align="center"` / `align="right"` around other blocks
    case aligned(ColumnAlign, [RenderBlock])
    /// From HTML: `<img>` tags laid out in a row that wraps — a logo, a line of badges
    case images([SizedImage])
}

struct SizedImage: Equatable, Sendable {
    var url: URL?
    var alt: String
    /// From the tag's width/height attributes; nil keeps the image's own size
    var width: CGFloat?
    var height: CGFloat?
}

struct ListEntry: Equatable, Sendable {
    /// nil when this is not a task list
    var checked: Bool?
    var content: [RenderBlock]
}

enum ColumnAlign: Equatable, Sendable {
    case leading, center, trailing
}

/// Gives a RenderBlock an identity.
///
/// `ForEach(blocks.indices, id: \.self)` crashes when the document gets shorter:
/// SwiftUI still holds the old indices and subscripts them into the new, shorter array.
/// Iterating over values instead lets SwiftUI hold the value and never index back.
struct IdentifiedBlock: Identifiable, Equatable, Sendable {
    let id: Int
    let block: RenderBlock
}

extension Array where Element == RenderBlock {
    var identified: [IdentifiedBlock] {
        enumerated().map { IdentifiedBlock(id: $0.offset, block: $0.element) }
    }
}
