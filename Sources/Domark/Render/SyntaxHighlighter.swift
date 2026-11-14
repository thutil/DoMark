import AppKit
import SwiftUI

/// Colours a fenced code block by language.
///
/// A small hand-written scanner rather than a grammar engine: one table of rules per language
/// (keywords, comment and string delimiters, a few flags) drives the same loop. It gets the
/// things a reader's eye uses — comments, strings, keywords, numbers, types, calls — and is
/// wrong only in ways that stay local to a line. A block with no language, or one not listed
/// here, is left as plain text: guessing the language and getting it wrong looks worse than
/// no colour at all.
enum SyntaxHighlighter {
    static func highlight(_ code: String, language name: String?) -> AttributedString {
        guard let name, let language = Language.named(name) else { return AttributedString(code) }
        let tokens = switch language.mode {
        case .code: Scanner(language: language, text: Array(code)).scan()
        case .markup: MarkupScanner(text: Array(code)).scan()
        case .diff: diffTokens(code)
        }
        return attributed(tokens)
    }

    // MARK: - Output

    private static func attributed(_ tokens: [(TokenKind, String)]) -> AttributedString {
        var out = AttributedString()
        for (kind, text) in tokens {
            var run = AttributedString(text)
            if let color = SyntaxPalette.color(for: kind) { run.foregroundColor = color }
            out.append(run)
        }
        return out
    }

    /// Diff is coloured by whole line — what was added, removed, and where
    private static func diffTokens(_ code: String) -> [(TokenKind, String)] {
        let lines = code.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.enumerated().map { index, line in
            let kind: TokenKind =
                if line.hasPrefix("+++") || line.hasPrefix("---") || line.hasPrefix("diff ") || line.hasPrefix("index ") {
                    .keyword
                } else if line.hasPrefix("@@") {
                    .attribute
                } else if line.hasPrefix("+") {
                    .inserted
                } else if line.hasPrefix("-") {
                    .deleted
                } else {
                    .plain
                }
            return (kind, String(line) + (index < lines.count - 1 ? "\n" : ""))
        }
    }
}

enum TokenKind {
    case plain, keyword, string, comment, number, type, function, attribute, inserted, deleted
}

/// Xcode's Default (Light) and Default (Dark) colours. Dynamic, so a change of appearance
/// redraws in the other set without re-parsing the document.
enum SyntaxPalette {
    static func color(for kind: TokenKind) -> Color? {
        switch kind {
        case .plain: nil
        case .keyword: keyword
        case .string: string
        case .comment: comment
        case .number: number
        case .type: type
        case .function: function
        case .attribute: attribute
        case .inserted: inserted
        case .deleted: deleted
        }
    }

    private static let keyword = dynamic(light: 0x9B2393, dark: 0xFF7AB2)
    private static let string = dynamic(light: 0xC41A16, dark: 0xFF8170)
    private static let comment = dynamic(light: 0x5D6C79, dark: 0x7F8C98)
    private static let number = dynamic(light: 0x1C00CF, dark: 0xD9C97C)
    private static let type = dynamic(light: 0x0B4F79, dark: 0xDABAFF)
    private static let function = dynamic(light: 0x326D74, dark: 0x67B7A4)
    private static let attribute = dynamic(light: 0x815F03, dark: 0xFFA14F)
    private static let inserted = dynamic(light: 0x1A7F37, dark: 0x3FB950)
    private static let deleted = dynamic(light: 0xCF222E, dark: 0xF85149)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

// MARK: - Language rules

struct Language: Sendable {
    enum Mode: Sendable { case code, markup, diff }

