import SwiftUI
import AppKit

// NOTE : Notification.Name est défini dans FoldApp.swift uniquement.

struct TextEditorView: View {
    @ObservedObject var document: FoldDocument
    @Environment(TagStore.self) var tagStore
    @Environment(PreferencesStore.self) var prefs
    @Binding var activeTag: String?

    @State private var focusedTitle: String? = nil

    var body: some View {
        ZStack(alignment: .topLeading) {
            CenteredEditorView(
                text: $document.text,
                maxWidth: 780,
                activeTag: activeTag,
                preferences: prefs,
                fontSize: prefs.fontSize,
                fontName: prefs.fontName,
                tagColors: tagStore.tagColors,
                tagColorProvider: { tagStore.color(for: $0) },
                focusedTitle: $focusedTitle
            )

            // Pill de concentration — flottante en haut à gauche, dans la zone texte
            if let title = focusedTitle {
                ConcentrationPill(title: title) {
                    focusedTitle = nil
                }
                .padding(.top, 16)
                .padding(.leading, 20)
                .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .topLeading)))
                .zIndex(2)
            }

            if let tag = activeTag {
                VStack {
                    Spacer()
                    ActiveTagPill(
                        tag: tag,
                        color: tagStore.swiftUIColor(for: tag)
                    ) {
                        withAnimation(.spring(duration: 0.3)) { activeTag = nil }
                    }
                    .padding(.bottom, 24)
                }
                .frame(maxWidth: .infinity)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: focusedTitle)
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

// MARK: - Pill de concentration flottante

struct ConcentrationPill: View {
    let title: String
    let onDismiss: () -> Void

    var body: some View {
        Button(action: onDismiss) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .help("Quitter la concentration (Esc ou ⌘↩)")
    }
}

struct CenteredEditorView: NSViewRepresentable {
    @Binding var text: String
    let maxWidth: CGFloat
    var activeTag: String? = nil
    var preferences: PreferencesStore? = nil
    var fontSize: CGFloat = 16
    var fontName: String = "SF Pro Text"
    var tagColors: [String: String] = [:]
    var tagColorProvider: ((String) -> NSColor)? = nil
    @Binding var focusedTitle: String?

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
        context.coordinator.focusedTitleBinding = { title in
            context.coordinator.parent.focusedTitle = title
        }

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

            // Sync focus : si focusedTitle est nil on efface le zoom
            let newFocusedRange: NSRange? = focusedTitle == nil ? nil : s.focusedRange
            let focusChanged = s.focusedRange?.location != newFocusedRange?.location
                            || s.focusedRange?.length   != newFocusedRange?.length
            if focusedTitle == nil && s.focusedRange != nil {
                s.focusedRange = nil
                s.focusedHeadingTitle = ""
                // Invalider les glyphes pour forcer la régénération après suppression de .foldHidden
                if let tv = scroll.documentView as? CenteredTextView {
                    tv.layoutManager?.invalidateGlyphs(
                        forCharacterRange: NSRange(location: 0, length: s.length),
                        changeInLength: 0, actualCharacterRange: nil)
                }
            }

