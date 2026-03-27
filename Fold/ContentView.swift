import SwiftUI
import AppKit

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
    }
}


