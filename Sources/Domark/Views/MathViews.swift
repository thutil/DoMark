import AppKit
import SwiftMath
import SwiftUI

/// Typesets TeX with SwiftMath into images, once per formula, size and appearance.
///
/// The image is drawn by a handler rather than captured as a bitmap, so it stays sharp at any
/// zoom and on any display. The baseline comes back with it, so inline math sits on the line
/// of text instead of on its bottom edge.
@MainActor
enum MathRenderer {
    struct Typeset {
        let image: NSImage
        /// Distance from the bottom of the image up to the formula's baseline
        let descent: CGFloat
    }

    enum Outcome {
        case typeset(Typeset)
        case failed(String)
    }

    private struct Key: Hashable {
        let latex: String
        let size: CGFloat
        let display: Bool
        let dark: Bool
    }

    private static var cache: [Key: Outcome] = [:]

    static func render(_ latex: String, size: CGFloat, display: Bool, dark: Bool) -> Outcome {
        let key = Key(latex: latex, size: size, display: display, dark: dark)
        if let cached = cache[key] { return cached }
        let outcome = typeset(latex, size: size, display: display, dark: dark)
        if cache.count > 500 { cache.removeAll() }
        cache[key] = outcome
        return outcome
    }

    private static func typeset(_ latex: String, size: CGFloat, display: Bool, dark: Bool) -> Outcome {
        let label = MTMathUILabel()
        label.displayErrorInline = false
        label.labelMode = display ? .display : .text
        label.textAlignment = .left
        label.fontSize = size
        label.textColor = textColor(dark: dark)
        label.latex = latex
        if let error = label.error { return .failed(error.localizedDescription) }

        let fitting = label.fittingSize
        guard fitting.width > 0, fitting.height > 0 else { return .failed("Empty formula") }
        label.frame = CGRect(origin: .zero, size: fitting)
        label.layout()
        guard let displayList = label.displayList else { return .failed("Could not lay out the formula") }

        // NSImage keeps the handler and calls it again whenever it is drawn at a new scale
        nonisolated(unsafe) let list = displayList
        let image = NSImage(size: fitting, flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            list.draw(context)
            return true
        }
        // Where the label put the baseline — its layout is mirrored here because the
        // position itself is internal to SwiftMath. A very short formula is centred on half the font size.
        let height = displayList.ascent + displayList.descent
        let baseline = (height - max(height, size / 2)) / 2 + displayList.descent
        return .typeset(Typeset(image: image, descent: baseline))
    }

    /// The text colour as it resolves in that appearance — a dynamic colour would resolve
    /// against whatever happens to be current when the image is drawn
    private static func textColor(dark: Bool) -> NSColor {
        var color = NSColor.textColor
        NSAppearance(named: dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
            color = NSColor.textColor.usingColorSpace(.sRGB) ?? color
        }
        return color
    }
}

/// `$$…$$`: centred on its own line, scrolling sideways when wider than the column.
/// A formula SwiftMath cannot read is shown as its source with the reason under it.
struct MathBlockView: View {
    let latex: String
    let theme: Theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        switch MathRenderer.render(latex, size: theme.base * 1.2, display: true, dark: colorScheme == .dark) {
        case let .typeset(typeset):
            ScrollView(.horizontal) {
                Image(nsImage: typeset.image)
                    .help(latex)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .defaultScrollAnchor(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, theme.base * 0.3)

        case let .failed(reason):
            VStack(alignment: .leading, spacing: theme.base * 0.4) {
                CodeBlockView(language: "math", code: AttributedString(latex), isWide: false, theme: theme)
                Label(reason, systemImage: "exclamationmark.triangle")
                    .font(theme.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// A paragraph with `$…$` in it. Text runs and typeset formulas are joined into one `Text`,
/// so they wrap together like words.
struct InlineMathText: View {
    let text: AttributedString
    let theme: Theme
    @Environment(\.colorScheme) private var colorScheme

    static func containsMath(_ text: AttributedString) -> Bool {
        text.runs[InlineMathAttribute.self].contains { $0.0 != nil }
    }

    var body: some View {
        var result = Text(verbatim: "")
        for (latex, range) in text.runs[InlineMathAttribute.self] {
            let piece = Text(AttributedString(text[range]))
            guard let latex else {
                result = Text("\(result)\(piece)")
                continue
            }
            switch MathRenderer.render(latex, size: theme.base * 1.05, display: false, dark: colorScheme == .dark) {
            case let .typeset(typeset):
                let formula = Text(Image(nsImage: typeset.image)).baselineOffset(-typeset.descent)
                result = Text("\(result)\(formula)")
            case .failed:
                // Unreadable TeX stays visible as its source
                result = Text("\(result)\(piece)")
            }
        }
        return result
    }
}
