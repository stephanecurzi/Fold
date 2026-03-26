import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var document: FoldDocument
    @Environment(FolderStore.self) var folderStore
    @Environment(TagStore.self) var tagStore
    @Environment(PreferencesStore.self) var prefs
    @Environment(RecentStore.self) var recentStore

    @State private var selectedFileURL: URL?    = nil
    @State private var browsingContent: String  = ""
    @State private var activeTag:       String? = nil
    @State private var columnVisibility: NavigationSplitViewVisibility = .detailOnly
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
            columnVisibility = .detailOnly
            activeTag = nil
        }
        .onChange(of: selectedFileURL) { _, url in
            NSApp.keyWindow?.title = url?.deletingPathExtension().lastPathComponent ?? "Fold"
        }
        .onChange(of: displayedTags) { _, tags in
            if let active = activeTag, !tags.contains(active) { activeTag = nil }
        }
    }
}