    var mode: Mode = .code
    var keywords: Set<String> = []
    var types: Set<String> = []
    var lineComments: [String] = []
    var blockComment: (open: String, close: String)?
    var quotes: Set<Character> = ["\"", "'"]
    /// `"""` strings (Swift, Python, Dart, Kotlin)
    var tripleQuotes = false
    /// SQL
    var caseInsensitive = false
    /// `Foo` is a type in languages that capitalise type names by convention
    var capitalizedAreTypes = false
    /// `@MainActor`, `@override`, Python decorators, CSS at-rules
    var attributePrefix = false
    /// `#if`, `#include`, Rust's `#[derive]`
    var hashDirectives = false
    /// Shell `$VAR`, `${VAR}`
    var shellVariables = false
    /// JSON/YAML keys and CSS properties: a word or string followed by `:`
    var keysBeforeColon = false
    /// CSS `#fff`
    var hashColors = false
    /// Characters besides letters, digits and `_` that may sit inside a word (`-` in CSS and YAML)
    var wordExtras: Set<Character> = []

    static func named(_ raw: String) -> Language? {
        // Info strings may carry more than the language: ```swift title="x"
        let name = raw.lowercased().split(whereSeparator: { $0 == " " || $0 == "{" || $0 == "," }).first.map(String.init) ?? ""
        return switch name {
        case "swift": swift
        case "dart", "flutter": dart
        case "js", "javascript", "jsx", "mjs", "cjs", "node": javaScript
        case "ts", "typescript", "tsx": typeScript
        case "py", "python", "python3": python
        case "sh", "bash", "zsh", "shell", "console", "shellscript": shell
        case "json", "jsonc", "json5": json
        case "yaml", "yml": yaml
        case "sql", "postgres", "postgresql", "mysql", "sqlite", "plsql": sql
        case "html", "xml", "xhtml", "svg", "plist", "htm": Language(mode: .markup)
        case "css", "scss", "less": css
        case "diff", "patch": Language(mode: .diff)
        case "go", "golang": go
        case "rs", "rust": rust
        case "kt", "kotlin", "kts", "java": kotlinJava
        case "c", "h", "cpp", "c++", "cc", "hpp", "cxx", "objc", "objective-c": cFamily
        default: nil
        }
    }

    private static func words(_ list: String) -> Set<String> {
        Set(list.split(separator: " ").map(String.init))
    }

    private static let cComments = (lineComments: ["//"], blockComment: (open: "/*", close: "*/"))

    static let swift = Language(
        keywords: words("""
        associatedtype class deinit enum extension fileprivate func import init inout internal let open operator \
        private precedencegroup protocol public rethrows static struct subscript typealias var break case catch \
        continue default defer do else fallthrough for guard if in repeat return throw switch where while as Any \
        false is nil self Self super throws true try await async actor some any mutating nonmutating override final \
        lazy weak unowned convenience required dynamic indirect optional get set willSet didSet nonisolated isolated \
        consume borrowing consuming sending package macro
        """),
        lineComments: cComments.lineComments, blockComment: cComments.blockComment,
        quotes: ["\""], tripleQuotes: true, capitalizedAreTypes: true, attributePrefix: true, hashDirectives: true
    )

    static let dart = Language(
        keywords: words("""
        abstract as assert async await base break case catch class const continue covariant default deferred do \
        dynamic else enum export extends extension external factory false final finally for Function get hide if \
        implements import in interface is late library mixin new null on operator part required rethrow return \
        sealed set show static super switch sync this throw true try typedef var void when while with yield
        """),
        types: words("int double num bool String List Map Set Future Stream Object dynamic Never"),
        lineComments: cComments.lineComments, blockComment: cComments.blockComment,
        tripleQuotes: true, capitalizedAreTypes: true, attributePrefix: true
    )

    private static let jsKeywords = """
    break case catch class const continue debugger default delete do else export extends finally for function \
    if import in instanceof new return super switch this throw try typeof var void while with yield let static \
    async await of from as get set null undefined true false NaN Infinity
    """

    static let javaScript = Language(
        keywords: words(jsKeywords),
        lineComments: cComments.lineComments, blockComment: cComments.blockComment,
        quotes: ["\"", "'", "`"], capitalizedAreTypes: true, attributePrefix: true
    )

    static let typeScript = Language(
        keywords: words(jsKeywords + """
         interface type enum implements namespace declare abstract private protected public readonly keyof infer \
        is unique never unknown any satisfies
        """),
        types: words("string number boolean object symbol bigint"),
        lineComments: cComments.lineComments, blockComment: cComments.blockComment,
        quotes: ["\"", "'", "`"], capitalizedAreTypes: true, attributePrefix: true
    )

