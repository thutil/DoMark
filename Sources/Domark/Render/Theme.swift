import AppKit
import SwiftUI

/// Every size, colour and spacing derives from one number — change `base` and the whole page scales.
struct Theme: Equatable, Sendable {
    var base: CGFloat
    /// Family for everything the reader reads; empty means the system font
    var prose: String = ""
    /// Family for code blocks and the editor pane
    var code: String = ""

    static let minBase: CGFloat = 11
    static let maxBase: CGFloat = 28
    static let defaultBase: CGFloat = 15

    // MARK: Fonts

    var body: Font { Fonts.body(family: prose, size: base) }

    func heading(_ level: Int) -> Font {
        Fonts.body(
            family: prose,
            size: base * Theme.headingScale(level),
            weight: level <= 2 ? .bold : .semibold
        )
    }

    static func headingScale(_ level: Int) -> CGFloat {
        switch level {
        case 1: 2.00
        case 2: 1.55
        case 3: 1.28
        case 4: 1.12
        case 5: 1.00
        default: 0.92
        }
    }

    var mono: Font { Fonts.mono(family: code, size: base * 0.90) }
    var caption: Font { Fonts.body(family: prose, size: base * 0.78) }

    // MARK: Spacing

    /// Thai stacks vowels and tone marks above and below the line, and the reading face may be
    /// drawn larger than `base` — so leading is measured against the size the text is really set at.
    var paragraphLeading: CGFloat { base * Fonts.opticalScale(for: prose) * 0.40 }
    var headingLeading: CGFloat { base * Fonts.opticalScale(for: prose) * 0.18 }

    var blockSpacing: CGFloat { base * 0.95 }
    var listSpacing: CGFloat { base * 0.42 }
    var listIndent: CGFloat { base * 1.55 }
    var contentWidth: CGFloat { max(560, base * 46) }
    var pagePadding: CGFloat { base * 2.6 }

    // MARK: Colours (all semantic, so they follow the system theme)

    // `Color.secondary` already carries ~50% alpha, so multiplying it again landed at 6%
    // instead of the intended 13%. `textColor` is fully opaque, so this percentage is real.
    var codeBackground: Color { Color(nsColor: .textColor).opacity(0.075) }
    var rule: Color { Color(nsColor: .separatorColor) }
    var quoteBar: Color { Color.accentColor.opacity(0.55) }

    // Find highlights are drawn on top of body text in both appearances, so they are fixed
    // hues rather than semantic colours — a system colour would vanish in one of the two themes.
    var findHighlight: Color { Color.yellow.opacity(0.32) }
    var findCurrentHighlight: Color { Color.orange.opacity(0.85) }
    var findCurrentText: Color { Color.black }
}
