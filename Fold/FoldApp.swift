import SwiftUI
import AppKit

// MARK: - Notifications globales

extension Notification.Name {
    static let foldSearch       = Notification.Name("fold.search")
    static let foldReplace      = Notification.Name("fold.replace")
    static let foldFindNext     = Notification.Name("fold.findNext")
    static let foldFindPrev     = Notification.Name("fold.findPrev")
    static let foldFindHide     = Notification.Name("fold.findHide")
    static let foldAddFolder          = Notification.Name("fold.addFolder")
    static let foldGlobalSearchJump   = Notification.Name("fold.globalSearchJump")
    static let foldGlobalSearchClear  = Notification.Name("fold.globalSearchClear")
    static let foldWikiLink           = Notification.Name("fold.wikiLink")
    static let foldFocusSearch        = Notification.Name("fold.focusSearch")
    static let foldPrefsChanged = Notification.Name("fold.prefsChanged")
}

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Si aucune fenêtre n'est déjà ouverte (ex. ouverture depuis Finder),
        // on crée un document vide directement — sans sélecteur de fichier.
        if NSApp.windows.filter({ $0.isVisible }).isEmpty {
            NSDocumentController.shared.newDocument(nil)
        }
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        NSDocumentController.shared.newDocument(nil)
        return true
    }
}

// MARK: - App

