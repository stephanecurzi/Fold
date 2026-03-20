import SwiftUI
import AppKit

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

            // Pastille Liquid Glass
            if let tag = activeTag {
                ActiveTagPill(tag: tag) {
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


// MARK: - Pastille Liquid Glass

struct ActiveTagPill: View {
    let tag: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "tag.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.orange)
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
    var tagColors: [String: String] = [:]  // Force re-render quand les couleurs changent
    var tagColorProvider: ((String) -> NSColor)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let textStorage = MarkdownTextStorage()
        textStorage.tagColorProvider = tagColorProvider
        textStorage.activeTag = activeTag
        textStorage.preferences = preferences

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

        DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
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

            // Re-highlight si préférences, tag actif ou couleurs changent
            if prefsChanged || tagChanged || colorsChanged {
                s.edited(.editedAttributes, range: NSRange(location: 0, length: s.length), changeInLength: 0)
            }
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
        }
    }
}

// MARK: - CenteredTextView

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
