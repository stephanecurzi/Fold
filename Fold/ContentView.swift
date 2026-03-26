import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var document: FoldDocument
    @Environment(FolderStore.self) var folderStore
    @Environment(TagStore.self) var tagStore
    @Environment(PreferencesStore.self) var prefs
    @Environment(RecentStore.self) var recentStore

    @State private var selectedFileURL:  URL?    = nil
    @State private var browsingContent:  String  = ""
    @State private var activeTag:        String? = nil
    @State private var columnVisibility: NavigationSplitViewVisibility = .detailOnly
    @State private var searchStore = SearchStore()
    @State private var sidebarResizeReady = false

    private let sidebarWidth: CGFloat = 240

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
            .navigationSplitViewColumnWidth(min: 200, ideal: sidebarWidth)

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
        .onAppear {
            columnVisibility = .detailOnly
            activeTag = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                sidebarResizeReady = true
            }
        }
        .onChange(of: columnVisibility) { old, new in
            guard sidebarResizeReady else { return }
            adjustWindow(from: old, to: new)
        }
        .onChange(of: displayedTags) { _, tags in
            if let active = activeTag, !tags.contains(active) { activeTag = nil }
        }
    }

    private func adjustWindow(from old: NavigationSplitViewVisibility,
                               to new: NavigationSplitViewVisibility) {
        guard let window = NSApp.keyWindow else { return }
        let wasVisible = (old == .all || old == .doubleColumn)
        let isVisible  = (new == .all || new == .doubleColumn)
        guard wasVisible != isVisible else { return }
        var frame = window.frame
        if isVisible {
            frame.size.width += sidebarWidth
        } else {
            frame.size.width -= sidebarWidth
            if let screen = window.screen {
                let maxX = screen.visibleFrame.maxX
                if frame.maxX > maxX { frame.origin.x = maxX - frame.width }
            }
        }
        window.setFrame(frame, display: true, animate: true)
    }
}

