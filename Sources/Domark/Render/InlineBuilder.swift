import AppKit
import Foundation
import Markdown
import SwiftUI

/// Styling carried down while walking the AST.
///
/// It has to accumulate and be applied at the leaf: `***bold italic***` is Strong wrapping Emphasis,
/// so applying a font at each level would let the inner one overwrite the outer and leave only italic.
struct InlineStyle: OptionSet {
    let rawValue: Int
    static let bold = InlineStyle(rawValue: 1 << 0)
    static let italic = InlineStyle(rawValue: 1 << 1)
    static let code = InlineStyle(rawValue: 1 << 2)
    static let strike = InlineStyle(rawValue: 1 << 3)
    static let keyboard = InlineStyle(rawValue: 1 << 4)
    static let sub = InlineStyle(rawValue: 1 << 5)
    static let sup = InlineStyle(rawValue: 1 << 6)

    /// The inline tags Markdown authors write by hand
    init?(htmlTag name: String) {
        switch name {
        case "b", "strong": self = .bold
        case "i", "em": self = .italic
        case "code": self = .code
        case "kbd": self = .keyboard
        case "sub": self = .sub
        case "sup": self = .sup
        case "s", "del", "strike": self = .strike
        default: return nil
        }
    }

    init(rawValue: Int) { self.rawValue = rawValue }
}

struct InlineBuilder {
    var theme: Theme
    /// Base font size of the enclosing block — a heading passes in its own size
    var size: CGFloat
    var weight: NSFont.Weight = .regular
    /// Location of the .md file, used to resolve relative image and link paths
    var baseURL: URL?

    func attributed(_ markup: Markup) -> AttributedString {
        descend(markup, style: [], link: nil)
    }

    private func render(_ markup: Markup, style: InlineStyle, link: URL?) -> AttributedString {
        switch markup {
        case let node as Markdown.Text:
            return leaf(node.string, style: style, link: link)

        case let node as InlineCode:
            if node.code.first == MathSource.marker {
                // `$…$`, wrapped as a code span by MathSource. The TeX stays in the text so
                // copying and searching still see it; the view draws the formula over it.
                let latex = String(node.code.dropFirst())
                var piece = leaf(latex, style: style, link: link)
                piece[InlineMathAttribute.self] = latex
                return piece
            }
            return leaf(node.code, style: style.union(.code), link: link)

        case is SoftBreak:
            return leaf(" ", style: style, link: link)

        case is LineBreak:
            return leaf("\n", style: style, link: link)

        case let node as Strong:
            return descend(node, style: style.union(.bold), link: link)

        case let node as Emphasis:
            return descend(node, style: style.union(.italic), link: link)

        case let node as Strikethrough:
            return descend(node, style: style.union(.strike), link: link)

        case let node as Markdown.Link:
            return descend(node, style: style, link: resolve(node.destination) ?? link)

        case let node as Markdown.Image:
            // An image inline in a paragraph shows its alt text (a lone image already became an .image block)
            let alt = node.plainText.isEmpty ? "image" : node.plainText
            return leaf("🖼 \(alt)", style: style.union(.italic), link: resolve(node.source) ?? link)

        case let node as InlineHTML:
            // Tags that style what follows them are handled by `descend`; what reaches
            // here is HTML we do not render, shown as code so it is not lost
            return leaf(node.rawHTML, style: style.union(.code), link: link)

        default:
            return descend(markup, style: style, link: link)
        }
    }

    /// Inline HTML arrives as separate siblings — `<kbd>`, a Text, `</kbd>` — so the styling
    /// it opens has to be carried along the run of siblings, not down into one node.
    private func descend(_ markup: Markup, style: InlineStyle, link: URL?) -> AttributedString {
        var out = AttributedString()
        var opened: [(name: String, style: InlineStyle)] = []
        var links: [URL?] = []

        for child in markup.children {
            let current = opened.reduce(style) { $0.union($1.style) }
            let currentLink = links.last.flatMap { $0 } ?? link

            guard let html = child as? InlineHTML else {
                out += render(child, style: current, link: currentLink)
                continue
            }
            switch HTML.tokenize(html.rawHTML).first {
            case .comment?:
                continue
            case let .open("br", _, _)?:
                out += leaf("\n", style: current, link: currentLink)
            case let .open("a", attributes, false)?:
                links.append(resolve(attributes["href"]))
            case .close("a")? where !links.isEmpty:
                links.removeLast()
            case let .open("img", attributes, _)?:
                let alt = attributes["alt"].flatMap { $0.isEmpty ? nil : $0 } ?? "image"
                out += leaf("🖼 \(alt)", style: current.union(.italic), link: resolve(attributes["src"]) ?? currentLink)
            case let .open(name, _, false)? where InlineStyle(htmlTag: name) != nil:
                opened.append((name, InlineStyle(htmlTag: name)!))
            case let .close(name)? where opened.contains(where: { $0.name == name }):
                opened.remove(at: opened.lastIndex(where: { $0.name == name })!)
            default:
                out += render(child, style: current, link: currentLink)
            }
        }
        return out
    }

