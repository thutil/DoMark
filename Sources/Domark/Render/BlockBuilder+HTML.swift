import Foundation
import Markdown

/// Raw HTML blocks → render blocks. See `HTML` for what is supported and why the rest is shown as code.
extension BlockBuilder {
    /// A block-level run of siblings, with `<details>` / `<div align>` that open in one HTML
    /// block and close in a later one gathered around the Markdown between them.
    func blocks(of children: [Markup]) -> [RenderBlock] {
        var out: [RenderBlock] = []
        var index = 0
        while index < children.count {
            if let html = children[index] as? HTMLBlock,
               let opener = HTML.opener(html.rawHTML),
               let close = closingIndex(for: opener.name, in: children, after: index) {
                let inner = blocks(of: Array(children[(index + 1)..<close]))
                out += wrap(inner, in: opener.name, attributes: opener.attributes, summary: opener.summary)
                index = close + 1
            } else {
                out += block(children[index])
                index += 1
            }
        }
        return out
    }

    /// The matching `</name>` block, counting nested openers of the same element
    private func closingIndex(for name: String, in children: [Markup], after start: Int) -> Int? {
        var depth = 0
        for index in (start + 1)..<children.count {
            guard let html = children[index] as? HTMLBlock else { continue }
            if HTML.opener(html.rawHTML)?.name == name {
                depth += 1
            } else if HTML.isCloser(html.rawHTML, of: name) {
                if depth == 0 { return index }
                depth -= 1
            }
        }
        return nil
    }

    /// One self-contained HTML block. Nil when it uses something unsupported.
    func htmlBlocks(_ source: String) -> [RenderBlock]? {
        if HTML.isOnlyComments(source) { return [] }
        guard let nodes = HTML.parse(source) else { return nil }
        return blocks(html: nodes)
    }

    // MARK: - Nodes

    private func blocks(html nodes: [HTML.Node]) -> [RenderBlock] {
        var out: [RenderBlock] = []
        var inline: [HTML.Node] = []

        func flush() {
            defer { inline = [] }
            if let images = imageRow(inline) {
                out.append(.images(images))
                return
            }
            let text = inlineResolver.attributed(html: inline)
            if !text.characters.isEmpty { out.append(.paragraph(text)) }
        }

        for node in nodes {
            guard case let .element(name, attributes, children) = node, HTML.blockElements.contains(name) else {
                inline.append(node)
                continue
            }
            flush()
            switch name {
            case "hr":
                out.append(.thematicBreak)
            case "details":
                let summaryNode = children.first { if case .element("summary", _, _) = $0 { true } else { false } }
                let rest = children.filter { $0 != summaryNode }
                var summary: [HTML.Node] = []
                if case let .element(_, _, nodes)? = summaryNode { summary = nodes }
                out += wrap(blocks(html: rest), in: name, attributes: attributes, summary: summary)
            case "summary":
                // A summary outside a details is just a bold line
                let text = inlineResolver.attributed(html: [.element(name: "b", attributes: [:], children: children)])
                out.append(.paragraph(text))
            default:
                if let level = Int(name.dropFirst()), name.hasPrefix("h") {
                    let heading = headingBuilder(level).attributed(html: children)
                    out += wrap([.heading(level: level, text: heading)], in: name, attributes: attributes, summary: [])
                } else {
                    out += wrap(blocks(html: children), in: name, attributes: attributes, summary: [])
                }
            }
        }
        flush()
        return out
    }

    private func wrap(_ inner: [RenderBlock], in name: String, attributes: [String: String], summary: [HTML.Node]) -> [RenderBlock] {
        if name == "details" {
            var title = inlineResolver.attributed(html: summary)
            if title.characters.isEmpty { title = AttributedString("Details") }
            return [.details(summary: title, content: inner)]
        }
        guard let alignment = HTML.alignment(attributes, name: name), !inner.isEmpty else { return inner }
        return [.aligned(alignment, inner)]
    }

    /// A run that holds nothing but images (links around them and spacing allowed) — a logo,
    /// a row of badges — is drawn as images rather than as their alt text
    private func imageRow(_ nodes: [HTML.Node]) -> [SizedImage]? {
        var images: [SizedImage] = []

        func collect(_ nodes: [HTML.Node]) -> Bool {
            for node in nodes {
                switch node {
                case let .text(text) where text.allSatisfy(\.isWhitespace):
                    continue
                case .element("br", _, _):
                    continue
                case let .element("img", attributes, _):
                    images.append(SizedImage(
                        url: inlineResolver.url(for: attributes["src"]),
                        alt: attributes["alt"] ?? "",
                        width: attributes["width"].flatMap(Self.length),
                        height: attributes["height"].flatMap(Self.length)
                    ))
                case let .element("a", _, children), let .element("span", _, children):
                    guard collect(children) else { return false }
                default:
                    return false
                }
            }
            return true
        }
        return collect(nodes) && !images.isEmpty ? images : nil
    }

    /// `128`, `128px` → 128. Percentages are ignored: there is no container width to resolve against.
    private static func length(_ raw: String) -> CGFloat? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "px", with: "")
        return Double(trimmed).map { CGFloat($0) }
    }
}