    static let python = Language(
        keywords: words("""
        False None True and as assert async await break class continue def del elif else except finally for from \
        global if import in is lambda nonlocal not or pass raise return try while with yield match case self cls
        """),
        types: words("int str float bool list dict set tuple bytes object type"),
        lineComments: ["#"], tripleQuotes: true, capitalizedAreTypes: true, attributePrefix: true
    )

    static let shell = Language(
        keywords: words("""
        if then else elif fi case esac for while until do done in function return break continue local export \
        readonly declare unset set shift exit source alias echo cd test true false time select sudo
        """),
        lineComments: ["#"], quotes: ["\"", "'", "`"], shellVariables: true
    )

    static let json = Language(
        keywords: words("true false null"),
        lineComments: cComments.lineComments, blockComment: cComments.blockComment,
        quotes: ["\""], keysBeforeColon: true
    )

    static let yaml = Language(
        keywords: words("true false null yes no on off True False Null"),
        lineComments: ["#"], keysBeforeColon: true, wordExtras: ["-", "."]
    )

    static let sql = Language(
        keywords: words("""
        select from where and or not insert into values update set delete create table drop alter add column \
        index primary key foreign references join inner left right outer full cross on as group by order having \
        limit offset union all distinct case when then else end null is in like ilike between exists default \
        unique check constraint view with returning begin commit rollback transaction if replace asc desc true false
        """),
        types: words("int integer text varchar char boolean bool date timestamp timestamptz serial bigint float real numeric uuid jsonb json"),
        lineComments: ["--"], blockComment: cComments.blockComment, caseInsensitive: true
    )

    static let css = Language(
        keywords: words("important inherit initial unset none auto"),
        blockComment: cComments.blockComment,
        attributePrefix: true, keysBeforeColon: true, hashColors: true, wordExtras: ["-"]
    )

    static let go = Language(
        keywords: words("""
        break case chan const continue default defer else fallthrough for func go goto if import interface map \
        package range return select struct switch type var nil true false iota
        """),
        types: words("""
        bool byte complex64 complex128 error float32 float64 int int8 int16 int32 int64 rune string uint uint8 \
        uint16 uint32 uint64 uintptr any
        """),
        lineComments: cComments.lineComments, blockComment: cComments.blockComment,
        quotes: ["\"", "'", "`"]
    )

    static let rust = Language(
        keywords: words("""
        as async await break const continue crate dyn else enum extern false fn for if impl in let loop match mod \
        move mut pub ref return self Self static struct super trait true type unsafe use where while Some None Ok Err
        """),
        types: words("i8 i16 i32 i64 i128 isize u8 u16 u32 u64 u128 usize f32 f64 bool char str"),
        lineComments: cComments.lineComments, blockComment: cComments.blockComment,
        // No `'` — it opens lifetimes (`'a`) far more often than char literals
        quotes: ["\""], capitalizedAreTypes: true, hashDirectives: true
    )

    static let kotlinJava = Language(
        keywords: words("""
        abstract assert boolean break byte case catch char class const continue default do double else enum \
        extends final finally float for if implements import instanceof int interface long native new package \
        private protected public return short static super switch synchronized this throw throws transient try \
        void volatile while var val fun when is in object companion data sealed override open internal lateinit by \
        init suspend inline reified null true false typealias record yield
        """),
        lineComments: cComments.lineComments, blockComment: cComments.blockComment,
        tripleQuotes: true, capitalizedAreTypes: true, attributePrefix: true
    )

    static let cFamily = Language(
        keywords: words("""
        auto break case char const continue default do double else enum extern float for goto if inline int long \
        register restrict return short signed sizeof static struct switch typedef union unsigned void volatile \
        while bool class namespace template typename public private protected virtual override new delete this \
        nullptr true false using try catch throw constexpr noexcept operator friend explicit mutable static_cast \
        dynamic_cast reinterpret_cast const_cast decltype NULL
        """),
        lineComments: cComments.lineComments, blockComment: cComments.blockComment,
        hashDirectives: true
    )
}

// MARK: - Scanners

/// The rule-driven scanner every `.code` language shares
private struct Scanner {
    let language: Language
    let text: [Character]
    private var tokens: [(TokenKind, String)] = []
    private var plain = ""
    private var i = 0