    /// Text and inline elements from a raw HTML block, with HTML's whitespace rules:
    /// runs of spaces and newlines collapse to one space, and `<br>` is the only line break.
    func attributed(html nodes: [HTML.Node]) -> AttributedString {
        var out = AttributedString()
        var atLineStart = true

        func walk(_ nodes: [HTML.Node], style: InlineStyle, link: URL?) {
            for node in nodes {
                switch node {
                case let .text(raw):
                    var text = raw.replacing(/\s+/, with: " ")
                    if atLineStart { text = String(text.drop(while: { $0 == " " })) }
                    guard !text.isEmpty else { continue }
                    out += leaf(text, style: style, link: link)
                    atLineStart = false
                case let .element("br", _, _):
                    out += leaf("\n", style: style, link: link)
                    atLineStart = true
                case let .element("a", attributes, children):
                    walk(children, style: style, link: resolve(attributes["href"]) ?? link)
                case let .element("img", attributes, _):
                    let alt = attributes["alt"].flatMap { $0.isEmpty ? nil : $0 } ?? "image"
                    out += leaf("🖼 \(alt)", style: style.union(.italic), link: resolve(attributes["src"]) ?? link)
                    atLineStart = false
                case let .element(name, _, children):
                    walk(children, style: style.union(InlineStyle(htmlTag: name) ?? []), link: link)
                }
            }
        }
        walk(nodes, style: [], link: nil)

        // A trailing space before the end of the block would push centred text off-centre
        while out.characters.last?.isWhitespace == true {
            out.removeSubrange(out.index(beforeCharacter: out.endIndex)..<out.endIndex)
        }
        return out
    }

    private func leaf(_ string: String, style: InlineStyle, link: URL?) -> AttributedString {
        var piece = AttributedString(string)
        var attrs = AttributeContainer()

        // Sub- and superscript are set smaller and moved off the baseline
        let shifted = style.contains(.sub) || style.contains(.sup)
        let size = shifted ? self.size * 0.72 : self.size
        if shifted {
            attrs.baselineOffset = style.contains(.sup) ? self.size * 0.38 : -self.size * 0.18
        }

        if style.contains(.keyboard) {
            // A key cap: monospaced on a darker plate than inline code
            piece = AttributedString("\u{2009}\(string)\u{2009}")
            attrs.font = Fonts.mono(family: theme.code, size: size * 0.82, weight: .medium)
            attrs.backgroundColor = theme.keyBackground
        } else if style.contains(.code) {
            attrs.font = Fonts.mono(
                family: theme.code,
                size: size * 0.90,
                weight: style.contains(.bold) ? .semibold : .regular
            )
            attrs.backgroundColor = theme.codeBackground
        } else {
            attrs.font = Fonts.body(
                family: theme.prose,
                size: size,
                weight: style.contains(.bold) ? .bold : weight,
                italic: style.contains(.italic)
            )
        }

        if style.contains(.strike) {
            attrs.strikethroughStyle = .single
            attrs.foregroundColor = .secondary
        }

        if let link {
            attrs.link = link
            attrs.foregroundColor = .accentColor
        }

        piece.mergeAttributes(attrs)
        return piece
    }

    /// Handles absolute URLs, paths relative to the .md file, and anchors
    func url(for destination: String?) -> URL? { resolve(destination) }

    func resolve(_ destination: String?) -> URL? {
        guard let destination, !destination.isEmpty else { return nil }
        // A table of contents points inside this document, not at a file next to it
        if destination.hasPrefix("#") { return Anchor.url(fragment: destination) }
        if let url = URL(string: destination), url.scheme != nil { return url }
        guard let baseURL else { return URL(string: destination) }
        return URL(fileURLWithPath: destination, relativeTo: baseURL.deletingLastPathComponent()).standardizedFileURL
    }
}
