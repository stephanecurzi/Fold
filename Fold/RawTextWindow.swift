import AppKit

// MARK: - Notification de mise à jour live

extension Notification.Name {
    static let foldRawUpdate = Notification.Name("fold.rawUpdate")
}

// MARK: - Controller

final class RawTextWindowController: NSWindowController {

    static let shared = RawTextWindowController()

    private let textView:   NSTextView
    private let scrollView: NSScrollView

    private init() {
        let tv = NSTextView()
        tv.isEditable              = false
        tv.isSelectable            = true
        tv.isRichText              = false
        tv.font                    = .monospacedSystemFont(ofSize: 12, weight: .regular)
        tv.textContainerInset      = NSSize(width: 16, height: 16)
        tv.isVerticallyResizable   = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask        = .width
        tv.isAutomaticQuoteSubstitutionEnabled = false

        let sv = NSScrollView(frame: NSRect(x: 0, y: 0, width: 640, height: 540))
        sv.hasVerticalScroller   = true
        sv.autohidesScrollers    = true
        sv.hasHorizontalScroller = false
        sv.documentView          = tv
        tv.minSize = NSSize(width: 0, height: sv.contentSize.height)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                            height: CGFloat.greatestFiniteMagnitude)

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 540),
            styleMask:   [.titled, .closable, .resizable, .miniaturizable],
            backing:     .buffered,
            defer:       false
        )
        win.title                = "Fold — Texte brut"
        win.contentView          = sv
        win.isReleasedWhenClosed = false
        win.center()

        self.textView   = tv
        self.scrollView = sv
        super.init(window: win)

        // Mise à jour live quand la fenêtre est déjà ouverte
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onUpdate(_:)),
            name: .foldRawUpdate,
            object: nil
        )
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - API publique

    /// Ouvre la fenêtre et affiche le texte fourni.
    /// Appelé directement depuis le menu — pas de notification.
    func show(text: String) {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        // setText après makeKeyAndOrderFront : la fenêtre a une taille réelle,
        // le NSTextView peut se redimensionner correctement.
        setText(text)
    }

    // MARK: - Mise à jour live

    @objc private func onUpdate(_ n: Notification) {
        guard window?.isVisible == true,
              let text = n.userInfo?["text"] as? String else { return }
        let origin = scrollView.documentVisibleRect.origin
        setText(text)
        scrollView.documentView?.scroll(origin)
    }

    // MARK: - Helpers

    private func setText(_ text: String) {
        textView.string = text
        let lines = text.components(separatedBy: "\n").count
        let chars  = text.count
        window?.title = "Fold — Texte brut  ·  \(lines) lignes  ·  \(chars) car."
    }
}

