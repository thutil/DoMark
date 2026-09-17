import AppKit
import SwiftUI

/// Light/dark choice.
///
/// The app follows the system by default. The override exists because a reader is often
/// used against a fixed backdrop — a bright room, a projector, a dark editor next to it —
/// and people want the page to stay put regardless of what the rest of the Mac is doing.
enum AppearanceSetting: String, CaseIterable {
    case system, light, dark

    static let key = "appearance"

    var label: String {
        switch self {
        case .system: "Match System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    private var appearance: NSAppearance? {
        switch self {
        case .system: nil // nil hands control back to the system
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    @MainActor
    func apply() {
        NSApp?.appearance = appearance
    }

    static var current: AppearanceSetting {
        AppearanceSetting(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .system
    }
}
