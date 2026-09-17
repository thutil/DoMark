import AppKit
import SwiftUI

/// Builds every font the app uses, from the two families the user picks in Settings:
/// one for reading, one for code and the editor.
///
/// Two things are handled here so that no view — and no font picker — has to think about them:
///
/// * **Optical size.** Faces differ wildly in how large they draw at the same point size:
///   TH Sarabun New's x-height is 5.10 where the system font's is 7.90 at 15 pt. Every size is
///   multiplied by the family's x-height ratio, so `Theme.base` keeps meaning the same thing
///   whichever face is chosen, and ⌘+ lands where the reader expects.
/// * **Thai coverage.** A family that cannot draw Thai gets Noto Sans Thai in its *cascade list*:
///   one font object, no per-run script detection, and mixed Thai/English on one line still sits
///   on a single baseline. A cascade entry is always drawn at the base font's size — a matrix or
///   size attribute on it is ignored — which is why the optical scale has to be applied to the
///   font itself and never to the fallback.
///
/// Everything is memoised. Matching a descriptor is not cheap and a long document asks for the
/// same handful of styles thousands of times while parsing.
enum Fonts {
    /// An empty family name means "whatever the system provides"
    static let systemFamily = ""

    /// Thai inside a family that has no Thai of its own
    static let thaiFallbackFamily = "Noto Sans Thai"

    // MARK: - SwiftUI

    static func body(family: String, size: CGFloat, weight: NSFont.Weight = .regular, italic: Bool = false) -> Font {
        cache.font(FontKey(family: family, size: size, weight: weight, italic: italic, mono: false))
    }

    static func mono(family: String, size: CGFloat, weight: NSFont.Weight = .regular) -> Font {
        cache.font(FontKey(family: family, size: size, weight: weight, italic: false, mono: true))
    }

    // MARK: - AppKit (the editor needs a real NSFont)

    static func nsBody(family: String, size: CGFloat, weight: NSFont.Weight = .regular, italic: Bool = false) -> NSFont {
        cache.nsFont(FontKey(family: family, size: size, weight: weight, italic: italic, mono: false))
    }

    static func nsMono(family: String, size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        cache.nsFont(FontKey(family: family, size: size, weight: weight, italic: false, mono: true))
    }

    /// How much larger this family has to be drawn to read like the system font.
    /// Spacing that has to follow the text — leading above all — is measured against this.
    static func opticalScale(for family: String) -> CGFloat {
        cache.scale(family)
    }

    // MARK: - Building

    /// `scale` is passed in rather than looked up, so that building a font never reaches back
    /// into the cache that is already locked around this call
    fileprivate static func make(_ key: FontKey, scale: CGFloat) -> NSFont {
        let size = key.size * scale
        let font = resolve(key, size: size)
        return coversThai(font) ? font : cascadingToThai(font, size: size, weight: key.weight)
    }

    private static func resolve(_ key: FontKey, size: CGFloat) -> NSFont {
        let system = key.mono
            ? NSFont.monospacedSystemFont(ofSize: size, weight: key.weight)
            : NSFont.systemFont(ofSize: size, weight: key.weight)

        guard !key.family.isEmpty else { return leaning(system, italic: key.italic, size: size) }

        // Descriptor matching rather than NSFontManager: parsing runs off the main thread and
        // NSFontManager is a UI object. CoreText picks the nearest weight the family actually ships.
        //
        // Italic is asked for afterwards, never as part of this match: a family with no italic
        // would otherwise match some *other* family that has one, and the user's choice would
        // silently disappear on every emphasised word.
        let descriptor = NSFontDescriptor(fontAttributes: [
            .family: key.family,
            .traits: [NSFontDescriptor.TraitKey.weight: key.weight.rawValue],
        ])
        guard let matched = NSFont(descriptor: descriptor, size: size),
              matched.familyName == key.family
        else {
            // The family was uninstalled since it was picked
            return leaning(system, italic: key.italic, size: size)
        }
        return leaning(matched, italic: key.italic, size: size)
    }

