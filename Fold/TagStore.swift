import Foundation
import AppKit
import Observation

private let colorsKey = "fold.tagColors"

// Étiquettes par défaut avec leurs couleurs originales
let defaultTags: [String: String] = [
    "done":       "#FF383C",
    "inprogress": "#0088FF",
    "design":     "#FE5000"
]

@MainActor
@Observable
final class TagStore {

    var tagColors: [String: String] = [:]

    init() {
        load()
        for (tag, color) in defaultTags where tagColors[tag] == nil {
            tagColors[tag] = color
        }
        save()
    }

    // MARK: - Extraction @tags en fin de phrase/ligne

    static func extract(from content: String) -> [String] {
        let pattern = #"@(\w+)(?=\s*[.!?]?\s*$)"#
        guard let rx = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return [] }
        let range = NSRange(content.startIndex..., in: content)
        let matches = rx.matches(in: content, range: range)
        return Array(Set(matches.compactMap { m -> String? in
            guard let r = Range(m.range(at: 1), in: content) else { return nil }
            return String(content[r]).lowercased()
        })).sorted()
    }

    // MARK: - @done = texte barré

    static func isDoneTag(_ tag: String) -> Bool {
        tag.lowercased() == "done"
    }

    // MARK: - Classification

    var defaultTagNames: [String] { defaultTags.keys.sorted() }

    var customTagNames: [String] {
        tagColors.keys
            .filter { defaultTags[$0] == nil }
            .sorted()
    }

    func isDefault(_ tag: String) -> Bool {
        defaultTags[tag] != nil
    }

    // MARK: - Couleurs

    func color(for tag: String) -> NSColor {
        if let hex = tagColors[tag] {
            return NSColor(hex: hex) ?? .tertiaryLabelColor
        }
        return .tertiaryLabelColor
    }

    func swiftUIColor(for tag: String) -> Color {
        Color(nsColor: color(for: tag))
    }

    /// Enregistre la couleur d'un tag. C'est le seul endroit où un tag
    /// personnalisé est créé — uniquement quand l'utilisateur choisit une couleur.
    func setColor(_ hex: String, for tag: String) {
        tagColors[tag] = hex
        save()
    }

    /// Réinitialise une étiquette par défaut à sa couleur d'origine.
    func resetToDefault(_ tag: String) {
        guard let original = defaultTags[tag] else { return }
        tagColors[tag] = original
        save()
    }

    /// Supprime une étiquette personnalisée.
    func removeTag(_ tag: String) {
        guard !isDefault(tag) else { return }
        tagColors.removeValue(forKey: tag)
        save()
    }

    // MARK: - Persistance

    private func save() {
        UserDefaults.standard.set(tagColors, forKey: colorsKey)
    }

    private func load() {
        tagColors = UserDefaults.standard.dictionary(forKey: colorsKey) as? [String: String] ?? [:]
    }
}

// MARK: - NSColor hex

extension NSColor {
    convenience init?(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard h.count == 6, let val = UInt64(h, radix: 16) else { return nil }
        self.init(
            red:   CGFloat((val >> 16) & 0xff) / 255,
            green: CGFloat((val >> 8)  & 0xff) / 255,
            blue:  CGFloat( val        & 0xff) / 255,
            alpha: 1
        )
    }
    var hexString: String {
        guard let c = usingColorSpace(.sRGB) else { return "#8E8E93" }
        return String(format: "#%02x%02x%02x",
            Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }
}

import SwiftUI
extension Color {
    init(hex: String) { self.init(nsColor: NSColor(hex: hex) ?? .secondaryLabelColor) }
}

