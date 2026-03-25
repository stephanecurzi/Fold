import AppKit

// MARK: - Clé d'attribut custom pour la barre gauche des citations

private let kFoldMark = NSNumber(value: 1)

extension NSAttributedString.Key {
    static let foldBlockquote = NSAttributedString.Key("fold.blockquote")
}

final class MarkdownTextStorage: NSTextStorage {

    private let backing = NSMutableAttributedString()
    private static var rxCache: [String: NSRegularExpression] = [:]

    // Injecté depuis TextEditorView / CenteredEditorView
    var preferences: PreferencesStore? = nil
    var tagColorProvider: ((String) -> NSColor)? = nil
    var activeTag: String? = nil
    var foldedHeadings: Set<Int> = []
    var currentTagColors: [String: String]? = nil

    /// Position du curseur / sélection courante — mise à jour par le coordinator
    var cursorRange: NSRange = NSRange(location: NSNotFound, length: 0)

    // MARK: - Fonts

    private var fontSize: CGFloat { preferences?.fontSize ?? 18 }
    private var bodyFont: NSFont  { preferences?.bodyFont ?? .systemFont(ofSize: fontSize) }
    private var monoFont: NSFont  { .monospacedSystemFont(ofSize: fontSize - 1, weight: .regular) }

    // MARK: - Primitives

    override var string: String { backing.string }

    override func attributes(at location: Int,
                             effectiveRange range: NSRangePointer?) -> [NSAttributedString.Key: Any] {
        backing.attributes(at: location, effectiveRange: range)
    }

    override func replaceCharacters(in range: NSRange, with str: String) {
        beginEditing()
        backing.replaceCharacters(in: range, with: str)
        edited(.editedCharacters, range: range, changeInLength: (str as NSString).length - range.length)
        endEditing()
    }

    override func setAttributes(_ attrs: [NSAttributedString.Key: Any]?, range: NSRange) {
        beginEditing()
        backing.setAttributes(attrs, range: range)
        edited(.editedAttributes, range: range, changeInLength: 0)
        endEditing()
    }

    // MARK: - Highlight

    override func processEditing() {
        highlight()
        super.processEditing()
    }

    private func highlight() {
        let text = backing.string
        let full = NSRange(location: 0, length: backing.length)

        backing.setAttributes(bodyAttrs, range: full)

        var lineStart = 0
        for line in text.components(separatedBy: "\n") {
            let nsLine = line as NSString
            applyBlock(line: line, nsLine: nsLine, at: lineStart)
            lineStart += nsLine.length + 1
        }

        applyInline(text: text, in: full)
        applyTagLineColors(text: text)
        applyTagCollapse(text: text)
    }

    // MARK: - Block Elements

    private func applyBlock(line: String, nsLine: NSString, at offset: Int) {
        let len = nsLine.length
        guard len > 0 else { return }
        let lineRange    = NSRange(location: 0, length: len)
        let absLineRange = NSRange(location: offset, length: len)

        // ── Headings ──────────────────────────────────
        if let m = rx(#"^(#{1,6})([ \t]+)(.*)$"#).firstMatch(in: line, range: lineRange) {
            let level  = m.range(at: 1).length
            let hidden = m.range(at: 1).length + m.range(at: 2).length
            let textLn = m.range(at: 3).length
            if !cursorTouches(absLineRange) {
                hide(at: offset, length: hidden)
            } else {
                backing.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor,
                                     range: NSRange(location: offset, length: hidden))
            }
            if textLn > 0 {
                let font = preferences?.headingFont(level: level) ?? headingFont(level)
                backing.addAttribute(.font, value: font,
                                     range: NSRange(location: offset + hidden, length: textLn))
            }
            return
        }

        // ── HR ─────────────────────────────────────────
        if rx(#"^(---+|\*\*\*+|___+)\s*$"#).firstMatch(in: line, range: lineRange) != nil {
            let hrStyle = NSMutableParagraphStyle()
            hrStyle.alignment   = .center
            hrStyle.lineSpacing = 8
            backing.addAttributes([
                .foregroundColor: NSColor.labelColor,
                .font: NSFont.systemFont(ofSize: fontSize),
                .paragraphStyle: hrStyle
            ], range: absLineRange)
            return
        }

