import Foundation

/// Links that point inside the document itself — the `#หัวข้อ` form a table of contents uses.
///
/// They are rewritten at parse time into a URL with our own scheme. The preview can then tell
/// them apart from real links without inspecting strings again: everything else goes out to the
/// browser, these scroll the page. Left alone they used to resolve against the file's folder and
/// turn into a path to a file that does not exist, which is why clicking one did nothing at all.
enum Anchor {
    static let scheme = "domark-heading"

    /// `#การติดตั้ง` → `domark-heading:%E0%B8%81...`
    ///
    /// Anything already percent-encoded — which is how most tools write a Thai table of
    /// contents — is decoded first, so one heading only ever has one spelling here.
    static func url(fragment: String) -> URL? {
        let raw = fragment.hasPrefix("#") ? String(fragment.dropFirst()) : fragment
        let decoded = raw.removingPercentEncoding ?? raw
        guard !decoded.isEmpty,
              let encoded = decoded.addingPercentEncoding(withAllowedCharacters: .alphanumerics)
        else { return nil }
        return URL(string: "\(scheme):\(encoded)")
    }

    /// The heading this URL points at, or nil when it is an ordinary link
    static func target(of url: URL) -> String? {
        guard url.scheme == scheme else { return nil }
        let raw = String(url.absoluteString.dropFirst(scheme.count + 1))
        return raw.removingPercentEncoding ?? raw
    }

    /// GitHub's heading slug: lowercased, punctuation dropped, spaces turned into hyphens.
    /// Letters and digits survive whatever the script, so a Thai heading slugs to itself.
    static func slug(_ text: String) -> String {
        var out = ""
        for character in text.lowercased() {
            if character.isLetter || character.isNumber || character == "-" || character == "_" {
                out.append(character)
            } else if character.isWhitespace {
                out.append("-")
            }
        }
        return out
    }

    /// Maps every heading to the top-level block that has to scroll into view — a heading nested
    /// in a quote or a list points at the block that contains it.
    ///
    /// Repeated headings get GitHub's `-1`, `-2` suffixes so that a table of contents generated
    /// by another tool still lands on the right one.
    static func map(for blocks: [IdentifiedBlock]) -> [String: Int] {
        var map: [String: Int] = [:]
        var seen: [String: Int] = [:]

        func visit(_ block: RenderBlock, id: Int) {
            switch block {
            case let .heading(_, text):
                let base = slug(String(text.characters))
                guard !base.isEmpty else { return }
                let count = seen[base, default: 0]
                seen[base] = count + 1
                map[count == 0 ? base : "\(base)-\(count)"] = id

            case let .quote(children):
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
        return map
    }

    /// Tolerates the spellings other tools write: an already-slugged target, or the raw heading
    /// text with its spaces and punctuation still in it.
    static func block(for target: String, in map: [String: Int]) -> Int? {
        map[target] ?? map[slug(target)]
    }
}
