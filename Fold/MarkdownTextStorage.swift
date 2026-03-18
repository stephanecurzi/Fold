import AppKit

final class MarkdownTextStorage: NSTextStorage {

    private let backing = NSMutableAttributedString()
    private static var rxCache: [String: NSRegularExpression] = [:]

    static let fontSize: CGFloat = 16
    static var body: NSFont { .systemFont(ofSize: fontSize) }

    var foldedHeadings: Set<Int> = []

    // TagStore injecté pour les couleurs
    var tagColorProvider: ((String) -> NSColor)? = nil

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
        applyFolding(text: text)
    }

    // MARK: - Block Elements

    private func applyBlock(line: String, nsLine: NSString, at offset: Int) {
        let len = nsLine.length
        guard len > 0 else { return }
        let lineRange = NSRange(location: 0, length: len)

        if let m = rx(#"^(#{1,6})([ \t]+)(.*)$"#).firstMatch(in: line, range: lineRange) {
            let level  = m.range(at: 1).length
            let hidden = m.range(at: 1).length + m.range(at: 2).length
            let textLn = m.range(at: 3).length
            hide(at: offset, length: hidden)
            if textLn > 0 {
                backing.addAttribute(.font, value: headingFont(level),
                                     range: NSRange(location: offset + hidden, length: textLn))
            }
            return
        }

        if let m = rx(#"^(>[ \t]?)(.*)$"#).firstMatch(in: line, range: lineRange) {
            let pLen = m.range(at: 1).length
            let tLen = m.range(at: 2).length
            hide(at: offset, length: pLen)
            if tLen > 0 {
                backing.addAttributes([
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .font: Self.body.italic()
                ], range: NSRange(location: offset + pLen, length: tLen))
            }
            return
        }

        if rx(#"^(---+|\*\*\*+|___+)\s*$"#).firstMatch(in: line, range: lineRange) != nil {
            hide(at: offset, length: len)
            return
        }

        if let m = rx(#"^(\s*)([-*+])([ \t])"#).firstMatch(in: line, range: lineRange) {
            backing.addAttribute(.foregroundColor, value: NSColor.systemBlue,
                                 range: NSRange(location: offset + m.range(at: 2).location, length: 1))
        }

        if let m = rx(#"^(\s*)(\d+\.)([ \t])"#).firstMatch(in: line, range: lineRange) {
            backing.addAttribute(.foregroundColor, value: NSColor.systemBlue,
                                 range: NSRange(location: offset + m.range(at: 2).location,
                                                length: m.range(at: 2).length))
        }
    }

    // MARK: - Inline Elements

    private func applyInline(text: String, in full: NSRange) {
        inline(#"\*\*\*(.+?)\*\*\*"#, text, full, attrs: [.font: boldItalicFont()])
        inline(#"\*\*(.+?)\*\*"#, text, full, attrs: [.font: NSFont.boldSystemFont(ofSize: Self.fontSize)])
        inline(#"(?<![*_])\*([^*\n]+)\*(?![*_])"#, text, full, attrs: [.font: Self.body.italic()])
        inline(#"`([^`\n]+)`"#, text, full, attrs: [
            .font: NSFont.monospacedSystemFont(ofSize: Self.fontSize - 1, weight: .regular),
            .foregroundColor: NSColor.systemGreen
        ])
        inline(#"~~(.+?)~~"#, text, full, attrs: [
            .strikethroughStyle: NSUnderlineStyle.single.rawValue,
            .foregroundColor: NSColor.secondaryLabelColor
        ])
        inlineLinks(text, full)

        // @tags : toujours en gris tertiaire
        inlineAll(#"@[\w]+"#, text, full, attrs: [
            .foregroundColor: NSColor.tertiaryLabelColor,
            .font: NSFont.systemFont(ofSize: Self.fontSize)
        ])

        inlineHashtags(text)
    }

    // MARK: - Colorisation des lignes par @tag

    private func applyTagLineColors(text: String) {
        guard let provider = tagColorProvider else { return }
        let pattern = #"@(\w+)(?=\s*[.!?]?\s*$)"#
        guard let rx = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return }

        let lines = text.components(separatedBy: "\n")
        var offset = 0

        for line in lines {
            let lineLen = (line as NSString).length
            let lineRange = NSRange(location: 0, length: lineLen)

            if let m = rx.firstMatch(in: line, range: lineRange),
               let tagRange = Range(m.range(at: 1), in: line) {
                let tagName = String(line[tagRange]).lowercased()
                let color = provider(tagName)

                // Colorie toute la ligne sauf le @tag lui-même
                let fullLineRange = NSRange(location: offset, length: lineLen)
                let tagNSRange = NSRange(location: offset + m.range(at: 0).location,
                                        length: m.range(at: 0).length)

                // Ligne en couleur du tag
                if valid(fullLineRange) {
                    backing.addAttribute(.foregroundColor, value: color, range: fullLineRange)
                }
                // @tag reste en gris tertiaire par-dessus
                if valid(tagNSRange) {
                    backing.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: tagNSRange)
                }
            }
            offset += lineLen + 1
        }
    }

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

    // MARK: - Folding

    private func applyFolding(text: String) {
        guard !foldedHeadings.isEmpty else { return }
        let lines = text.components(separatedBy: "\n")
        var offset = 0
        var foldingLevel: Int? = nil
        var foldRange: NSRange? = nil

        for (i, line) in lines.enumerated() {
            let lineLen = (line as NSString).length
            var currentLevel: Int? = nil
            if let m = rx(#"^(#{1,6})([ \t]+)"#).firstMatch(in: line,
                          range: NSRange(location: 0, length: lineLen)) {
                currentLevel = m.range(at: 1).length
            }
            if let level = currentLevel {
                if let fr = foldRange { applyFoldAttrs(range: fr); foldRange = nil; foldingLevel = nil }
                if foldedHeadings.contains(offset) { foldingLevel = level }
            } else if foldingLevel != nil {
                let nextIsHeading: Bool = {
                    guard i + 1 < lines.count else { return false }
                    let next = lines[i + 1]
                    return rx(#"^#{1,6}[ \t]"#).firstMatch(
                        in: next, range: NSRange(location: 0, length: (next as NSString).length)) != nil
                }()
                foldRange = foldRange.map { NSRange(location: $0.location, length: $0.length + lineLen + 1) }
                          ?? NSRange(location: offset, length: lineLen + 1)
                if nextIsHeading { if let fr = foldRange { applyFoldAttrs(range: fr) }; foldRange = nil; foldingLevel = nil }
            }
            offset += lineLen + 1
        }
        if let fr = foldRange { applyFoldAttrs(range: fr) }
    }

    private func applyFoldAttrs(range: NSRange) {
        let safe = NSRange(location: range.location,
                           length: min(range.length, backing.length - range.location))
        guard safe.length > 0 else { return }
        backing.addAttributes([.foregroundColor: NSColor.clear, .font: NSFont.systemFont(ofSize: 0.01)], range: safe)
    }

    // MARK: - Utilities

    private func hide(at location: Int, length: Int) {
        guard length > 0, location + length <= backing.length else { return }
        backing.addAttributes([.foregroundColor: NSColor.clear, .font: NSFont.systemFont(ofSize: 0.01)],
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

    private func headingFont(_ level: Int) -> NSFont {
        let sizes: [CGFloat] = [30, 24, 20, 18, 17, 15]
        return .boldSystemFont(ofSize: sizes[min(level - 1, 5)])
    }

    private func boldItalicFont() -> NSFont {
        NSFont(descriptor: Self.body.fontDescriptor.withSymbolicTraits([.bold, .italic]),
               size: Self.fontSize) ?? Self.body
    }

    private var bodyAttrs: [NSAttributedString.Key: Any] {
        let s = NSMutableParagraphStyle()
        s.lineSpacing = 5
        s.paragraphSpacing = 2
        return [.font: Self.body, .foregroundColor: NSColor.labelColor, .paragraphStyle: s]
    }
}

extension NSFont {
    func italic() -> NSFont {
        NSFont(descriptor: fontDescriptor.withSymbolicTraits(.italic), size: pointSize) ?? self
    }
}
