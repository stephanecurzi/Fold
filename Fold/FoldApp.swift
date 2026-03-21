import SwiftUI
import AppKit

// MARK: - Notifications globales (définies ici une seule fois)

extension Notification.Name {
    static let foldSearch    = Notification.Name("fold.search")
    static let foldReplace   = Notification.Name("fold.replace")
    static let foldFindNext  = Notification.Name("fold.findNext")
    static let foldFindPrev  = Notification.Name("fold.findPrev")
    static let foldFindHide  = Notification.Name("fold.findHide")
    static let foldAddFolder = Notification.Name("fold.addFolder")
}

@main
struct FoldApp: App {
    @State private var folderStore = FolderStore()
    @State private var tagStore    = TagStore()
    @State private var prefs       = PreferencesStore()

    init() {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    var body: some Scene {
        DocumentGroup(newDocument: { FoldDocument() }) { config in
            ContentView(document: config.document)
                .environment(folderStore)
                .environment(tagStore)
                .environment(prefs)
                .tint(.orange)
        }
        .defaultSize(width: 940, height: 680)
        .commands {
            CommandGroup(replacing: .windowArrangement) {}

            // ── Recherche ─────────────────────────────
            // SwiftUI intercepte ⌘F via CommandGroup et
            // poste une notification. CenteredTextView
            // l'attrape et appelle performTextFinderAction
            // avec un NSMenuItem (le seul sender valide
            // car AppKit lit sender.tag pour connaître l'action).
            CommandGroup(replacing: .textEditing) {
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
                Button("Italique") { wrapSelection("*", "*") }
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
                Button("Bloc de code") { wrapSelection("```\n", "\n```") }
                    .keyboardShortcut("j", modifiers: [.command, .shift])
                Divider()
                Button("Lien") { wrapSelection("[", "](url)") }
                    .keyboardShortcut("k", modifiers: .command)
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
        }
    }

    // MARK: - Format helpers

    private func formatLine(_ prefix: String) {
        guard let tv = NSApp.keyWindow?.firstResponder as? NSTextView else { return }
        let sel = tv.selectedRange()
        let str = tv.string as NSString
        let lineRange = str.lineRange(for: sel)
        let line = str.substring(with: lineRange)
        let stripped = line.replacingOccurrences(
            of: "^(#{1,6}\\s+|[-*+]\\s+|\\d+\\.\\s+|>\\s+|- \\[[ x]\\] )",
            with: "", options: .regularExpression
        )
        tv.insertText(prefix + stripped, replacementRange: lineRange)
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
        let patterns = ["\\*\\*\\*(.+?)\\*\\*\\*", "\\*\\*(.+?)\\*\\*", "\\*(.+?)\\*",
                        "`(.+?)`", "~~(.+?)~~", "==(.+?)==",
                        "^#{1,6}\\s+", "^[-*+]\\s+", "^\\d+\\.\\s+",
                        "^>\\s+", "^- \\[[ x]\\] "]
        for pattern in patterns {
            if let rx = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) {
                let range = NSRange(text.startIndex..., in: text)
                text = rx.stringByReplacingMatches(in: text, range: range, withTemplate: "$1")
            }
        }
        tv.insertText(text, replacementRange: sel)
    }
}

