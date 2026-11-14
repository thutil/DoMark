import Foundation

/// The slice of HTML that Markdown documents actually use — a centred logo, a row of badges,
/// a collapsible section, a key cap — turned into ordinary render blocks.
///
/// This is not a browser. Anything outside `supported` makes the whole fragment fall back to
/// being shown as code, as all HTML was before: a page that silently drops what it does not
/// understand is worse than one that shows the source.
enum HTML {
    indirect enum Node: Equatable {
        case text(String)
        case element(name: String, attributes: [String: String], children: [Node])
    }

    static let supported: Set<String> = [
        "p", "div", "center", "span", "h1", "h2", "h3", "h4", "h5", "h6",
        "details", "summary", "img", "br", "hr", "a",
        "b", "strong", "i", "em", "code", "kbd", "sub", "sup",
    ]
    static let voidElements: Set<String> = ["img", "br", "hr", "input", "meta", "link", "source", "wbr"]
    static let blockElements: Set<String> = [
        "p", "div", "center", "h1", "h2", "h3", "h4", "h5", "h6", "details", "summary", "hr",
    ]
    /// Elements that may open in one HTML block and close in a later one, with Markdown in between
    static let wrappers: Set<String> = ["details", "div", "p", "center"]

    // MARK: - Tokens

    enum Token: Equatable {
        case open(String, [String: String], selfClosing: Bool)
        case close(String)
        case text(String)
        case comment
    }

    static func tokenize(_ source: String) -> [Token] {
        let s = Array(source)
        var tokens: [Token] = []
        var text = ""
        var i = 0

        func flushText() {
            if !text.isEmpty { tokens.append(.text(text)); text = "" }
        }

        while i < s.count {
            if s[i] == "<", i + 3 < s.count, s[i + 1] == "!", s[i + 2] == "-", s[i + 3] == "-" {
                flushText()
                var j = i + 4
                while j + 2 < s.count, !(s[j] == "-" && s[j + 1] == "-" && s[j + 2] == ">") { j += 1 }
                i = min(j + 3, s.count)
                tokens.append(.comment)
            } else if s[i] == "<", i + 1 < s.count, s[i + 1].isLetter || s[i + 1] == "/" {
                let isClose = s[i + 1] == "/"
                var j = i + (isClose ? 2 : 1)
                var name = ""
                while j < s.count, s[j].isLetter || s[j].isNumber || s[j] == "-" {
                    name.append(s[j]); j += 1
                }
                guard !name.isEmpty else { text.append(s[i]); i += 1; continue }
                var attributes: [String: String] = [:]
                var selfClosing = false
                // Attributes until `>`, honouring quotes so a `>` inside a value does not end the tag
                while j < s.count, s[j] != ">" {
                    if s[j] == "/" { selfClosing = true; j += 1; continue }
                    guard s[j].isLetter else { j += 1; continue }
                    selfClosing = false
                    var key = ""
                    while j < s.count, s[j].isLetter || s[j].isNumber || "-_:".contains(s[j]) {
                        key.append(s[j]); j += 1
                    }
                    var value = ""
                    if j < s.count, s[j] == "=" {
                        j += 1
                        if j < s.count, s[j] == "\"" || s[j] == "'" {
                            let quote = s[j]
                            j += 1
                            while j < s.count, s[j] != quote { value.append(s[j]); j += 1 }
                            j += 1
                        } else {
                            while j < s.count, !s[j].isWhitespace, s[j] != ">" { value.append(s[j]); j += 1 }
                        }
                    }
                    attributes[key.lowercased()] = decodeEntities(value)
                }
                flushText()
                let lower = name.lowercased()
                tokens.append(isClose ? .close(lower) : .open(lower, attributes, selfClosing: selfClosing))
                i = min(j + 1, s.count)
            } else {
                text.append(s[i])
                i += 1
            }
        }
        flushText()
        return tokens
    }

    // MARK: - Tree

