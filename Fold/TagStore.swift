import Foundation
import AppKit
import Observation

private let colorsKey = "fold.tagColors"

// Couleurs par défaut pour les premiers tags
private let defaultColors: [String] = [
    "#fe5000", "#0066ff", "#00b340", "#bf00ff",
    "#ff3b30", "#ff9500", "#34c759", "#007aff"
]

@MainActor
@Observable
final class TagStore {

    // [tagName: hexColor]
    var tagColors: [String: String] = [:]

    private var colorIndex = 0

    init() {
        load()
    }

    // MARK: - Couleur d'un tag

    func color(for tag: String) -> NSColor {
        let hex = tagColors[tag] ?? colorForNew(tag)
        return NSColor(hex: hex) ?? .tertiaryLabelColor
    }

    func swiftUIColor(for tag: String) -> Color {
        Color(nsColor: color(for: tag))
    }

    func setColor(_ hex: String, for tag: String) {
        tagColors[tag] = hex
        save()
    }

    // Assigne automatiquement une couleur si le tag est nouveau
    @discardableResult
    func colorForNew(_ tag: String) -> String {
        if let existing = tagColors[tag] { return existing }
        let hex = defaultColors[colorIndex % defaultColors.count]
        colorIndex += 1
        tagColors[tag] = hex
        save()
        return hex
    }

    // MARK: - Extraction @tags en fin de phrase/ligne

    static func extract(from content: String) -> [String] {
        let pattern = #"@(\w+)(?=\s*[.!?]?\s*$)"#
        guard let rx = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return [] }
        let range = NSRange(content.startIndex..., in: content)
        let matches = rx.matches(in: content, range: range)
        let tags = matches.compactMap { match -> String? in
            guard let r = Range(match.range(at: 1), in: content) else { return nil }
            return String(content[r]).lowercased()
        }
        return Array(Set(tags)).sorted()
    }

    // MARK: - Persistance

    private func save() {
        UserDefaults.standard.set(tagColors, forKey: colorsKey)
    }

    private func load() {
        tagColors = UserDefaults.standard.dictionary(forKey: colorsKey) as? [String: String] ?? [:]
    }
}

// MARK: - NSColor hex init

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
        guard let c = usingColorSpace(.sRGB) else { return "#000000" }
        return String(format: "#%02x%02x%02x",
            Int(c.redComponent * 255),
            Int(c.greenComponent * 255),
            Int(c.blueComponent * 255))
    }
}

import SwiftUI
extension Color {
    init(hex: String) {
        self.init(nsColor: NSColor(hex: hex) ?? .labelColor)
    }
}
