import SwiftUI
import AppKit
import Combine

private let sidebarVisibilityKey = "fold.sidebarVisible"

struct ContentView: View {
    @ObservedObject var document: FoldDocument
    @Environment(FolderStore.self) var folderStore
    @Environment(TagStore.self) var tagStore
    @Environment(PreferencesStore.self) var prefs
    @Environment(RecentStore.self) var recentStore

    @State private var activeTag:        String? = nil
    @State private var columnVisibility: NavigationSplitViewVisibility = {
        UserDefaults.standard.bool(forKey: sidebarVisibilityKey) ? .all : .detailOnly
    }()
    @State private var searchStore = SearchStore()

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(
                currentDocumentTags: TagStore.extract(from: document.text),
                activeTag: $activeTag,
                columnVisibility: columnVisibility
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 200)
        } detail: {
            TextEditorView(document: document, activeTag: $activeTag)
        }
        .environment(folderStore)
        .environment(tagStore)
        .environment(prefs)
        .environment(recentStore)
        .environment(searchStore)

        .onAppear { activeTag = nil }
        .onChange(of: columnVisibility) { _, new in
            let isVisible = (new == .all || new == .doubleColumn)
            UserDefaults.standard.set(isVisible, forKey: sidebarVisibilityKey)
        }
        .onChange(of: document.text) { _, _ in
            if let active = activeTag,
               !TagStore.extract(from: document.text).contains(active) {
                activeTag = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .foldWikiLink)) { n in
            guard let title = n.userInfo?["title"] as? String else { return }
            openWikiLink(title: title)
        }
        .onReceive(NotificationCenter.default.publisher(for: .foldFocusSearch)) { _ in
            // Géré dans SidebarView via la même notification
        }
    }

    // MARK: - Wiki link resolution

    private func openWikiLink(title: String) {
        let lower = title.lowercased()
        for folder in folderStore.folders {
            if let match = folder.documents.first(where: {
                $0.title.lowercased() == lower
            }) {
                let url = match.fileURL
                _ = url.startAccessingSecurityScopedResource()
                if let existing = NSDocumentController.shared.document(for: url) {
                    existing.showWindows()
                    return
                }
                NSDocumentController.shared.openDocument(
                    withContentsOf: url, display: true
                ) { doc, _, _ in doc?.showWindows() }
                return
            }
        }

        // 🔵 FIX: on capture la fenêtre courante et son titre original avant le délai.
        //         L'ancienne version pouvait restaurer le titre sur la mauvaise fenêtre
        //         et hardcodait "Fold" au lieu du nom du fichier ouvert.
        if let window = NSApp.keyWindow {
            let originalTitle = window.title
            window.title = "« \(title) » introuvable"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak window] in
                window?.title = originalTitle
            }
        }
    }
}