    /// A family with no italic of its own keeps its upright shape — CoreText does not fake one,
    /// and swapping in a different family's italic would be worse than staying upright
    private static func leaning(_ font: NSFont, italic: Bool, size: CGFloat) -> NSFont {
        guard italic, !font.fontDescriptor.symbolicTraits.contains(.italic) else { return font }
        guard let slanted = NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(.italic), size: size),
              slanted.familyName == font.familyName
        else { return font }
        return slanted
    }

    fileprivate static func opticalScaleUncached(_ family: String) -> CGFloat {
        guard !family.isEmpty else { return 1 }
        // Measured big, so the ratio does not ride on hinting at small sizes
        let reference = NSFont.systemFont(ofSize: 100).xHeight
        let descriptor = NSFontDescriptor(fontAttributes: [.family: family])
        guard let font = NSFont(descriptor: descriptor, size: 100), font.xHeight > 0 else { return 1 }
        // Clamped: a display face with a freakish x-height should not blow the layout apart
        return min(max(reference / font.xHeight, 0.8), 1.8)
    }

    private static func coversThai(_ font: NSFont) -> Bool {
        font.coveredCharacterSet.contains(UnicodeScalar(0x0E01)!) // ก
    }

    /// Noto Sans Thai ships as static instances, so each weight is its own PostScript name
    private static let thaiNames: [NSFont.Weight: String] = [
        .ultraLight: "NotoSansThai-ExtraLight",
        .thin: "NotoSansThai-Thin",
        .light: "NotoSansThai-Light",
        .regular: "NotoSansThai-Regular",
        .medium: "NotoSansThai-Medium",
        .semibold: "NotoSansThai-SemiBold",
        .bold: "NotoSansThai-Bold",
        .heavy: "NotoSansThai-ExtraBold",
        .black: "NotoSansThai-Black",
    ]

    private static func cascadingToThai(_ font: NSFont, size: CGFloat, weight: NSFont.Weight) -> NSFont {
        guard let name = thaiNames[weight] ?? thaiNames[.regular],
              let thai = NSFont(name: name, size: size)
        else { return font }

        let descriptor = font.fontDescriptor.addingAttributes([
            .cascadeList: [thai.fontDescriptor]
        ])
        return NSFont(descriptor: descriptor, size: size) ?? font
    }

    private static let cache = FontCache()
}

fileprivate struct FontKey: Hashable {
    var family: String
    var size: CGFloat
    var weight: NSFont.Weight
    var italic: Bool
    var mono: Bool
}

/// Parsing happens off the main thread, so the cache has to be safe to reach from anywhere.
/// A plain lock beats an actor here: every lookup is a dictionary hit that must stay synchronous.
private final class FontCache: @unchecked Sendable {
    private let lock = NSLock()
    private var nsFonts: [FontKey: NSFont] = [:]
    private var fonts: [FontKey: Font] = [:]

    /// Its own lock: a font lookup needs the scale, and one lock for both would deadlock
    private let scaleLock = NSLock()
    private var scales: [String: CGFloat] = [:]

    func nsFont(_ key: FontKey) -> NSFont {
        let scale = scale(key.family)
        lock.lock()
        defer { lock.unlock() }
        return resolved(key, scale: scale)
    }

    func font(_ key: FontKey) -> Font {
        let scale = scale(key.family)
        lock.lock()
        defer { lock.unlock() }
        if let hit = fonts[key] { return hit }
        let font = Font(resolved(key, scale: scale) as CTFont)
        fonts[key] = font
        return font
    }

    func scale(_ family: String) -> CGFloat {
        scaleLock.lock()
        defer { scaleLock.unlock() }
        if let hit = scales[family] { return hit }
        let scale = Fonts.opticalScaleUncached(family)
        scales[family] = scale
        return scale
    }

    /// Callers hold `lock`
    private func resolved(_ key: FontKey, scale: CGFloat) -> NSFont {
        if let hit = nsFonts[key] { return hit }
        let made = Fonts.make(key, scale: scale)
        nsFonts[key] = made
        return made
    }
}
