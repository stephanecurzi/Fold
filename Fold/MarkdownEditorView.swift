import SwiftUI
import AppKit

struct MarkdownEditorView: NSViewRepresentable {
    @Binding var text: String
    var onTextChange: (String) -> Void
    var tagColorProvider: ((String) -> NSColor)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let textStorage = MarkdownTextStorage()
        textStorage.tagColorProvider = tagColorProvider

        let layoutMgr = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        textStorage.addLayoutManager(layoutMgr)
        layoutMgr.addTextContainer(container)

        let textView = FoldTextView(frame: .zero, textContainer: container)
        textView.configure()
        textView.delegate = context.coordinator
        context.coordinator.textView = textView

        let scroll = NSScrollView()
        scroll.hasVerticalScroller   = true
        scroll.autohidesScrollers    = true
        scroll.drawsBackground       = false
        scroll.hasHorizontalScroller = false
        scroll.documentView          = textView
        textView.minSize             = NSSize(width: 0, height: scroll.contentSize.height)
        textView.maxSize             = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                              height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable   = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask        = .width

        DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        if let s = tv.textStorage as? MarkdownTextStorage { s.tagColorProvider = tagColorProvider }
        guard tv.string != text else { return }
        let sel = tv.selectedRange()
        tv.string = text
        tv.setSelectedRange(NSRange(location: min(sel.location, (text as NSString).length), length: 0))
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditorView
        weak var textView: FoldTextView?
        init(_ p: MarkdownEditorView) { parent = p }
        func textDidChange(_ n: Notification) {
            guard let tv = n.object as? NSTextView else { return }
            parent.text = tv.string
            parent.onTextChange(tv.string)
        }
    }
}

// MARK: - FoldTextView

final class FoldTextView: NSTextView {
    func configure() {
        isRichText                            = false
        allowsUndo                            = true
        isEditable                            = true
        isSelectable                          = true
        isAutomaticQuoteSubstitutionEnabled   = false
        isAutomaticDashSubstitutionEnabled    = false
        isAutomaticLinkDetectionEnabled       = false
        isAutomaticSpellingCorrectionEnabled  = false
        isContinuousSpellCheckingEnabled      = false
        usesFontPanel                         = false
        textContainerInset                    = NSSize(width: 70, height: 50)
        backgroundColor                       = .textBackgroundColor
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 48 && !event.modifierFlags.contains(.shift) {
            // Tab sur titre → fold/unfold, sinon tabulation réelle
            if !toggleFold(at: selectedRange().location) {
                insertText("\t", replacementRange: selectedRange())
            }
        } else {
            super.keyDown(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) && event.clickCount == 1 {
            let point      = convert(event.locationInWindow, from: nil)
            let adjustedPt = NSPoint(x: point.x - textContainerInset.width,
                                     y: point.y - textContainerInset.height)
            var fraction: CGFloat = 0
            let glyph      = layoutManager?.glyphIndex(for: adjustedPt,
                                                        in: textContainer!,
                                                        fractionOfDistanceThroughGlyph: &fraction) ?? 0
            let charIdx    = layoutManager?.characterIndexForGlyph(at: glyph) ?? 0
            if toggleFold(at: charIdx) { return }
        }
        super.mouseDown(with: event)
    }

    @discardableResult
    private func toggleFold(at charIndex: Int) -> Bool {
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
        storage.edited(.editedAttributes, range: NSRange(location: 0, length: storage.length), changeInLength: 0)
        storage.processEditing()
        needsDisplay = true
        return true
    }
}

