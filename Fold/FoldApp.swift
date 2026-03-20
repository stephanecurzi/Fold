import SwiftUI
import AppKit

@main
struct FoldApp: App {
    @State private var folderStore = FolderStore()
    @State private var tagStore    = TagStore()
    @State private var prefs       = PreferencesStore()

    init() {
        NSWindow.allowsAutomaticWindowTabbing = false
        // Force la langue française pour les menus système
        UserDefaults.standard.set(["fr"], forKey: "AppleLanguages")
    }

    var body: some Scene {
        DocumentGroup(newDocument: { FoldDocument() }) { config in
            ContentView(document: config.document)
                .environment(folderStore)
                .environment(tagStore)
                .environment(prefs)
                .tint(.orange)
        }
        .defaultSize(width: 1200, height: 760)
        .commands {
            // ── Supprime les tabs ──────────────────────
            CommandGroup(replacing: .windowArrangement) {}

            // ── Menu Format ───────────────────────────
            CommandMenu("Format") {

                // Entêtes — sous-menu
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

                // Listes — sous-menu
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

                // Styles
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

                // Blocs
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

                // Zoom typographie
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
