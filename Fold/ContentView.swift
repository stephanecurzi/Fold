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

    // Évite le redimensionnement au premier rendu
    @State private var sidebarResizeReady = false

    private let sidebarWidth:   CGFloat = 240
    private let minEditorWidth: CGFloat = 520   // largeur min pour l'éditeur seul

    private var currentTags: [String] {
        TagStore.extract(from: document.text)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(
                currentDocumentTags: currentTags,
                activeTag: $activeTag
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: sidebarWidth)
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                sidebarResizeReady = true
            }
        }
        .onChange(of: columnVisibility) { old, new in
            guard sidebarResizeReady else { return }
            adjustWindow(from: old, to: new)
        }
        .onChange(of: currentTags) { _, tags in
            if let active = activeTag, !tags.contains(active) {
                activeTag = nil
            }
        }
    }

    // MARK: - Redimensionnement fenêtre selon sidebar

    private func adjustWindow(from old: NavigationSplitViewVisibility,
                               to new: NavigationSplitViewVisibility) {
        guard let window = NSApp.keyWindow else { return }

        let wasVisible = (old == .all || old == .doubleColumn)
        let isVisible  = (new == .all || new == .doubleColumn)

        guard wasVisible != isVisible else { return }

        var frame = window.frame

        if isVisible {
            // N'agrandit que si la fenêtre n'est pas déjà assez large
            guard frame.width < sidebarWidth + minEditorWidth else { return }
            frame.size.width += sidebarWidth
        } else {
            // Rétrécit uniquement si on avait agrandi pour la sidebar
            frame.size.width -= sidebarWidth
            if let screen = window.screen {
                let maxX = screen.visibleFrame.maxX
                if frame.maxX > maxX { frame.origin.x = maxX - frame.width }
            }
        }
        window.setFrame(frame, display: true, animate: true)
    }
}

