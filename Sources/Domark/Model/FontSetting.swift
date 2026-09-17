import AppKit
import Foundation

/// Where the two typeface choices live, and what is on offer.
///
/// Only family names are stored — the weight, the italic and the size are decided per use by
/// `Fonts`, so a stored choice keeps working when the same family is asked for in bold or at
/// heading size. An empty name means the system font, which is also what a family that has since
/// been uninstalled falls back to.
enum FontSetting {
    static let proseKey = "proseFontFamily"
    static let codeKey = "codeFontFamily"

    /// The reading face the app shipped with, when it is installed
    static let defaultProse: String = FontCatalog.isInstalled("TH Sarabun New") ? "TH Sarabun New" : ""

    /// The system monospaced font — the editor's own default
    static let defaultCode = ""
}

/// The families installed on this Mac, grouped the way each picker wants them.
///
/// Every list is built once, on first use: asking for a font per family is too slow to redo
/// each time the Settings window draws.
enum FontCatalog {
    static let systemLabel = "System"

    static func label(for family: String) -> String {
        family.isEmpty ? systemLabel : family
    }

    static let families: [String] = NSFontManager.shared.availableFontFamilies.sorted()

    static func isInstalled(_ family: String) -> Bool { families.contains(family) }

    /// Worth listing first for reading: these draw Thai themselves instead of leaning on the fallback
    static let thaiFamilies: [String] = families.filter { covers(thai, in: $0) }

    /// Worth listing first for the editor, where the columns have to line up
    static let monospacedFamilies: [String] = families.filter { isMonospaced($0) }

    private static let thai = UnicodeScalar(0x0E01)! // ก

    private static func sample(_ family: String) -> NSFont? {
        NSFont(descriptor: NSFontDescriptor(fontAttributes: [.family: family]), size: 12)
    }

    private static func covers(_ scalar: UnicodeScalar, in family: String) -> Bool {
        sample(family)?.coveredCharacterSet.contains(scalar) ?? false
    }

    private static func isMonospaced(_ family: String) -> Bool {
        sample(family)?.fontDescriptor.symbolicTraits.contains(.monoSpace) ?? false
    }
}
