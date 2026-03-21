import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var document: FoldDocument
    @Environment(FolderStore.self) var folderStore
    @Environment(TagStore.self) var tagStore
    @Environment(PreferencesStore.self) var prefs

    @State private var activeTag: String? = nil
    @State private var columnVisibility: NavigationSplitViewVisibility = .detailOnly
    @State private var searchStore = SearchStore()

    private var currentTags: [String] {
        TagStore.extract(from: document.text)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(
                currentDocumentTags: currentTags,
                activeTag: $activeTag
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            TextEditorView(
                document: document,
                activeTag: $activeTag
            )
        }
        .environment(folderStore)
        .environment(tagStore)
        .environment(prefs)
        .environment(searchStore)
        .tint(.orange)
        .onAppear {
            columnVisibility = .detailOnly
            activeTag = nil
        }
        .onChange(of: currentTags) { _, tags in
            if let active = activeTag, !tags.contains(active) {
                activeTag = nil
            }
        }
    }
}
