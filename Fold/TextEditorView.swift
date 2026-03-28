import SwiftUI
import AppKit

// NOTE : Notification.Name est défini dans FoldApp.swift uniquement.

struct TextEditorView: View {
    @ObservedObject var document: FoldDocument
    @Environment(TagStore.self) var tagStore
    @Environment(PreferencesStore.self) var prefs
    @Binding var activeTag: String?

    var body: some View {
        ZStack(alignment: .bottom) {
            CenteredEditorView(
                text: $document.text,
                maxWidth: 780,
                activeTag: activeTag,
                preferences: prefs,
                fontSize: prefs.fontSize,
                fontName: prefs.fontName,
                tagColors: tagStore.tagColors,
                tagColorProvider: { tagStore.color(for: $0) }
            )
            if let tag = activeTag {
                ActiveTagPill(
                    tag: tag,
                    color: tagStore.swiftUIColor(for: tag)
                ) {
                    withAnimation(.spring(duration: 0.3)) { activeTag = nil }
                }
                .padding(.bottom, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(1)
            }
        }
        .animation(.spring(duration: 0.3), value: activeTag)
    }
}

// MARK: - Pastille tag actif

struct ActiveTagPill: View {
    let tag: String
    let color: Color
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "tag.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
            Text(tag)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
    }
}

// MARK: - CenteredEditorView

struct CenteredEditorView: NSViewRepresentable {
    @Binding var text: String
    let maxWidth: CGFloat
    var activeTag: String? = nil
    var preferences: PreferencesStore? = nil
    var fontSize: CGFloat = 16
    var fontName: String = "SF Pro Text"
    var tagColors: [String: String] = [:]
    var tagColorProvider: ((String) -> NSColor)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let textStorage = MarkdownTextStorage()
        textStorage.tagColorProvider = tagColorProvider
        textStorage.activeTag = activeTag
        textStorage.preferences = preferences

        let layoutMgr = FoldLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        textStorage.addLayoutManager(layoutMgr)
        layoutMgr.addTextContainer(container)

        let textView = CenteredTextView(frame: .zero, textContainer: container)
        textView.maxContentWidth = maxWidth
        textView.isRichText                           = false
        textView.allowsUndo                           = true
        textView.isEditable                           = true
        textView.isSelectable                         = true
        textView.isAutomaticQuoteSubstitutionEnabled  = false
        textView.isAutomaticDashSubstitutionEnabled   = false
        textView.isAutomaticLinkDetectionEnabled      = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled     = false
        textView.usesFontPanel                        = false
        textView.backgroundColor                      = .textBackgroundColor
        textView.isVerticallyResizable                = true
        textView.isHorizontallyResizable              = false
        textView.autoresizingMask                     = .width
        textView.delegate = context.coordinator
        context.coordinator.textView = textView

        let scroll = NSScrollView()
        scroll.hasVerticalScroller   = true
        scroll.autohidesScrollers    = true
        scroll.drawsBackground       = false
        scroll.hasHorizontalScroller = false
        scroll.documentView          = textView
        textView.minSize = NSSize(width: 0, height: scroll.contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)

        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true

        textView.selectedTextAttributes = [
            .backgroundColor: NSColor.systemOrange.withAlphaComponent(0.28),
            .foregroundColor: NSColor.labelColor
        ]

        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        if let s = tv.textStorage as? MarkdownTextStorage {
            s.tagColorProvider = tagColorProvider
            let prefsChanged = s.preferences?.fontSize != preferences?.fontSize
                            || s.preferences?.fontName  != preferences?.fontName
            s.preferences = preferences
            let tagChanged = s.activeTag != activeTag
            s.activeTag = activeTag
            let colorsChanged = tagColors != (s.currentTagColors ?? [:])
            s.currentTagColors = tagColors
            if prefsChanged || tagChanged || colorsChanged {
                s.beginEditing()
                s.edited(.editedAttributes, range: NSRange(location: 0, length: s.length), changeInLength: 0)
                s.endEditing()
            }
        }
        guard tv.string != text else { return }
        let sel = tv.selectedRange()
        tv.string = text
        tv.setSelectedRange(NSRange(location: min(sel.location, (text as NSString).length), length: 0))
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CenteredEditorView
        weak var textView: CenteredTextView?
        init(_ p: CenteredEditorView) { parent = p }

        func textDidChange(_ n: Notification) {
            guard let tv = n.object as? NSTextView else { return }
            parent.text = tv.string
        }