    /// Nil when the fragment uses anything outside `supported`
    static func parse(_ source: String) -> [Node]? {
        let tokens = tokenize(source)

        // Each open element: its name, attributes and the children gathered so far
        var stack: [(name: String, attributes: [String: String], children: [Node])] = [("", [:], [])]

        func closeTop() {
            let top = stack.removeLast()
            stack[stack.count - 1].children.append(.element(name: top.name, attributes: top.attributes, children: top.children))
        }

        for token in tokens {
            switch token {
            case let .text(string):
                stack[stack.count - 1].children.append(.text(decodeEntities(string)))
            case .comment:
                break
            case let .open(name, attributes, selfClosing):
                guard supported.contains(name) else { return nil }
                if selfClosing || voidElements.contains(name) {
                    stack[stack.count - 1].children.append(.element(name: name, attributes: attributes, children: []))
                } else {
                    stack.append((name, attributes, []))
                }
            case let .close(name):
                guard supported.contains(name) else { return nil }
                // Tolerant like a browser: close whatever was left open inside it; a stray close is ignored
                guard stack.dropFirst().contains(where: { $0.name == name }) else { continue }
                while stack.last?.name != name { closeTop() }
                closeTop()
            }
        }
        while stack.count > 1 { closeTop() }
        return stack[0].children
    }

    // MARK: - Wrappers split across blocks

    /// `<details><summary>…</summary>` or `<div align="center">` standing alone, with the
    /// Markdown it wraps following as separate blocks
    struct Opener {
        let name: String
        let attributes: [String: String]
        let summary: [Node]
    }

    static func opener(_ source: String) -> Opener? {
        let tokens = tokenize(source).filter { token in
            if case .comment = token { return false }
            if case let .text(string) = token { return !string.allSatisfy(\.isWhitespace) }
            return true
        }
        guard case let .open(name, attributes, selfClosing) = tokens.first,
              wrappers.contains(name), !selfClosing else { return nil }
        let rest = tokens.dropFirst()
        if rest.isEmpty { return Opener(name: name, attributes: attributes, summary: []) }

        // Only a details may carry more — its complete summary
        guard name == "details",
              case .open("summary", _, _) = rest.first,
              rest.last == .close("summary"),
              let tree = parse(source),
              case let .element(_, _, children)? = tree.first(where: { if case .element = $0 { true } else { false } }),
              case let .element("summary", _, summary)? = children.first(where: { if case .element = $0 { true } else { false } })
        else { return nil }
        return Opener(name: name, attributes: attributes, summary: summary)
    }

    /// True when the block is nothing but `</name>`
    static func isCloser(_ source: String, of name: String) -> Bool {
        let tokens = tokenize(source).filter { token in
            if case .comment = token { return false }
            if case let .text(string) = token { return !string.allSatisfy(\.isWhitespace) }
            return true
        }
        return tokens == [.close(name)]
    }

    /// True when the block holds only comments, which are hidden rather than shown as code
    static func isOnlyComments(_ source: String) -> Bool {
        let tokens = tokenize(source)
        return tokens.contains(.comment) && tokens.allSatisfy { token in
            if case .comment = token { return true }
            if case let .text(string) = token { return string.allSatisfy(\.isWhitespace) }
            return false
        }
    }

    static func alignment(_ attributes: [String: String], name: String) -> ColumnAlign? {
        if name == "center" { return .center }
        return switch attributes["align"]?.lowercased() {
        case "center": .center
        case "right": .trailing
        default: nil
        }
    }

    // MARK: - Entities

    private static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
        "copy": "©", "reg": "®", "trade": "™", "mdash": "—", "ndash": "–", "hellip": "…",
        "middot": "·", "bull": "•", "rarr": "→", "larr": "←", "times": "×",
    ]

    static func decodeEntities(_ string: String) -> String {
        guard string.contains("&") else { return string }
        var out = ""
        var rest = Substring(string)
        while let amp = rest.firstIndex(of: "&") {
            out += rest[..<amp]
            let after = rest[rest.index(after: amp)...]
            if let semi = after.prefix(10).firstIndex(of: ";") {
                let entity = String(after[..<semi])
                if let value = named[entity] ?? numeric(entity) {
                    out += value
                    rest = after[after.index(after: semi)...]
                    continue
                }
            }
            out += "&"
            rest = after
        }
        return out + rest
    }

    private static func numeric(_ entity: String) -> String? {
        guard entity.hasPrefix("#") else { return nil }
        let digits = entity.dropFirst()
        let code = digits.lowercased().hasPrefix("x") ? UInt32(digits.dropFirst(), radix: 16) : UInt32(digits)
        return code.flatMap(Unicode.Scalar.init).map { String(Character($0)) }
    }
}
