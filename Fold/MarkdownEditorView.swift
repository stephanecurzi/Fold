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
        // Met à jour le tagColorProvider si changé
        if let storage = tv.textStorage as? MarkdownTextStorage {
            storage.tagColorProvider = tagColorProvider
            // Force re-highlight si le provider change
            storage.edited(.editedAttributes, range: NSRange(location: 0, length: storage.length), changeInLength: 0)
        }
        guard tv.string != text else { return }
        let sel = tv.selectedRange()
        tv.string = text
        let safeLoc = min(sel.location, (text as NSString).length)
        tv.setSelectedRange(NSRange(location: safeLoc, length: 0))
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditorView
        weak var textView: FoldTextView?

        init(_ parent: MarkdownEditorView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            parent.onTextChange(tv.string)
        }
    }
}

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
        isGrammarCheckingEnabled              = false
        isContinuousSpellCheckingEnabled      = true
        usesFontPanel                         = false
        textContainerInset                    = NSSize(width: 70, height: 50)
        backgroundColor                       = .textBackgroundColor
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 48 && !event.modifierFlags.contains(.shift) {
            insertText("  ", replacementRange: selectedRange())
        } else {
            super.keyDown(with: event)
        }
    }

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
        guard let rx = try? NSRegularExpression(pattern: #"^#{1,6}[ \t]"#),
              rx.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) != nil
        else { return }
        let lineStart = lineRange.location
        if storage.foldedHeadings.contains(lineStart) {
            storage.foldedHeadings.remove(lineStart)
        } else {
            storage.foldedHeadings.insert(lineStart)
        }
        storage.edited(.editedAttributes, range: NSRange(location: 0, length: storage.length), changeInLength: 0)
        storage.processEditing()
        needsDisplay = true
    }
}
