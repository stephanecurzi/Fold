import SwiftUI
import AppKit

private let sidebarVisibilityKey = "fold.sidebarVisible"

struct ContentView: View {
    @ObservedObject var document: FoldDocument
    @Environment(FolderStore.self) var folderStore
    @Environment(TagStore.self) var tagStore
    @Environment(PreferencesStore.self) var prefs
    @Environment(RecentStore.self) var recentStore

    @State private var selectedFileURL: URL?    = nil
    @State private var browsingContent: String  = ""
    @State private var activeTag:       String? = nil
    @State private var columnVisibility: NavigationSplitViewVisibility = {
        UserDefaults.standard.bool(forKey: sidebarVisibilityKey) ? .all : .detailOnly
    }()
    @State private var searchStore = SearchStore()

    private var displayedTags: [String] {
        selectedFileURL != nil
            ? TagStore.extract(from: browsingContent)
            : TagStore.extract(from: document.text)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(
                selectedFileURL: $selectedFileURL,
                currentDocumentTags: displayedTags,
                activeTag: $activeTag
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            if let url = selectedFileURL {
                InlineFileView(url: url, content: $browsingContent, activeTag: $activeTag)
            } else {
                TextEditorView(document: document, activeTag: $activeTag)
            }
        }
        .environment(folderStore)
        .environment(tagStore)
        .environment(prefs)
        .environment(recentStore)
        .environment(searchStore)
        .tint(.orange)
        .navigationTitle(selectedFileURL?.deletingPathExtension().lastPathComponent ?? "Fold")
        .onAppear {
            activeTag = nil
        }
        .onChange(of: columnVisibility) { _, new in
            let isVisible = (new == .all || new == .doubleColumn)
            UserDefaults.standard.set(isVisible, forKey: sidebarVisibilityKey)
        }
        .onChange(of: selectedFileURL) { _, url in
            guard url != nil else { return }
            NSApp.keyWindow?.title = url?.deletingPathExtension().lastPathComponent ?? "Fold"
            discardIfUntitledAndEmpty()
        }
        .onChange(of: displayedTags) { _, tags in
            if let active = activeTag, !tags.contains(active) { activeTag = nil }
        }
    }

    // MARK: - Discard untitled empty document

    private func discardIfUntitledAndEmpty() {
        // Cherche un NSDocument sans URL (jamais sauvegardé) et non modifié (vide)
        guard let nsDoc = NSDocumentController.shared.documents.first(where: {
            $0.fileURL == nil && !$0.isDocumentEdited
        }) else { return }

        nsDoc.close()
    }
}