@main
struct FoldApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @State private var folderStore = FolderStore()
    @State private var tagStore    = TagStore()
    @State private var prefs       = PreferencesStore()
    @State private var recentStore = RecentStore()

    init() {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    var body: some Scene {
        DocumentGroup(newDocument: { FoldDocument() }) { config in
            ContentView(document: config.document)
                .environment(folderStore)
                .environment(tagStore)
                .environment(prefs)
                .environment(recentStore)

                .onAppear {
                    folderStore.recentStore = recentStore
                    if let url = config.fileURL {
                        recentStore.add(url)
                    }
                }
        }
        .defaultSize(width: 940, height: 680)
        .commands {
            CommandGroup(replacing: .windowArrangement) {}

            CommandGroup(replacing: .textEditing) {
                Button("Recherche globale") {
                    NotificationCenter.default.post(name: .foldFocusSearch, object: nil)
                }
                .keyboardShortcut("f", modifiers: [.command, .shift, .option])

                Button("Rechercher…") {
                    NotificationCenter.default.post(name: .foldSearch, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)

                Button("Rechercher et remplacer…") {
                    NotificationCenter.default.post(name: .foldReplace, object: nil)
                }
                .keyboardShortcut("f", modifiers: [.command, .option])

                Button("Rechercher le suivant") {
                    NotificationCenter.default.post(name: .foldFindNext, object: nil)
                }
                .keyboardShortcut("g", modifiers: .command)

                Button("Rechercher le précédent") {
                    NotificationCenter.default.post(name: .foldFindPrev, object: nil)
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])

                Button("Masquer la recherche") {
                    NotificationCenter.default.post(name: .foldFindHide, object: nil)
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            }

            // ── Format ────────────────────────────────
            CommandMenu("Format") {
                Menu("Entête") {
                    Button("Entête H1") { formatLine("# ") }
                        .keyboardShortcut("1", modifiers: .command)
                    Button("Entête H2") { formatLine("## ") }
                        .keyboardShortcut("2", modifiers: .command)
                    Button("Entête H3") { formatLine("### ") }
                        .keyboardShortcut("3", modifiers: .command)
                    Button("Entête H4") { formatLine("#### ") }
                        .keyboardShortcut("4", modifiers: .command)
                    Button("Entête H5") { formatLine("##### ") }
                        .keyboardShortcut("5", modifiers: .command)
                    Button("Entête H6") { formatLine("###### ") }
                        .keyboardShortcut("6", modifiers: .command)
                }
                Divider()
                Menu("Liste") {
                    Button("Liste non ordonnée") { formatLine("- ") }
                        .keyboardShortcut("l", modifiers: .command)
                    Button("Liste ordonnée") { formatLine("1. ") }
                        .keyboardShortcut("l", modifiers: [.command, .shift])
                    Button("Liste de tâches") { formatLine("- [ ] ") }
                        .keyboardShortcut("l", modifiers: [.command, .option])
                    Divider()
                    Button("Marquer comme terminé") { toggleCheckbox() }
                        .keyboardShortcut("x", modifiers: [.command, .option])
                }
                Divider()
                Button("Gras") { wrapSelection("**", "**") }
                    .keyboardShortcut("b", modifiers: .command)
                Button("Italique") { wrapSelection("_", "_") }
                    .keyboardShortcut("i", modifiers: .command)
                Button("Code") { wrapSelection("`", "`") }
                    .keyboardShortcut("j", modifiers: .command)
                Button("Barré") { wrapSelection("~~", "~~") }
                    .keyboardShortcut("u", modifiers: [.command, .shift])
                Button("Surligné") { wrapSelection("==", "==") }
                    .keyboardShortcut("u", modifiers: [.command, .option])
                Divider()
                Button("Citation") { formatLine("> ") }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
                Button("Bloc de code") { formatLine("\t") }
                    .keyboardShortcut("j", modifiers: [.command, .shift])
                Divider()
                Button("Lien") { wrapSelection("[", "](url)") }
                    .keyboardShortcut("k", modifiers: .command)
                Button("Lien wiki") { wrapSelection("[[", "]]") }
                    .keyboardShortcut("k", modifiers: [.command, .shift])
                Divider()
                Button("Supprimer les styles") { removeFormatting() }
                Divider()
                Button("Agrandir le texte") { prefs.zoomIn() }
                    .keyboardShortcut("+", modifiers: .command)
                Button("Réduire le texte") { prefs.zoomOut() }
                    .keyboardShortcut("-", modifiers: .command)
                Button("Taille par défaut") { prefs.zoomReset() }
                    .keyboardShortcut("0", modifiers: .command)
            }
        }
        Settings {
            PreferencesView()
                .environment(prefs)
                .environment(tagStore)
        }
    }

    // MARK: - Format helpers

    private func formatLine(_ prefix: String) {
        guard let tv = NSApp.keyWindow?.firstResponder as? NSTextView else { return }
        let sel = tv.selectedRange()
        let str = tv.string as NSString
        let selectionRange = sel.length > 0 ? sel : str.lineRange(for: sel)
        let firstLineRange = str.lineRange(for: NSRange(location: selectionRange.location, length: 0))
        let lastLineRange  = str.lineRange(for: NSRange(location: max(selectionRange.location,
                                                                      selectionRange.location + selectionRange.length - 1),
                                                        length: 0))
        let fullRange = NSRange(location: firstLineRange.location,
                                length: lastLineRange.location + lastLineRange.length - firstLineRange.location)
        let block = str.substring(with: fullRange)
        var lines = block.components(separatedBy: "\n")
        let trailingEmpty = lines.last == ""
        if trailingEmpty { lines.removeLast() }
        let transformed = lines.map { line -> String in
            guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return line }
            let stripped = line.replacingOccurrences(
                of: "^(#{1,6}\\s+|[-*+]\\s+|\\d+\\.\\s+|>\\s+|- \\[[ x]\\] )",
                with: "", options: .regularExpression)
            return prefix + stripped
        }
        var result = transformed.joined(separator: "\n")
        if trailingEmpty { result += "\n" }
        tv.insertText(result, replacementRange: fullRange)
        tv.setSelectedRange(NSRange(location: fullRange.location, length: (result as NSString).length))
    }

    private func wrapSelection(_ before: String, _ after: String) {
        guard let tv = NSApp.keyWindow?.firstResponder as? NSTextView else { return }
        let sel = tv.selectedRange()
        guard sel.length > 0 else { return }
        let selected = (tv.string as NSString).substring(with: sel)
        tv.insertText(before + selected + after, replacementRange: sel)
    }

    private func toggleCheckbox() {
        guard let tv = NSApp.keyWindow?.firstResponder as? NSTextView else { return }
        let sel = tv.selectedRange()
        let str = tv.string as NSString
        let lineRange = str.lineRange(for: sel)
        let line = str.substring(with: lineRange)
        let toggled: String
        if line.contains("- [x] ") {
            toggled = line.replacingOccurrences(of: "- [x] ", with: "- [ ] ")
        } else if line.contains("- [ ] ") {
            toggled = line.replacingOccurrences(of: "- [ ] ", with: "- [x] ")
        } else {
            toggled = "- [ ] " + line
        }
        tv.insertText(toggled, replacementRange: lineRange)
    }

    private func removeFormatting() {
        guard let tv = NSApp.keyWindow?.firstResponder as? NSTextView else { return }
        let sel = tv.selectedRange()
        guard sel.length > 0 else { return }
        var text = (tv.string as NSString).substring(with: sel)
        if let rx = try? NSRegularExpression(pattern: "^```[^\\n]*\\n([\\s\\S]*?)^```\\s*$",
                                              options: [.anchorsMatchLines]) {
            text = rx.stringByReplacingMatches(in: text,
                                               range: NSRange(text.startIndex..., in: text),
                                               withTemplate: "$1")
        }
        let inlinePatterns: [(String, String)] = [
            ("\\*\\*\\*(.+?)\\*\\*\\*", "$1"), ("___(.+?)___", "$1"),
            ("\\*\\*(.+?)\\*\\*", "$1"),        ("__(.+?)__", "$1"),
            ("(?<!`)`(?!`)([^`\\n]+)(?<!`)`(?!`)", "$1"),
            ("\\*([^*\\n]+)\\*", "$1"),          ("_([^_\\n]+)_", "$1"),
            ("~~(.+?)~~", "$1"),                 ("==(.+?)==", "$1"),
        ]
        for (pattern, template) in inlinePatterns {
            if let rx = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) {
                text = rx.stringByReplacingMatches(in: text,
                                                   range: NSRange(text.startIndex..., in: text),
                                                   withTemplate: template)
            }
        }
        for pattern in ["^#{1,6}\\s+", "^[-*+]\\s+", "^\\d+\\.\\s+", "^>\\s*", "^- \\[[ x]\\] "] {
            if let rx = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) {
                text = rx.stringByReplacingMatches(in: text,
                                                   range: NSRange(text.startIndex..., in: text),
                                                   withTemplate: "")
            }
        }
        tv.insertText(text, replacementRange: sel)
    }
}




