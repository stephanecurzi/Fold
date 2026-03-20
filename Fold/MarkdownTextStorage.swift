import AppKit

final class MarkdownTextStorage: NSTextStorage {

    private let backing = NSMutableAttributedString()
    private static var rxCache: [String: NSRegularExpression] = [:]

    // Injecté depuis TextEditorView
    var preferences: PreferencesStore? = nil
    var tagColorProvider: ((String) -> NSColor)? = nil
    var activeTag: String? = nil
    var foldedHeadings: Set<Int> = []
    var currentTagColors: [String: String]? = nil  // Pour détecter les changements

    // MARK: - Fonts

    private var fontSize: CGFloat { preferences?.fontSize ?? 16 }
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
        applyActiveTagHighlight(text: text)
    }

    // MARK: - Block Elements

    private func applyBlock(line: String, nsLine: NSString, at offset: Int) {
        let len = nsLine.length
        guard len > 0 else { return }
        let lineRange = NSRange(location: 0, length: len)

        // ── Headings ──────────────────────────────────
        if let m = rx(#"^(#{1,6})([ \t]+)(.*)$"#).firstMatch(in: line, range: lineRange) {
            let level  = m.range(at: 1).length
            let hidden = m.range(at: 1).length + m.range(at: 2).length
            let textLn = m.range(at: 3).length
            hide(at: offset, length: hidden)
            if textLn > 0 {
                let font = preferences?.headingFont(level: level) ?? headingFont(level)
                backing.addAttribute(.font, value: font,
                                     range: NSRange(location: offset + hidden, length: textLn))
            }
            return
        }

        // ── HR — affiché comme ligne visible ──────────
        if rx(#"^(---+|\*\*\*+|___+)\s*$"#).firstMatch(in: line, range: lineRange) != nil {
            backing.addAttributes([
                .foregroundColor: NSColor.separatorColor,
                .font: NSFont.systemFont(ofSize: 4),
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                .strikethroughColor: NSColor.separatorColor
            ], range: NSRange(location: offset, length: len))
            return
        }

        // ── Blockquote — italique + indentation ───────
        if let m = rx(#"^(>[ \t]?)(.*)$"#).firstMatch(in: line, range: lineRange) {
            let pLen = m.range(at: 1).length
            let tLen = m.range(at: 2).length
            hide(at: offset, length: pLen)
            if tLen > 0 {
                let ps = NSMutableParagraphStyle()
                ps.headIndent    = 20
                ps.firstLineHeadIndent = 20
                ps.lineSpacing   = 5
                backing.addAttributes([
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .font: italicFont(),
                    .paragraphStyle: ps
                ], range: NSRange(location: offset + pLen, length: tLen))
            }
            return
        }

        // ── Listes — couleur labelColor par défaut ────
        if let m = rx(#"^(\s*)([-*+])([ \t])"#).firstMatch(in: line, range: lineRange) {
            backing.addAttribute(.foregroundColor, value: NSColor.labelColor,
                                 range: NSRange(location: offset + m.range(at: 2).location, length: 1))
        }

        if let m = rx(#"^(\s*)(\d+\.)([ \t])"#).firstMatch(in: line, range: lineRange) {
            backing.addAttribute(.foregroundColor, value: NSColor.labelColor,
                                 range: NSRange(location: offset + m.range(at: 2).location,
                                                length: m.range(at: 2).length))
        }

        // ── Checkbox ──────────────────────────────────
        if rx(#"^(\s*- \[x\] )"#).firstMatch(in: line, range: lineRange) != nil {
            backing.addAttributes([
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                .foregroundColor: NSColor.tertiaryLabelColor
            ], range: NSRange(location: offset, length: len))
        }

        // ── Bloc de code (``` ... ```) ─────────────────
        if rx(#"^```"#).firstMatch(in: line, range: lineRange) != nil {
            backing.addAttributes([
                .font: monoFont,
                .foregroundColor: NSColor.secondaryLabelColor
            ], range: NSRange(location: offset, length: len))
        }
    }

    // MARK: - Inline Elements

    private func applyInline(text: String, in full: NSRange) {
        // Bold + Italic
        inline(#"\*\*\*(.+?)\*\*\*"#, text, full, attrs: [.font: boldItalicFont()])
        // Bold
        inline(#"\*\*(.+?)\*\*"#, text, full, attrs: [.font: boldFont()])
        // Italic
        inline(#"(?<![*_])\*([^*\n]+)\*(?![*_])"#, text, full, attrs: [.font: italicFont()])
        // Code inline — monospace
        inline(#"`([^`\n]+)`"#, text, full, attrs: [
            .font: monoFont,
            .foregroundColor: NSColor.systemGreen,
            .backgroundColor: NSColor.secondaryLabelColor.withAlphaComponent(0.06)
        ])
        // Strikethrough
        inline(#"~~(.+?)~~"#, text, full, attrs: [
            .strikethroughStyle: NSUnderlineStyle.single.rawValue,
            .foregroundColor: NSColor.secondaryLabelColor
        ])
        // Highlight ==texte==
        inline(#"==(.+?)=="#, text, full, attrs: [
            .backgroundColor: NSColor.systemOrange.withAlphaComponent(0.3)
        ])
        // Links
        inlineLinks(text, full)
        // @tags gris tertiaire
        inlineAll(#"@[\w]+"#, text, full, attrs: [
            .foregroundColor: NSColor.tertiaryLabelColor
        ])
        // #hashtags
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
            let lineLen = (line as NSString).length
            let lineRange = NSRange(location: 0, length: lineLen)

            if let m = tagRx.firstMatch(in: line, range: lineRange),
               let tagRange = Range(m.range(at: 1), in: line) {
                let tagName = String(line[tagRange]).lowercased()
                let color   = provider(tagName)
                let fullLineRange = NSRange(location: offset, length: lineLen)
                let tagNSRange   = NSRange(location: offset + m.range(at: 0).location,
                                           length: m.range(at: 0).length)

                if valid(fullLineRange) {
                    backing.addAttribute(.foregroundColor, value: color, range: fullLineRange)

                    // @done = texte barré
                    if TagStore.isDoneTag(tagName) {
                        backing.addAttribute(.strikethroughStyle,
                                             value: NSUnderlineStyle.single.rawValue,
                                             range: fullLineRange)
                    }

                    // Bullets/numéros prennent la couleur du tag
                    let nsLine = line as NSString
                    if let bm = rx(#"^(\s*)([-*+])(\s)"#).firstMatch(in: line, range: lineRange) {
                        backing.addAttribute(.foregroundColor, value: color,
                                             range: NSRange(location: offset + bm.range(at: 2).location, length: 1))
                    }
                    if let nm = rx(#"^(\s*)(\d+\.)(\s)"#).firstMatch(in: line, range: lineRange) {
                        backing.addAttribute(.foregroundColor, value: color,
                                             range: NSRange(location: offset + nm.range(at: 2).location,
                                                            length: nm.range(at: 2).length))
                        _ = nsLine
                    }
                }

                // @tag reste en tertiaire
                if valid(tagNSRange) {
                    backing.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: tagNSRange)
                }
            }
            offset += lineLen + 1
        }
    }

    // MARK: - Active tag highlight

    private func applyActiveTagHighlight(text: String) {
        guard let tag = activeTag else { return }
        let pattern = #"@"# + NSRegularExpression.escapedPattern(for: tag) + #"(?=\s*[.!?]?\s*$)"#
        guard let tagRx = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return }

        let lines = text.components(separatedBy: "\n")
        var offset = 0
        for line in lines {
            let lineLen = (line as NSString).length
            if tagRx.firstMatch(in: line, range: NSRange(location: 0, length: lineLen)) != nil {
                let fullLineRange = NSRange(location: offset, length: lineLen)
                if valid(fullLineRange) {
                    backing.addAttribute(.backgroundColor,
                                         value: NSColor.systemOrange.withAlphaComponent(0.15),
                                         range: fullLineRange)
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
            if preLen > 0 { hide(at: full.location, length: preLen) }
            if sufLen > 0 { hide(at: cap.location + cap.length, length: sufLen) }
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

    private func inlineLinks(_ text: String, _ full: NSRange) {
        rx(#"\[([^\]\n]+)\]\(([^)\n]+)\)"#).enumerateMatches(in: text, range: full) { [weak self] m, _, _ in
            guard let self, let m else { return }
            let outer   = m.range(at: 0)
            let textCap = m.range(at: 1)
            guard valid(textCap) else { return }
            hide(at: outer.location, length: 1)
            let afterText = textCap.location + textCap.length
            let tailLen   = outer.location + outer.length - afterText
            if tailLen > 0 { hide(at: afterText, length: tailLen) }
            backing.addAttributes([
                .foregroundColor: NSColor.systemBlue,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ], range: textCap)
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
                    if valid(r) {
                        backing.addAttribute(.foregroundColor, value: NSColor.systemPurple, range: r)
                    }
                }
            }
            offset += lineLen + 1
        }
    }

    // MARK: - Utilities

    private func hide(at location: Int, length: Int) {
        guard length > 0, location + length <= backing.length else { return }
        backing.addAttributes([.foregroundColor: NSColor.clear,
                                .font: NSFont.systemFont(ofSize: 0.01)],
                               range: NSRange(location: location, length: length))
    }

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

    private func boldFont() -> NSFont {
        NSFontManager.shared.convert(bodyFont, toHaveTrait: .boldFontMask)
    }

    private func italicFont() -> NSFont {
        NSFontManager.shared.convert(bodyFont, toHaveTrait: .italicFontMask)
    }

    private func boldItalicFont() -> NSFont {
        var f = NSFontManager.shared.convert(bodyFont, toHaveTrait: .boldFontMask)
        f = NSFontManager.shared.convert(f, toHaveTrait: .italicFontMask)
        return f
    }

    private var bodyAttrs: [NSAttributedString.Key: Any] {
        let s = NSMutableParagraphStyle()
        s.lineSpacing      = 5
        s.paragraphSpacing = 4
        return [.font: bodyFont, .foregroundColor: NSColor.labelColor, .paragraphStyle: s]
    }
}