    init(language: Language, text: [Character]) {
        self.language = language
        self.text = text
    }

    consuming func scan() -> [(TokenKind, String)] {
        while i < text.count {
            let ch = text[i]

            if language.shellVariables, ch == "$", i + 1 < text.count {
                emit(.attribute, upTo: shellVariableEnd())
            } else if let end = commentEnd() {
                emit(.comment, upTo: end)
            } else if language.tripleQuotes, starts(with: "\"\"\"") {
                emit(.string, upTo: closing("\"\"\"", from: i + 3))
            } else if language.quotes.contains(ch) {
                let end = stringEnd(quote: ch)
                emit(isKey(after: end) ? .attribute : .string, upTo: end)
            } else if ch.isASCII, ch.isNumber, !isWordChar(at: i - 1) {
                emit(.number, upTo: wordEnd(from: i + 1, extras: ["."]))
            } else if language.hashColors, ch == "#", i + 1 < text.count, text[i + 1].isHexDigit {
                emit(.number, upTo: wordEnd(from: i + 1))
            } else if language.attributePrefix, ch == "@", i + 1 < text.count, text[i + 1].isLetter {
                emit(.attribute, upTo: wordEnd(from: i + 1))
            } else if language.hashDirectives, ch == "#", let end = directiveEnd() {
                emit(.attribute, upTo: end)
            } else if isWordStart(ch) {
                let end = wordEnd(from: i + 1)
                emit(kind(ofWord: String(text[i..<end]), end: end), upTo: end)
            } else {
                plain.append(ch)
                i += 1
            }
        }
        flush()
        return tokens
    }

    // MARK: Pieces

    private func commentEnd() -> Int? {
        if let block = language.blockComment, starts(with: block.open) {
            return closing(block.close, from: i + block.open.count)
        }
        for marker in language.lineComments where starts(with: marker) {
            // `#` only opens a comment at the start of a word — `a#b` and `$#` are not comments
            if marker == "#", i > 0, !text[i - 1].isWhitespace { continue }
            return lineEnd(from: i)
        }
        return nil
    }

    /// Strings stop at the end of the line unless the quote is a backtick: a stray apostrophe
    /// in prose-like code (`don't`) then colours one line, not the rest of the block.
    private func stringEnd(quote: Character) -> Int {
        var j = i + 1
        while j < text.count {
            let c = text[j]
            if c == "\\" { j += 2; continue }
            if c == quote { return j + 1 }
            if c == "\n", quote != "`" { return j }
            j += 1
        }
        return text.count
    }

    private func shellVariableEnd() -> Int {
        let next = text[i + 1]
        if next == "{" { return min(closing("}", from: i + 2), text.count) }
        if isWordStart(next) { return wordEnd(from: i + 2) }
        return i + 2 // $1, $?, $#, $@
    }

    private func directiveEnd() -> Int? {
        guard i + 1 < text.count else { return nil }
        if text[i + 1] == "[" { return closing("]", from: i + 2) }
        // Only at the start of a line — `#` elsewhere is an operator or part of a string
        var k = i - 1
        while k >= 0, text[k] == " " || text[k] == "\t" { k -= 1 }
        guard k < 0 || text[k] == "\n", text[i + 1].isLetter else { return nil }
        return wordEnd(from: i + 1)
    }

    private func kind(ofWord word: String, end: Int) -> TokenKind {
        let key = language.caseInsensitive ? word.lowercased() : word
        if language.keywords.contains(key) { return .keyword }
        if isKey(after: end) { return .attribute }
        if language.types.contains(key) { return .type }
        if language.capitalizedAreTypes, word.first?.isUppercase == true { return .type }
        if nextNonSpace(from: end) == "(" { return .function }
        return .plain
    }

    private func isKey(after end: Int) -> Bool {
        language.keysBeforeColon && nextNonSpace(from: end) == ":"
    }

