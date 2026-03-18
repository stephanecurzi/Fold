import SwiftUI
import AppKit

struct TextEditorView: View {
    @ObservedObject var document: FoldDocument
    @Environment(TagStore.self) var tagStore

    var body: some View {
        CenteredEditorView(
            text: $document.text,
            maxWidth: 780,
            onTextChange: { _ in },
            tagColorProvider: { tagStore.color(for: $0) }
        )
    }
}

struct CenteredEditorView: NSViewRepresentable {
    @Binding var text: String
    let maxWidth: CGFloat
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
        textView.isContinuousSpellCheckingEnabled     = true
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

        DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        if let s = tv.textStorage as? MarkdownTextStorage {
            s.tagColorProvider = tagColorProvider
        }
        guard tv.string != text else { return }
        let sel = tv.selectedRange()
        tv.string = text
        tv.setSelectedRange(NSRange(location: min(sel.location, (text as NSString).length), length: 0))
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CenteredEditorView
        weak var textView: CenteredTextView?
        init(_ p: CenteredEditorView) { parent = p }

        func textDidChange(_ n: Notification) {
            guard let tv = n.object as? NSTextView else { return }
            parent.text = tv.string
            parent.onTextChange(tv.string)
        }
    }
}

final class CenteredTextView: NSTextView {
    var maxContentWidth: CGFloat = 780

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateInset()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateInset()
    }

    private func updateInset() {
        let width = frame.width
        let horizontalInset = max(50, (width - maxContentWidth) / 2)
        textContainerInset = NSSize(width: horizontalInset, height: 50)
    }
}
