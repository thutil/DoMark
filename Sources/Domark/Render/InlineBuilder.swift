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
}

struct InlineBuilder {
    var theme: Theme
    /// Base font size of the enclosing block — a heading passes in its own size
    var size: CGFloat
    var weight: NSFont.Weight = .regular
    /// Location of the .md file, used to resolve relative image and link paths
    var baseURL: URL?

    func attributed(_ markup: Markup) -> AttributedString {
        var out = AttributedString()
        for child in markup.children {
            out += render(child, style: [], link: nil)
        }
        return out
    }

    private func render(_ markup: Markup, style: InlineStyle, link: URL?) -> AttributedString {
        switch markup {
        case let node as Markdown.Text:
            return leaf(node.string, style: style, link: link)

        case let node as InlineCode:
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
            return leaf(node.rawHTML, style: style.union(.code), link: link)

        default:
            return descend(markup, style: style, link: link)
        }
    }

    private func descend(_ markup: Markup, style: InlineStyle, link: URL?) -> AttributedString {
        var out = AttributedString()
        for child in markup.children {
            out += render(child, style: style, link: link)
        }
        return out
    }

    private func leaf(_ string: String, style: InlineStyle, link: URL?) -> AttributedString {
        var piece = AttributedString(string)
        var attrs = AttributeContainer()

        if style.contains(.code) {
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

    private func resolve(_ destination: String?) -> URL? {
        guard let destination, !destination.isEmpty else { return nil }
        // A table of contents points inside this document, not at a file next to it
        if destination.hasPrefix("#") { return Anchor.url(fragment: destination) }
        if let url = URL(string: destination), url.scheme != nil { return url }
        guard let baseURL else { return URL(string: destination) }
        return URL(fileURLWithPath: destination, relativeTo: baseURL.deletingLastPathComponent()).standardizedFileURL
    }
}
