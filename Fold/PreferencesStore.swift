import Foundation
import AppKit
import Observation

private let fontNameKey = "fold.fontName"
private let fontSizeKey = "fold.fontSize"

@MainActor
@Observable
final class PreferencesStore {

    var fontName: String {
        didSet {
            UserDefaults.standard.set(fontName, forKey: fontNameKey)
            NotificationCenter.default.post(name: .foldPrefsChanged, object: self)
        }
    }
    var fontSize: CGFloat {
        didSet {
            UserDefaults.standard.set(Double(fontSize), forKey: fontSizeKey)
            NotificationCenter.default.post(name: .foldPrefsChanged, object: self)
        }
    }

    init() {
        fontName = UserDefaults.standard.string(forKey: fontNameKey) ?? "SF Pro Text"
        let saved = UserDefaults.standard.double(forKey: fontSizeKey)
        fontSize = saved > 0 ? CGFloat(saved) : 18
    }

    var bodyFont: NSFont {
        NSFont(name: fontName, size: fontSize) ?? .systemFont(ofSize: fontSize)
    }

    // H1 = base × 1.4, H2 = base × 1.2, H3+ = base (proportionnel)
    var h1Font: NSFont { bold(size: round(fontSize * 1.4)) }
    var h2Font: NSFont { bold(size: round(fontSize * 1.2)) }
    var h3Font: NSFont { bold(size: fontSize) }
    var h4Font: NSFont { bold(size: fontSize) }
    var h5Font: NSFont { bold(size: fontSize) }
    var h6Font: NSFont { bold(size: fontSize) }

    func headingFont(level: Int) -> NSFont {
        switch level {
        case 1: return h1Font
        case 2: return h2Font
        default: return h3Font
        }
    }

    func zoomIn()    { if fontSize < 32 { fontSize += 1 } }
    func zoomOut()   { if fontSize > 10 { fontSize -= 1 } }
    func zoomReset() { fontSize = 18 }

    // Polices disponibles filtrées — lisibles pour du texte
    var availableFonts: [String] {
        let families = NSFontManager.shared.availableFontFamilies
        let preferred = ["Georgia", "Palatino", "Times New Roman", "Helvetica Neue",
                         "Arial", "Avenir", "Baskerville", "Optima", "Garamond",
                         "Charter", "New York", "SF Pro Text"]
        let filtered = families.filter { name in
            !name.hasPrefix(".") && !name.contains("Symbol") && !name.contains("Wingdings")
        }
        let sorted = preferred.filter { filtered.contains($0) } +
                     filtered.filter  { !preferred.contains($0) }
        return sorted
    }

    private func bold(size: CGFloat) -> NSFont {
        NSFont(name: fontName, size: size).flatMap {
            NSFontManager.shared.convert($0, toHaveTrait: .boldFontMask)
        } ?? .boldSystemFont(ofSize: size)
    }
}