    // MARK: Helpers

    private func isWordStart(_ c: Character) -> Bool { c.isLetter || c == "_" }

    private func isWordChar(at index: Int) -> Bool {
        guard index >= 0, index < text.count else { return false }
        let c = text[index]
        return c.isLetter || c.isNumber || c == "_" || language.wordExtras.contains(c)
    }

    private func wordEnd(from start: Int, extras: Set<Character> = []) -> Int {
        var j = start
        while j < text.count, isWordChar(at: j) || extras.contains(text[j]) { j += 1 }
        return j
    }

    private func lineEnd(from start: Int) -> Int {
        var j = start
        while j < text.count, text[j] != "\n" { j += 1 }
        return j
    }

    /// Index just past `marker`, or the end of the text when it never closes
    private func closing(_ marker: String, from start: Int) -> Int {
        let m = Array(marker)
        var j = start
        while j + m.count <= text.count {
            if Array(text[j..<(j + m.count)]) == m { return j + m.count }
            j += 1
        }
        return text.count
    }

    private func starts(with marker: String) -> Bool {
        let m = Array(marker)
        guard i + m.count <= text.count else { return false }
        return Array(text[i..<(i + m.count)]) == m
    }

    private func nextNonSpace(from start: Int) -> Character? {
        var j = start
        while j < text.count, text[j] == " " || text[j] == "\t" { j += 1 }
        return j < text.count ? text[j] : nil
    }

    private mutating func emit(_ kind: TokenKind, upTo end: Int) {
        let end = max(end, i + 1)
        let piece = String(text[i..<min(end, text.count)])
        i = min(end, text.count)
        if kind == .plain {
            plain += piece
        } else {
            flush()
            tokens.append((kind, piece))
        }
    }

    private mutating func flush() {
        guard !plain.isEmpty else { return }
        tokens.append((.plain, plain))
        plain = ""
    }
}

/// HTML and XML: tag names, attribute names, attribute values and comments
private struct MarkupScanner {
    let text: [Character]

    func scan() -> [(TokenKind, String)] {
        var tokens: [(TokenKind, String)] = []
        var plain = ""
        var i = 0

        func flush() {
            if !plain.isEmpty { tokens.append((.plain, plain)); plain = "" }
        }
        func push(_ kind: TokenKind, _ start: Int, _ end: Int) {
            flush()
            tokens.append((kind, String(text[start..<end])))
        }
        func has(_ s: String, at index: Int) -> Bool {
            let m = Array(s)
            return index + m.count <= text.count && Array(text[index..<(index + m.count)]) == m
        }

        while i < text.count {
            if has("<!--", at: i) {
                var j = i + 4
                while j < text.count, !has("-->", at: j) { j += 1 }
                let end = min(j + 3, text.count)
                push(.comment, i, end)
                i = end
            } else if text[i] == "<", i + 1 < text.count, text[i + 1].isLetter || "/!?".contains(text[i + 1]) {
                // The opening bracket and any `/`, `!` or `?` stay plain; the name is the keyword
                var j = i + 1
                while j < text.count, "/!?".contains(text[j]) { j += 1 }
                plain += String(text[i..<j])
                var k = j
                while k < text.count, text[k].isLetter || text[k].isNumber || "-:_.".contains(text[k]) { k += 1 }
                if k > j { push(.keyword, j, k) }
                i = k
                // Inside the tag until `>`
                while i < text.count, text[i] != ">" {
                    let c = text[i]
                    if c == "\"" || c == "'" {
                        var e = i + 1
                        while e < text.count, text[e] != c { e += 1 }
                        let end = min(e + 1, text.count)
                        push(.string, i, end)
                        i = end
                    } else if c.isLetter {
                        var e = i
                        while e < text.count, text[e].isLetter || text[e].isNumber || "-:_.".contains(text[e]) { e += 1 }
                        push(.attribute, i, e)
                        i = e
                    } else {
                        plain.append(c)
                        i += 1
                    }
                }
            } else {
                plain.append(text[i])
                i += 1
            }
        }
        flush()
        return tokens
    }
}