        // ── Blockquote ─────────────────────────────────
        if let m = rx(#"^(>)([ \t]?)(.*)$"#).firstMatch(in: line, range: lineRange) {
            let markerLen = 1
            let spaceLen  = m.range(at: 2).length
            let tLen      = m.range(at: 3).length
            let prefixLen = markerLen + spaceLen
            let ps = NSMutableParagraphStyle()
            ps.firstLineHeadIndent = 24
            ps.headIndent          = 24
            ps.lineSpacing         = 5
            ps.paragraphSpacing    = 2
            backing.addAttribute(.paragraphStyle, value: ps, range: absLineRange)
            backing.addAttribute(.foldBlockquote, value: kFoldMark, range: absLineRange)
            if !cursorTouches(absLineRange) {
                hide(at: offset, length: prefixLen)
            } else {
                backing.addAttribute(.foregroundColor,
                                     value: NSColor.systemOrange.withAlphaComponent(0.7),
                                     range: NSRange(location: offset, length: prefixLen))
            }
            if tLen > 0 {
                backing.addAttributes([
                    .foregroundColor: NSColor.labelColor,
                    .font: italicFont()
                ], range: NSRange(location: offset + prefixLen, length: tLen))
            }
            return
        }

        // ── Liste de tâches ────────────────────────────
        // Testée AVANT la liste non ordonnée
        if let m = rx(#"^(\s*)(- \[([ x])\] )(.*)"#).firstMatch(in: line, range: lineRange) {
            let indentLen  = m.range(at: 1).length
            let prefix     = nsLine.substring(with: m.range(at: 2)) // "- [ ] " ou "- [x] "
            let isDone     = nsLine.substring(with: m.range(at: 3)) == "x"
            let textRange  = NSRange(location: offset + m.range(at: 4).location,
                                     length: m.range(at: 4).length)
            let indent     = measuredWidth(String(repeating: " ", count: indentLen))
            let textIndent = indent + measuredWidth(prefix)
            let ps = listParagraphStyle(firstLine: indent, wrapped: textIndent)
            backing.addAttribute(.paragraphStyle, value: ps, range: absLineRange)
            backing.addAttribute(.foregroundColor, value: NSColor.labelColor,
                                 range: NSRange(location: offset + indentLen, length: m.range(at: 2).length))

            // Ligne complétée → texte barré + couleur tertiaire
            if isDone && valid(textRange) {
                backing.addAttributes([
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                    .foregroundColor: NSColor.tertiaryLabelColor
                ], range: textRange)
            }
            return
        }

        // ── Liste non ordonnée ─────────────────────────
        if let m = rx(#"^(\s*)([-*+])([ \t])(.*)"#).firstMatch(in: line, range: lineRange) {
            let indentLen  = m.range(at: 1).length
            let bullet     = nsLine.substring(with: m.range(at: 2))
            let space      = nsLine.substring(with: m.range(at: 3))
            let prefix     = bullet + space
            let indent     = measuredWidth(String(repeating: " ", count: indentLen))
            let textIndent = indent + measuredWidth(prefix)
            let ps = listParagraphStyle(firstLine: indent, wrapped: textIndent)
            backing.addAttribute(.paragraphStyle, value: ps, range: absLineRange)
            backing.addAttribute(.foregroundColor, value: NSColor.labelColor,
                                 range: NSRange(location: offset + m.range(at: 2).location, length: 1))
            return
        }

        // ── Liste ordonnée ─────────────────────────────
        if let m = rx(#"^(\s*)(\d+\.)([ \t])(.*)"#).firstMatch(in: line, range: lineRange) {
            let indentLen  = m.range(at: 1).length
            let num        = nsLine.substring(with: m.range(at: 2))
            let space      = nsLine.substring(with: m.range(at: 3))
            let prefix     = num + space
            let indent     = measuredWidth(String(repeating: " ", count: indentLen))
            let textIndent = indent + measuredWidth(prefix)
            let ps = listParagraphStyle(firstLine: indent, wrapped: textIndent)
            backing.addAttribute(.paragraphStyle, value: ps, range: absLineRange)
            backing.addAttribute(.foregroundColor, value: NSColor.labelColor,
                                 range: NSRange(location: offset + m.range(at: 2).location,
                                                length: m.range(at: 2).length))
            return
        }

