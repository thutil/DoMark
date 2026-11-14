import Foundation

/// Finds TeX math in the Markdown source before cmark sees it.
///
/// cmark knows nothing about `$`: left alone, `$a_1 * b_1$` comes out of the parser as
/// emphasis, and `\\` loses a backslash. So math is moved into constructs whose content cmark
/// keeps byte for byte — `$$…$$` into a ```` ```math ```` fence, `$…$` into an inline code
/// span tagged with `marker` — and the renderer picks them up from there. Code fences and
/// code spans are skipped, so a `$` in code is never touched.
enum MathSource {
    /// Private-use character that opens an inline code span holding math rather than code
    static let marker: Character = "\u{E000}"

    static func protect(_ source: String) -> String {
        guard source.contains("$") else { return source }

        var out: [String] = []
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var fence: (char: Character, count: Int)?
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let indent = String(line.prefix(while: { $0 == " " || $0 == "\t" }))

            // Inside a code fence nothing is math
            if let open = fence {
                out.append(line)
                if Self.fenceRun(trimmed)?.char == open.char, (Self.fenceRun(trimmed)?.count ?? 0) >= open.count,
                   trimmed.drop(while: { $0 == open.char }).trimmingCharacters(in: .whitespaces).isEmpty {
                    fence = nil
                }
                index += 1
                continue
            }
            if let run = Self.fenceRun(trimmed), run.count >= 3 {
                fence = run
                out.append(line)
                index += 1
                continue
            }

            // $$ … $$ on one line, or opening a block that a later line closes
            if trimmed.hasPrefix("$$") {
                let afterOpen = String(trimmed.dropFirst(2))
                if afterOpen.hasSuffix("$$"), afterOpen.count > 2 {
                    out += mathFence(String(afterOpen.dropLast(2)), indent: indent)
                    index += 1
                    continue
                }
                if let close = lines[(index + 1)...].firstIndex(where: {
                    $0.trimmingCharacters(in: .whitespaces).hasSuffix("$$")
                }) {
                    var body = afterOpen.isEmpty ? [] : [afterOpen]
                    body += lines[(index + 1)..<close].map { $0.trimmingCharacters(in: .whitespaces) }
                    let last = String(lines[close].trimmingCharacters(in: .whitespaces).dropLast(2))
                    if !last.isEmpty { body.append(last) }
                    out += mathFence(body.joined(separator: "\n"), indent: indent)
                    index = close + 1
                    continue
                }
            }

            out.append(protectInline(line))
            index += 1
        }
        return out.joined(separator: "\n")
    }

    // MARK: - Blocks

    private static func fenceRun(_ trimmed: String) -> (char: Character, count: Int)? {
        guard let first = trimmed.first, first == "`" || first == "~" else { return nil }
        return (first, trimmed.prefix(while: { $0 == first }).count)
    }

    private static func mathFence(_ latex: String, indent: String) -> [String] {
        let ticks = String(repeating: "`", count: max(3, longestRun(of: "`", in: latex) + 1))
        let body = latex.split(separator: "\n", omittingEmptySubsequences: false).map { indent + $0 }
        return [indent + ticks + "math"] + body + [indent + ticks]
    }

    // MARK: - Inline

    /// `$x$` → `` `\u{E000}x` ``, using pandoc's rules so prices are not mistaken for math:
    /// the opening `$` must be followed by a non-space, the closing one preceded by a non-space
    /// and not followed by a digit.
    static func protectInline(_ line: String) -> String {
        guard line.contains("$") else { return line }
        let chars = Array(line)
        var out = ""
        var i = 0

        while i < chars.count {
            let c = chars[i]
            if c == "\\", i + 1 < chars.count {
                out.append(c); out.append(chars[i + 1]); i += 2
                continue
            }
            // Copy a code span through untouched
            if c == "`" {
                let run = chars[i...].prefix(while: { $0 == "`" }).count
                if let end = closingRun(of: run, in: chars, from: i + run) {
                    out += String(chars[i..<(end + run)])
                    i = end + run
                } else {
                    out += String(repeating: "`", count: run)
                    i += run
                }
                continue
            }
            if c == "$", i + 1 < chars.count, chars[i + 1] != "$", !chars[i + 1].isWhitespace,
               let end = closingDollar(in: chars, from: i + 1) {
                let latex = String(chars[(i + 1)..<end])
                if latex.contains("`") {
                    out += String(chars[i...end])
                } else {
                    out += "`\(marker)\(latex)`"
                }
                i = end + 1
                continue
            }
            out.append(c)
            i += 1
        }
        return out
    }

    private static func closingDollar(in chars: [Character], from start: Int) -> Int? {
        var j = start
        while j < chars.count {
            if chars[j] == "\\" { j += 2; continue }
            if chars[j] == "$" {
                let before = chars[j - 1]
                let after = j + 1 < chars.count ? chars[j + 1] : nil
                if !before.isWhitespace, !(after?.isNumber ?? false) { return j }
                return nil
            }
            j += 1
        }
        return nil
    }

    private static func closingRun(of length: Int, in chars: [Character], from start: Int) -> Int? {
        var j = start
        while j < chars.count {
            if chars[j] == "`" {
                let run = chars[j...].prefix(while: { $0 == "`" }).count
                if run == length { return j }
                j += run
            } else {
                j += 1
            }
        }
        return nil
    }

    private static func longestRun(of char: Character, in text: String) -> Int {
        var longest = 0, current = 0
        for c in text {
            current = c == char ? current + 1 : 0
            longest = max(longest, current)
        }
        return longest
    }
}

/// Marks a run of an AttributedString as inline math; the value is the TeX source
enum InlineMathAttribute: AttributedStringKey {
    typealias Value = String
    static let name = "domark.inlineMath"
}