        func textView(_ tv: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            if let url = link as? URL {
                NSWorkspace.shared.open(url)
                return true
            }
            if let str = link as? String, let url = URL(string: str) {
                NSWorkspace.shared.open(url)
                return true
            }
            return false
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView,
                  let s = tv.textStorage as? MarkdownTextStorage else { return }
            let newRange = tv.selectedRange()
            guard s.cursorRange.location != newRange.location
                    || s.cursorRange.length != newRange.length else { return }
            s.cursorRange = newRange
            s.beginEditing()
            s.edited(.editedAttributes,
                     range: NSRange(location: 0, length: s.length),
                     changeInLength: 0)
            s.endEditing()
        }
    }
}

// MARK: - CenteredTextView

final class CenteredTextView: NSTextView {
    var maxContentWidth: CGFloat = 780

    // MARK: - Cycle de vie

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateInset()
        guard window != nil else { return }
        let nc = NotificationCenter.default
        nc.removeObserver(self)
        nc.addObserver(self, selector: #selector(onSearch),       name: .foldSearch,       object: nil)
        nc.addObserver(self, selector: #selector(onReplace),      name: .foldReplace,      object: nil)
        nc.addObserver(self, selector: #selector(onNext),         name: .foldFindNext,     object: nil)
        nc.addObserver(self, selector: #selector(onPrev),         name: .foldFindPrev,     object: nil)
        nc.addObserver(self, selector: #selector(onHide),         name: .foldFindHide,     object: nil)
        nc.addObserver(self, selector: #selector(onPrefsChanged),      name: .foldPrefsChanged,      object: nil)
        nc.addObserver(self, selector: #selector(onGlobalSearchJump),  name: .foldGlobalSearchJump,  object: nil)
        nc.addObserver(self, selector: #selector(onGlobalSearchClear),  name: .foldGlobalSearchClear,  object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    // MARK: - NSTextFinder

    private func find(_ action: NSTextFinder.Action) {
        guard window?.isKeyWindow == true else { return }
        let item = NSMenuItem()
        item.tag = action.rawValue
        performTextFinderAction(item)
    }

    @objc private func onSearch(_:  Notification) { find(.showFindInterface)    }
    @objc private func onReplace(_: Notification) { find(.showReplaceInterface) }
    @objc private func onNext(_:    Notification) { find(.nextMatch)            }
    @objc private func onPrev(_:    Notification) { find(.previousMatch)        }
    @objc private func onHide(_:    Notification) { find(.hideFindInterface)    }

    @objc private func onGlobalSearchJump(_ n: Notification) {
        guard window?.isKeyWindow == true,
              let query = n.userInfo?["query"] as? String,
              !query.isEmpty else { return }
        highlightAllOccurrences(of: query)
    }

    private func highlightAllOccurrences(of query: String) {
        guard let lm = layoutManager else { return }
        let text = string as NSString
        let fullRange = NSRange(location: 0, length: text.length)
        let options: NSString.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

        // Efface les anciens highlights temporaires
        lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: fullRange)

        // Highlight de toutes les occurrences
        var searchRange = fullRange
        var firstRange: NSRange? = nil
        while searchRange.location < NSMaxRange(fullRange) {
            let found = text.range(of: query, options: options, range: searchRange)
            guard found.location != NSNotFound else { break }
            lm.addTemporaryAttributes(
                [.backgroundColor: NSColor.systemOrange.withAlphaComponent(0.35)],
                forCharacterRange: found
            )
            if firstRange == nil { firstRange = found }
            let next = found.location + found.length
            searchRange = NSRange(location: next, length: fullRange.length - next)
        }

        // Scroll et sélection sur la première occurrence
        if let first = firstRange {
            setSelectedRange(first)
            scrollRangeToVisible(first)
        }
    }

    @objc private func onGlobalSearchClear(_ n: Notification) { clearGlobalSearchHighlights() }

    /// Efface tous les highlights de recherche globale.
    func clearGlobalSearchHighlights() {
        guard let lm = layoutManager else { return }
        lm.removeTemporaryAttribute(.backgroundColor,
                                    forCharacterRange: NSRange(location: 0, length: string.count))
    }

    @objc private func onPrefsChanged(_ n: Notification) {
        guard let prefs = n.object as? PreferencesStore,
              let s = textStorage as? MarkdownTextStorage else { return }
        s.preferences = prefs
        s.beginEditing()
        s.edited(.editedAttributes,
                 range: NSRange(location: 0, length: s.length),
                 changeInLength: 0)
        s.endEditing()
    }

    // MARK: - Typographie française

    override func insertText(_ string: Any, replacementRange: NSRange) {
        guard let input = string as? String else {
            super.insertText(string, replacementRange: replacementRange)
            return
        }

        let cursorPos = replacementRange.location != NSNotFound
            ? replacementRange.location
            : selectedRange().location

        guard !isInsideCodeSpan(at: cursorPos) else {
            super.insertText(string, replacementRange: replacementRange)
            return
        }

        var result = input

        // Apostrophe droite → apostrophe typographique
        result = result.replacingOccurrences(of: "'", with: "\u{2019}")

        // Guillemets doubles → guillemets français avec espace fine insécable
        if result == "\"" {
            result = isOpeningContext(at: cursorPos)
                ? "«\u{202F}"
                : "\u{202F}»"
        }

        super.insertText(result, replacementRange: replacementRange)
    }

    private func isOpeningContext(at pos: Int) -> Bool {
        guard pos > 0 else { return true }
        let str = string as NSString
        guard pos <= str.length else { return true }
        let prevChar = str.character(at: pos - 1)
        let openingSet = CharacterSet.whitespaces
            .union(.newlines)
            .union(CharacterSet(charactersIn: "([{\"'«—-"))
        guard let scalar = Unicode.Scalar(prevChar) else { return true }
        return openingSet.contains(scalar)
    }

    private func isInsideCodeSpan(at pos: Int) -> Bool {
        let str = string as NSString
        let lineRange = str.lineRange(for: NSRange(location: min(pos, str.length), length: 0))
        let line = str.substring(with: lineRange)
        let localPos = pos - lineRange.location
        var inCode = false
        var charIndex = 0
        for ch in line {
            if charIndex == localPos { return inCode }
            if ch == "`" { inCode.toggle() }
            charIndex += 1
        }
        return false
    }

    // MARK: - Typing attributes — évite le curseur minuscule en début de ligne
    // hide() dans MarkdownTextStorage applique une police de 0.01 pt pour masquer
    // les marqueurs Markdown. Si le curseur se retrouve sur ces caractères cachés,
    // NSTextView hérite de cette police pour les typingAttributes → curseur minuscule.
    // On intercepte le getter pour garantir une taille minimale cohérente.

    override var typingAttributes: [NSAttributedString.Key: Any] {
        get {
            var attrs = super.typingAttributes
            if let font = attrs[.font] as? NSFont, font.pointSize < 2 {
                let fallback = (textStorage as? MarkdownTextStorage)?.preferences?.bodyFont
                    ?? NSFont.systemFont(ofSize: 18)
                attrs[.font]            = fallback
                attrs[.foregroundColor] = NSColor.labelColor
            }
            return attrs
        }
        set { super.typingAttributes = newValue }
    }

    // MARK: - Mise en page

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateInset()
    }

    private func updateInset() {
        let width = frame.width
        let horizontalInset = max(50, (width - maxContentWidth) / 2)
        textContainerInset = NSSize(width: horizontalInset, height: 50)
    }

    // MARK: - Clavier

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 48 where !event.modifierFlags.contains(.shift):
            // Tab → vrai caractère tabulation
            insertText("\t", replacementRange: selectedRange())
        case 36:
            // Return → continuation de liste si applicable
            if !handleListContinuation() {
                super.keyDown(with: event)
            }
        default:
            super.keyDown(with: event)
        }
    }

    // MARK: - Continuation de liste

    @discardableResult
    private func handleListContinuation() -> Bool {
        let sel = selectedRange()
        let str = string as NSString
        let lineRange = str.lineRange(for: NSRange(location: sel.location, length: 0))
        var line = str.substring(with: lineRange)
        if line.hasSuffix("\n") { line = String(line.dropLast()) }
        let nsLine = line as NSString
        let lr = NSRange(location: 0, length: nsLine.length)

        // ── Liste de tâches ──
        if let m = rx(#"^(\s*)(- \[[ x]\] )(.+)$"#).firstMatch(in: line, range: lr) {
            if m.range(at: 3).length == 0 {
                insertText("\n", replacementRange: lineRange)
                return true
            }
            let indent = nsLine.substring(with: m.range(at: 1))
            insertText("\n\(indent)- [ ] ", replacementRange: sel)
            return true
        }

        // ── Liste non ordonnée ──
        if let m = rx(#"^(\s*)([-*+]) (.+)$"#).firstMatch(in: line, range: lr) {
            let indent = nsLine.substring(with: m.range(at: 1))
            let bullet = nsLine.substring(with: m.range(at: 2))
            insertText("\n\(indent)\(bullet) ", replacementRange: sel)
            return true
        }

        // ── Ligne vide non ordonnée → supprimer ──
        if rx(#"^(\s*)([-*+]) $"#).firstMatch(in: line, range: lr) != nil {
            insertText("\n", replacementRange: lineRange)
            return true
        }

        // ── Liste ordonnée ──
        if let m = rx(#"^(\s*)(\d+)\. (.+)$"#).firstMatch(in: line, range: lr) {
            let indent  = nsLine.substring(with: m.range(at: 1))
            let numStr  = nsLine.substring(with: m.range(at: 2))
            let nextNum = (Int(numStr) ?? 1) + 1
            insertText("\n\(indent)\(nextNum). ", replacementRange: sel)
            return true
        }

        // ── Ligne vide ordonnée → supprimer ──
        if rx(#"^(\s*)\d+\. $"#).firstMatch(in: line, range: lr) != nil {
            insertText("\n", replacementRange: lineRange)
            return true
        }

        return false
    }

    // Double-clic → fold/unfold heading
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        if event.clickCount == 2 { toggleFoldAtCursor() }
    }

    private func toggleFoldAtCursor() {
        guard let storage = textStorage as? MarkdownTextStorage else { return }
        let charIndex = selectedRange().location
        let text = string as NSString
        let lineRange = text.lineRange(for: NSRange(location: charIndex, length: 0))
        let line = text.substring(with: lineRange)
        guard let rxObj = try? NSRegularExpression(pattern: #"^#{1,6}[ \t]"#),
              rxObj.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) != nil
        else { return }
        let lineStart = lineRange.location
        if storage.foldedHeadings.contains(lineStart) {
            storage.foldedHeadings.remove(lineStart)
        } else {
            storage.foldedHeadings.insert(lineStart)
        }
        storage.beginEditing()
        storage.edited(.editedAttributes,
                       range: NSRange(location: 0, length: storage.length),
                       changeInLength: 0)
        storage.endEditing()
        needsDisplay = true
    }

    // MARK: - Regex helper local

    private static var rxCache: [String: NSRegularExpression] = [:]
    private func rx(_ pattern: String) -> NSRegularExpression {
        if let cached = Self.rxCache[pattern] { return cached }
        let r = try! NSRegularExpression(pattern: pattern)
        Self.rxCache[pattern] = r
        return r
    }
}

// MARK: - FoldLayoutManager — barre verticale gauche pour les citations

final class FoldLayoutManager: NSLayoutManager {

    private let barWidth:  CGFloat = 3
    private let barInset:  CGFloat = 6
    private let barRadius: CGFloat = 1.5

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage,
              let container = textContainers.first else { return }
        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        drawBars(for: .foldBlockquote, color: .systemOrange, in: charRange,
                 storage: storage, container: container, origin: origin)
        drawBars(for: .foldCodeblock, color: .separatorColor, in: charRange,
                 storage: storage, container: container, origin: origin)
    }

    private func drawBars(for key: NSAttributedString.Key,
                          color: NSColor,
                          in charRange: NSRange,
                          storage: NSTextStorage,
                          container: NSTextContainer,
                          origin: NSPoint) {

        var markedRects: [CGRect] = []
        var pos = charRange.location
        let end = charRange.location + charRange.length

        while pos < end {
            var effectiveRange = NSRange(location: NSNotFound, length: 0)
            let value = storage.attribute(key, at: pos, longestEffectiveRange: &effectiveRange,
                                          in: charRange)
            let runEnd = min(effectiveRange.location + effectiveRange.length, end)
            if value != nil {
                let glRange = glyphRange(forCharacterRange: NSRange(location: pos, length: runEnd - pos),
                                         actualCharacterRange: nil)
                enumerateLineFragments(forGlyphRange: glRange) { rect, _, _, _, _ in
                    markedRects.append(rect)
                }
            }
            pos = runEnd
        }

        guard !markedRects.isEmpty else { return }

        let barX = origin.x + container.lineFragmentPadding + barInset
        var groupRect = markedRects[0]

        func drawBar(rect: CGRect) {
            let barRect = CGRect(x: barX,
                                 y: origin.y + rect.minY,
                                 width: barWidth,
                                 height: rect.height)
            color.setFill()
            NSBezierPath(roundedRect: barRect, xRadius: barRadius, yRadius: barRadius).fill()
        }

        for i in 1..<markedRects.count {
            let current = markedRects[i]
            if abs(current.minY - groupRect.maxY) < 2 {
                groupRect = groupRect.union(current)
            } else {
                drawBar(rect: groupRect)
                groupRect = current
            }
        }
        drawBar(rect: groupRect)
    }
}