            if prefsChanged || tagChanged || colorsChanged || focusChanged {
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
        var focusedTitleBinding: ((String?) -> Void)?
        init(_ p: CenteredEditorView) { parent = p }

        func textDidChange(_ n: Notification) {
            guard let tv = n.object as? NSTextView else { return }
            parent.text = tv.string
            // Mise à jour live de la fenêtre raw si elle est déjà visible
            NotificationCenter.default.post(
                name: .foldRawUpdate,
                object: nil,
                userInfo: ["text": tv.string]
            )
        }

        func textView(_ tv: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            let url: URL?
            if let u = link as? URL { url = u }
            else if let s = link as? String { url = URL(string: s) }
            else { return false }

            guard let url else { return false }

            if url.scheme == "fold-wiki" {
                let raw = url.path
                let title = String(raw.dropFirst())
                    .removingPercentEncoding ?? raw
                NotificationCenter.default.post(
                    name: .foldWikiLink,
                    object: nil,
                    userInfo: ["title": title]
                )
                return true
            }

            NSWorkspace.shared.open(url)
            return true
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
        nc.addObserver(self, selector: #selector(onSearch),            name: .foldSearch,            object: nil)
        nc.addObserver(self, selector: #selector(onReplace),           name: .foldReplace,           object: nil)
        nc.addObserver(self, selector: #selector(onNext),              name: .foldFindNext,          object: nil)
        nc.addObserver(self, selector: #selector(onPrev),              name: .foldFindPrev,          object: nil)
        nc.addObserver(self, selector: #selector(onHide),              name: .foldFindHide,          object: nil)
        nc.addObserver(self, selector: #selector(onPrefsChanged),      name: .foldPrefsChanged,      object: nil)
        nc.addObserver(self, selector: #selector(onGlobalSearchJump),  name: .foldGlobalSearchJump,  object: nil)
        nc.addObserver(self, selector: #selector(onGlobalSearchClear), name: .foldGlobalSearchClear, object: nil)
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

        lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: fullRange)

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

        if let first = firstRange {
            setSelectedRange(first)
            scrollRangeToVisible(first)
        }
    }

    @objc private func onGlobalSearchClear(_ n: Notification) { clearGlobalSearchHighlights() }

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

        result = result.replacingOccurrences(of: "'", with: "\u{2019}")

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

        if let m = rx(#"^(\s*)(- \[[ x]\] )(.+)$"#).firstMatch(in: line, range: lr) {
            if m.range(at: 3).length == 0 {
                insertText("\n", replacementRange: lineRange)
                return true
            }
            let indent = nsLine.substring(with: m.range(at: 1))
            insertText("\n\(indent)- [ ] ", replacementRange: sel)
            return true
        }

        if let m = rx(#"^(\s*)([-*+]) (.+)$"#).firstMatch(in: line, range: lr) {
            let indent = nsLine.substring(with: m.range(at: 1))
            let bullet = nsLine.substring(with: m.range(at: 2))
            insertText("\n\(indent)\(bullet) ", replacementRange: sel)
            return true
        }

        if rx(#"^(\s*)([-*+]) $"#).firstMatch(in: line, range: lr) != nil {
            insertText("\n", replacementRange: lineRange)
            return true
        }

        if let m = rx(#"^(\s*)(\d+)\. (.+)$"#).firstMatch(in: line, range: lr) {
            let indent  = nsLine.substring(with: m.range(at: 1))
            let numStr  = nsLine.substring(with: m.range(at: 2))
            let nextNum = (Int(numStr) ?? 1) + 1
            insertText("\n\(indent)\(nextNum). ", replacementRange: sel)
            return true
        }

        if rx(#"^(\s*)\d+\. $"#).firstMatch(in: line, range: lr) != nil {
            insertText("\n", replacementRange: lineRange)
            return true
        }

        return false
    }

    // MARK: - Fold / Unfold

    /// Clic simple sur une pill → déplie. ⌘-clic sur un titre → replie/déplie.
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        // Clic simple sur une pill → unfold (calcul du rect à la volée, pas de cache)
        if event.clickCount == 1,
           let lm = layoutManager as? FoldLayoutManager,
           let storage = textStorage as? MarkdownTextStorage,
           !storage.foldedHeadings.isEmpty {

            let text   = storage.string as NSString
            let map    = storage.headingMap(for: storage.string)
            let origin = lm.textContainers.first.map { _ in textContainerOrigin } ?? .zero

            for foldedStart in storage.foldedHeadings {
                guard foldedStart < storage.length else { continue }
                let headingLineRange = text.lineRange(for: NSRange(location: foldedStart, length: 0))
                let titleLen = max(0, headingLineRange.length - 1)
                guard titleLen > 0 else { continue }

                let glRange = lm.glyphRange(
                    forCharacterRange: NSRange(location: headingLineRange.location, length: titleLen),
                    actualCharacterRange: nil)
                var usedRect = CGRect.null
                lm.enumerateLineFragments(forGlyphRange: glRange) { _, used, _, _, _ in
                    usedRect = used
                }
                guard !usedRect.isNull else { continue }

                let pillH = CGFloat(12)
                let pillW = CGFloat(32)
                let pillX = origin.x + usedRect.maxX + 12
                let pillY = origin.y + usedRect.midY - pillH / 2 - 2
                let pillRect = CGRect(x: pillX, y: pillY, width: pillW, height: pillH)

                if pillRect.insetBy(dx: -4, dy: -4).contains(point) {
                    storage.foldedHeadings.remove(foldedStart)
                    refreshFolding(storage: storage)
                    return
                }
            }
        }

        if event.modifierFlags.contains(.command) && event.clickCount == 1 {
            let adjustedPt = NSPoint(x: point.x - textContainerInset.width,
                                     y: point.y - textContainerInset.height)
            var fraction: CGFloat = 0
            let glyph    = layoutManager?.glyphIndex(for: adjustedPt,
                                                      in: textContainer!,
                                                      fractionOfDistanceThroughGlyph: &fraction) ?? 0
            let charIdx  = layoutManager?.characterIndexForGlyph(at: glyph) ?? 0
            if toggleRepli(at: charIdx) { return }
        }
        super.mouseDown(with: event)
    }

    // MARK: - Replier / Déplier / Focus

    override func keyDown(with event: NSEvent) {
        let isCmd  = event.modifierFlags.contains(.command)
        let isOpt  = event.modifierFlags.contains(.option)
        let isShift = event.modifierFlags.contains(.shift)

        // ⌘↩ — concentration sur la section / quitter si actif
        if event.keyCode == 36 && isCmd && !isOpt && !isShift {
            if (textStorage as? MarkdownTextStorage)?.focusedRange != nil {
                quitterConcentration()
            } else {
                concentrerSection()
            }
            return
        }

        // Esc — quitter la concentration
        if event.keyCode == 53 {
            if (textStorage as? MarkdownTextStorage)?.focusedRange != nil {
                quitterConcentration()
                return
            }
        }

        // ⌘⌥↑ — replier la section courante
        if event.keyCode == 126 && isCmd && isOpt && !isShift {
            replierSection(); return
        }
        // ⌘⌥↓ — déplier la section courante
        if event.keyCode == 125 && isCmd && isOpt && !isShift {
            déplierSection(); return
        }
        // ⌘⌥⇧↑ — tout replier
        if event.keyCode == 126 && isCmd && isOpt && isShift {
            replierTout(); return
        }
        // ⌘⌥⇧↓ — tout déplier
        if event.keyCode == 125 && isCmd && isOpt && isShift {
            déplierTout(); return
        }

        switch event.keyCode {
        case 48 where !event.modifierFlags.contains(.shift):
            // Tab sur un titre → replier/déplier, sinon tabulation normale
            let charIdx = selectedRange().location
            if !toggleRepli(at: charIdx) {
                insertText("\t", replacementRange: selectedRange())
            }
        case 36:
            if !handleListContinuation() { super.keyDown(with: event) }
        default:
            super.keyDown(with: event)
        }
    }

    /// Tente de replier/déplier le titre à `charIndex`. Retourne `true` si on était sur un titre.
    @discardableResult
    private func toggleRepli(at charIndex: Int) -> Bool {
        guard let storage = textStorage as? MarkdownTextStorage else { return false }
        let text      = string as NSString
        let lineRange = text.lineRange(for: NSRange(location: min(charIndex, text.length), length: 0))
        let line      = text.substring(with: lineRange)
        guard let rxObj = try? NSRegularExpression(pattern: #"^#{1,6}[ \t]"#),
              rxObj.firstMatch(in: line,
                               range: NSRange(location: 0, length: (line as NSString).length)) != nil
        else { return false }

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
        return true
    }

    // MARK: - Structural zoom

    func concentrerSection() {
        guard let storage = textStorage as? MarkdownTextStorage else { return }
        let charIndex = selectedRange().location
        let map = storage.headingMap(for: storage.string)
        guard let heading = map.last(where: { $0.offset <= charIndex }) else { return }

        guard let range = storage.sectionRange(forHeadingAt: heading.offset,
                                                in: storage.string) else { return }
        let nsText = storage.string as NSString
        let headingLine = nsText.lineRange(for: NSRange(location: heading.offset, length: 0))
        var title = nsText.substring(with: headingLine)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        title = title.replacingOccurrences(of: "^#{1,6}\\s*", with: "",
                                            options: .regularExpression)

        storage.focusedRange        = range
        storage.focusedHeadingTitle = title
        refreshStorage(storage: storage)

        DispatchQueue.main.async { [weak self] in
            self?.scrollRangeToVisible(NSRange(location: range.location, length: 0))
        }
        if let coordinator = delegate as? CenteredEditorView.Coordinator {
            DispatchQueue.main.async {
                coordinator.parent.focusedTitle = title
            }
        }
    }

    func quitterConcentration() {
        guard let storage = textStorage as? MarkdownTextStorage else { return }
        guard storage.focusedRange != nil else { return }
        storage.focusedRange        = nil
        storage.focusedHeadingTitle = ""
        refreshStorage(storage: storage)
        if let coordinator = delegate as? CenteredEditorView.Coordinator {
            DispatchQueue.main.async {
                coordinator.parent.focusedTitle = nil
            }
        }
    }

    private func refreshStorage(storage: MarkdownTextStorage) {
        storage.beginEditing()
        storage.edited(.editedAttributes,
                       range: NSRange(location: 0, length: storage.length),
                       changeInLength: 0)
        storage.endEditing()
        // Force la régénération des glyphes — sans ça, les glyphes .null
        // issus de .foldHidden restent en cache même après suppression de l'attribut.
        layoutManager?.invalidateGlyphs(
            forCharacterRange: NSRange(location: 0, length: storage.length),
            changeInLength: 0, actualCharacterRange: nil)
        needsDisplay = true
    }

    /// Replie la section courante si dépliée, la déplie si repliée.
    func replierSection() {
        guard let storage = textStorage as? MarkdownTextStorage else { return }
        let charIndex = selectedRange().location
        let map = storage.headingMap(for: storage.string)
        guard let heading = map.last(where: { $0.offset <= charIndex }) else { return }
        if storage.foldedHeadings.contains(heading.offset) {
            storage.foldedHeadings.remove(heading.offset)
        } else {
            storage.foldedHeadings.insert(heading.offset)
        }
        refreshFolding(storage: storage)
    }

    /// Déplie uniquement la section courante.
    func déplierSection() {
        guard let storage = textStorage as? MarkdownTextStorage else { return }
        let charIndex = selectedRange().location
        let map = storage.headingMap(for: storage.string)
        guard let heading = map.last(where: { $0.offset <= charIndex }) else { return }
        storage.foldedHeadings.remove(heading.offset)
        refreshFolding(storage: storage)
    }

    /// Replie tous les titres du document.
    func replierTout() {
        guard let storage = textStorage as? MarkdownTextStorage else { return }
        storage.foldedHeadings = Set(storage.headingMap(for: storage.string).map { $0.offset })
        refreshFolding(storage: storage)
    }

    /// Déplie tous les titres du document.
    func déplierTout() {
        guard let storage = textStorage as? MarkdownTextStorage else { return }
        storage.foldedHeadings.removeAll()
        refreshFolding(storage: storage)
    }

    private func refreshFolding(storage: MarkdownTextStorage) {
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

// MARK: - FoldLayoutManager — citations + replis de sections

final class FoldLayoutManager: NSLayoutManager {

    private let barWidth:  CGFloat = 3
    private let barInset:  CGFloat = 6
    private let barRadius: CGFloat = 1.5

    // MARK: - Repli : glyphes nuls pour les sections cachées

    /// Intercepte la génération des glyphes : tout caractère marqué `.foldHidden`
    /// devient un glyphe `.null` — invisible ET sans espace de layout.
    override func setGlyphs(_ glyphs: UnsafePointer<CGGlyph>,
                             properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
                             characterIndexes charIndexes: UnsafePointer<Int>,
                             font aFont: NSFont,
                             forGlyphRange glyphRange: NSRange) {
        guard let storage = textStorage else {
            super.setGlyphs(glyphs, properties: props, characterIndexes: charIndexes,
                            font: aFont, forGlyphRange: glyphRange)
            return
        }
        let count = glyphRange.length
        var modifiedProps = Array(UnsafeBufferPointer(start: props, count: count))
        for i in 0..<count {
            let charIndex = charIndexes[i]
            guard charIndex < storage.length else { continue }
            if storage.attribute(.foldHidden, at: charIndex, effectiveRange: nil) != nil {
                modifiedProps[i] = .null
            }
        }
        modifiedProps.withUnsafeBufferPointer { ptr in
            super.setGlyphs(glyphs, properties: ptr.baseAddress!,
                            characterIndexes: charIndexes, font: aFont, forGlyphRange: glyphRange)
        }
    }

    // MARK: - Rendu fond + indicateurs

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage,
              let container = textContainers.first else { return }
        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        drawBars(for: .foldBlockquote, color: .systemOrange, in: charRange,
                 storage: storage, container: container, origin: origin)
        drawBars(for: .foldCodeblock, color: .separatorColor, in: charRange,
                 storage: storage, container: container, origin: origin)
        if let mkStorage = storage as? MarkdownTextStorage, !mkStorage.foldedHeadings.isEmpty {
            drawInlineFoldIndicators(storage: mkStorage, charRange: charRange, origin: origin)
        }
    }

    // MARK: - Indicateur inline — même design que ConcentrationPill

    private func drawInlineFoldIndicators(storage: MarkdownTextStorage,
                                          charRange: NSRange,
                                          origin: NSPoint) {
        let text   = storage.string
        let nsText = text as NSString
        let map    = storage.headingMap(for: text)
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        for foldedStart in storage.foldedHeadings {
            guard foldedStart < storage.length else { continue }
            guard map.first(where: { $0.offset == foldedStart }) != nil else { continue }

            let headingLineRange = nsText.lineRange(for: NSRange(location: foldedStart, length: 0))
            guard NSIntersectionRange(headingLineRange, charRange).length > 0 else { continue }

            let titleLen = max(0, headingLineRange.length - 1)
            guard titleLen > 0 else { continue }
            let glRange = glyphRange(
                forCharacterRange: NSRange(location: headingLineRange.location, length: titleLen),
                actualCharacterRange: nil)
            var usedRect = CGRect.null
            enumerateLineFragments(forGlyphRange: glRange) { _, used, _, _, _ in
                usedRect = used
            }
            guard !usedRect.isNull else { continue }

            // Pill 12 × 32 px, coins parfaitement ronds (rayon = moitié hauteur)
            let pillH: CGFloat = 12
            let pillW: CGFloat = 32
            let pillR: CGFloat = pillH / 2

            let pillX = origin.x + usedRect.maxX + 12
            let pillY = origin.y + usedRect.midY - pillH / 2 - 2
            let pillRect = CGRect(x: pillX, y: pillY, width: pillW, height: pillH)
            let pillPath = NSBezierPath(roundedRect: pillRect, xRadius: pillR, yRadius: pillR)

            // Fond : teinte accent légère — propre, pas dépendant du material OS
            let accent = NSColor.controlAccentColor
            accent.withAlphaComponent(isDark ? 0.18 : 0.12).setFill()
            pillPath.fill()

            // Bord : accent un peu plus saturé
            pillPath.lineWidth = 0.5
            accent.withAlphaComponent(isDark ? 0.45 : 0.35).setStroke()
            pillPath.stroke()

            // Dots : couleur accent
            let dotR: CGFloat = 1.5
            let gap:  CGFloat = 4.5
            accent.withAlphaComponent(isDark ? 0.80 : 0.65).setFill()
            for i in 0..<3 {
                let cx = pillRect.midX + CGFloat(i - 1) * (dotR * 2 + gap)
                let dotRect = CGRect(x: cx - dotR, y: pillRect.midY - dotR,
                                     width: dotR * 2, height: dotR * 2)
                NSBezierPath(ovalIn: dotRect).fill()
            }
        }
    }

    // MARK: - Barres verticales (citations / code) — ignorent les ranges repliés

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
                // Ne dessine la barre que si le contenu n'est pas caché par un repli
                let runRange = NSRange(location: pos, length: runEnd - pos)
                var hiddenRange = NSRange(location: NSNotFound, length: 0)
                let isHidden = storage.attribute(.foldHidden, at: pos,
                                                  longestEffectiveRange: &hiddenRange,
                                                  in: runRange) != nil
                if !isHidden {
                    let glRange = glyphRange(forCharacterRange: runRange, actualCharacterRange: nil)
                    enumerateLineFragments(forGlyphRange: glRange) { rect, _, _, _, _ in
                        markedRects.append(rect)
                    }
                }
            }
            pos = runEnd
        }

        guard !markedRects.isEmpty else { return }

        let barX = origin.x + container.lineFragmentPadding + barInset
        var groupRect = markedRects[0]

        func drawBar(rect: CGRect) {
            let barRect = CGRect(x: barX, y: origin.y + rect.minY,
                                 width: barWidth, height: rect.height)
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