        // ── Bloc de code ───────────────────────────────
        if rx(#"^```"#).firstMatch(in: line, range: lineRange) != nil {
            backing.addAttributes([
                .font: monoFont,
                .foregroundColor: NSColor.secondaryLabelColor
            ], range: absLineRange)
        }
    }

    /// Mesure la largeur réelle d'une chaîne avec le body font courant.
    private func measuredWidth(_ string: String) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [.font: bodyFont]
        return (string as NSString).size(withAttributes: attrs).width
    }

    /// Crée un paragraphStyle avec hanging indent propre pour les listes.
    private func listParagraphStyle(firstLine: CGFloat, wrapped: CGFloat) -> NSParagraphStyle {
        let ps = NSMutableParagraphStyle()
        ps.firstLineHeadIndent = firstLine
        ps.headIndent          = wrapped
        ps.lineSpacing         = 4
        ps.paragraphSpacing    = 2
        return ps
    }

    // MARK: - Inline Elements

    private func applyInline(text: String, in full: NSRange) {
        inlineFontMerging(#"\*\*\*(.+?)\*\*\*"#,              text, full, traits: [.boldFontMask, .italicFontMask])
        inlineFontMerging(#"(?<![_])___([^_\n]+)___(?![_])"#, text, full, traits: [.boldFontMask, .italicFontMask])
        inlineFontMerging(#"\*\*(.+?)\*\*"#,                  text, full, traits: [.boldFontMask])
        inlineFontMerging(#"(?<![_])__([^_\n]+)__(?![_])"#,   text, full, traits: [.boldFontMask])
        inlineFontMerging(#"(?<![*_])\*([^*\n]+)\*(?![*_])"#, text, full, traits: [.italicFontMask])
        inlineFontMerging(#"(?<![_\w])_([^_\n]+)_(?![_\w])"#, text, full, traits: [.italicFontMask])
        inline(#"`([^`\n]+)`"#, text, full, attrs: [
            .font: monoFont,
            .foregroundColor: NSColor.labelColor,
            .backgroundColor: NSColor.secondaryLabelColor.withAlphaComponent(0.07)
        ])
        inline(#"~~(.+?)~~"#, text, full, attrs: [
            .strikethroughStyle: NSUnderlineStyle.single.rawValue,
            .foregroundColor: NSColor.secondaryLabelColor
        ])
        inline(#"==(.+?)=="#, text, full, attrs: [
            .backgroundColor: NSColor.systemYellow.withAlphaComponent(0.45)
        ])
        inlineLinks(text, full)
        inlineAll(#"@[\w]+"#, text, full, attrs: [
            .foregroundColor: NSColor.tertiaryLabelColor
        ])
        inlineHashtags(text)
    }

    // MARK: - Tag line colors

    private func applyTagLineColors(text: String) {
        guard let provider = tagColorProvider else { return }
        let pattern = #"@(\w+)(?=\s*[.!?]?\s*$)"#
        guard let tagRx = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return }
        let lines = text.components(separatedBy: "\n")
        var offset = 0
        for line in lines {
            let lineLen   = (line as NSString).length
            let lineRange = NSRange(location: 0, length: lineLen)
            if let m = tagRx.firstMatch(in: line, range: lineRange),
               let tagRange = Range(m.range(at: 1), in: line) {
                let tagName       = String(line[tagRange]).lowercased()
                let color         = provider(tagName)
                let fullLineRange = NSRange(location: offset, length: lineLen)
                let tagNSRange    = NSRange(location: offset + m.range(at: 0).location,
                                            length: m.range(at: 0).length)
                if valid(fullLineRange) {
                    backing.addAttribute(.foregroundColor, value: color, range: fullLineRange)
                    if TagStore.isDoneTag(tagName) {
                        backing.addAttribute(.strikethroughStyle,
                                             value: NSUnderlineStyle.single.rawValue,
                                             range: fullLineRange)
                    }
                    if let bm = rx(#"^(\s*)([-*+])(\s)"#).firstMatch(in: line, range: lineRange) {
                        backing.addAttribute(.foregroundColor, value: color,
                                             range: NSRange(location: offset + bm.range(at: 2).location, length: 1))
                    }
                    if let nm = rx(#"^(\s*)(\d+\.)(\s)"#).firstMatch(in: line, range: lineRange) {
                        backing.addAttribute(.foregroundColor, value: color,
                                             range: NSRange(location: offset + nm.range(at: 2).location,
                                                            length: nm.range(at: 2).length))
                    }
                }
                if valid(tagNSRange) {
                    backing.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: tagNSRange)
                }
            }
            offset += lineLen + 1
        }
    }

    // MARK: - Tag highlight (ligne active)

    private func applyTagCollapse(text: String) {
        guard let tag = activeTag else { return }
        let highlightColor = tagColorProvider?(tag) ?? NSColor.systemOrange
        let escaped = NSRegularExpression.escapedPattern(for: tag)
        guard let tagRx = try? NSRegularExpression(
            pattern: "@" + escaped + #"(?=\s*[.!?]?\s*$)"#,
            options: [.anchorsMatchLines]
        ) else { return }
        let lines = text.components(separatedBy: "\n")
        var offset = 0
        for line in lines {
            let lineLen = (line as NSString).length
            if tagRx.firstMatch(in: line, range: NSRange(location: 0, length: lineLen)) != nil {
                let lineRange = NSRange(location: offset, length: lineLen)
                if valid(lineRange) {
                    backing.addAttribute(.backgroundColor,
                                         value: highlightColor.withAlphaComponent(0.12),
                                         range: lineRange)
                }
            }
            offset += lineLen + 1
        }
    }

    // MARK: - Inline helpers

    private func inline(_ pattern: String, _ text: String, _ range: NSRange,
                        attrs: [NSAttributedString.Key: Any]) {
        rx(pattern).enumerateMatches(in: text, range: range) { [weak self] m, _, _ in
            guard let self, let m, m.numberOfRanges > 1 else { return }
            let full = m.range(at: 0)
            let cap  = m.range(at: 1)
            guard valid(cap) else { return }
            let preLen = cap.location - full.location
            let sufLen = full.length - preLen - cap.length
            if !cursorTouches(full) {
                if preLen > 0 { hide(at: full.location, length: preLen) }
                if sufLen > 0 { hide(at: cap.location + cap.length, length: sufLen) }
            }
            backing.addAttributes(attrs, range: cap)
        }
    }

    private func inlineAll(_ pattern: String, _ text: String, _ range: NSRange,
                           attrs: [NSAttributedString.Key: Any]) {
        rx(pattern).enumerateMatches(in: text, range: range) { [weak self] m, _, _ in
            guard let self, let m else { return }
            let r = m.range(at: 0)
            guard valid(r) else { return }
            backing.addAttributes(attrs, range: r)
        }
    }

    private func inlineFontMerging(_ pattern: String, _ text: String, _ range: NSRange,
                                   traits: NSFontTraitMask) {
        rx(pattern).enumerateMatches(in: text, range: range) { [weak self] m, _, _ in
            guard let self, let m, m.numberOfRanges > 1 else { return }
            let full = m.range(at: 0)
            let cap  = m.range(at: 1)
            guard valid(cap) else { return }
            let preLen = cap.location - full.location
            let sufLen = full.length - preLen - cap.length
            if !cursorTouches(full) {
                if preLen > 0 { hide(at: full.location, length: preLen) }
                if sufLen > 0 { hide(at: cap.location + cap.length, length: sufLen) }
            }
            let baseFont = firstVisibleFont(in: cap) ?? bodyFont
            var merged = baseFont
            for trait in [NSFontTraitMask.boldFontMask, .italicFontMask]
                where traits.contains(trait) {
                merged = NSFontManager.shared.convert(merged, toHaveTrait: trait)
            }
            backing.addAttribute(.font, value: merged, range: cap)
        }
    }

    private func firstVisibleFont(in range: NSRange) -> NSFont? {
        var pos = range.location
        let end = range.location + range.length
        while pos < end {
            var effectiveRange = NSRange()
            let attrs = backing.attributes(at: pos, effectiveRange: &effectiveRange)
            let fgColor = attrs[.foregroundColor] as? NSColor
            if fgColor != NSColor.clear, let f = attrs[.font] as? NSFont, f.pointSize > 0.1 {
                return f
            }
            pos = effectiveRange.location + effectiveRange.length
        }
        return nil
    }

    private func inlineLinks(_ text: String, _ full: NSRange) {
        rx(#"\[([^\]\n]+)\]\(([^)\n]+)\)"#).enumerateMatches(in: text, range: full) { [weak self] m, _, _ in
            guard let self, let m else { return }
            let outer   = m.range(at: 0)
            let textCap = m.range(at: 1)
            let urlCap  = m.range(at: 2)
            guard valid(textCap) else { return }
            let linkURL = valid(urlCap)
                ? URL(string: (text as NSString).substring(with: urlCap))
                : nil
            if cursorTouches(outer) {
                var attrs: [NSAttributedString.Key: Any] = [
                    .foregroundColor: NSColor.systemBlue,
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ]
                if let url = linkURL { attrs[.link] = url }
                backing.addAttributes(attrs, range: outer)
            } else {
                hide(at: outer.location, length: 1)
                let afterText = textCap.location + textCap.length
                let tailLen   = outer.location + outer.length - afterText
                if tailLen > 0 { hide(at: afterText, length: tailLen) }
                var attrs: [NSAttributedString.Key: Any] = [
                    .foregroundColor: NSColor.systemBlue,
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ]
                if let url = linkURL { attrs[.link] = url }
                backing.addAttributes(attrs, range: textCap)
            }
        }
    }

    private func inlineHashtags(_ text: String) {
        let lines = text.components(separatedBy: "\n")
        var offset = 0
        for line in lines {
            let lineLen = (line as NSString).length
            if !line.trimmingCharacters(in: .whitespaces).hasPrefix("#") {
                let lineRange = NSRange(location: offset, length: lineLen)
                rx(#"(?<![#\w])#([\w]+)"#).enumerateMatches(in: text, range: lineRange) { [weak self] m, _, _ in
                    guard let self, let m else { return }
                    let r = m.range(at: 0)
                    if valid(r) { backing.addAttribute(.foregroundColor, value: NSColor.systemPurple, range: r) }
                }
            }
            offset += lineLen + 1
        }
    }

    // MARK: - Cursor helper

    private func cursorTouches(_ range: NSRange) -> Bool {
        guard cursorRange.location != NSNotFound,
              range.location != NSNotFound, range.length >= 0 else { return false }
        let cEnd = cursorRange.location + max(cursorRange.length, 1)
        let rEnd = range.location + range.length
        return cursorRange.location < rEnd && cEnd > range.location
    }

    // MARK: - Hide helper

    private func hide(at location: Int, length: Int) {
        guard length > 0, location + length <= backing.length else { return }
        backing.addAttributes([
            .foregroundColor: NSColor.clear,
            .font: NSFont.systemFont(ofSize: 0.01)
        ], range: NSRange(location: location, length: length))
    }

    // MARK: - Utilities

    private func valid(_ range: NSRange) -> Bool {
        range.location != NSNotFound && range.length > 0 && range.location + range.length <= backing.length
    }

    private func rx(_ pattern: String) -> NSRegularExpression {
        if let cached = Self.rxCache[pattern] { return cached }
        let r = try! NSRegularExpression(pattern: pattern)
        Self.rxCache[pattern] = r
        return r
    }

    // MARK: - Fonts

    private func headingFont(_ level: Int) -> NSFont {
        switch level {
        case 1: return preferences?.h1Font ?? .boldSystemFont(ofSize: 20)
        case 2: return preferences?.h2Font ?? .boldSystemFont(ofSize: 18)
        default: return preferences?.h3Font ?? .boldSystemFont(ofSize: fontSize)
        }
    }

    private func italicFont() -> NSFont {
        NSFontManager.shared.convert(bodyFont, toHaveTrait: .italicFontMask)
    }

    private var bodyAttrs: [NSAttributedString.Key: Any] {
        let s = NSMutableParagraphStyle()
        s.lineSpacing      = 5
        s.paragraphSpacing = 4
        return [.font: bodyFont, .foregroundColor: NSColor.labelColor, .paragraphStyle: s]
    }
}

