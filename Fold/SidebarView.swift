import SwiftUI

struct SidebarView: View {
    @Environment(FolderStore.self) var folderStore
    @Environment(TagStore.self) var tagStore

    @State private var selectedTag: String? = nil

    var body: some View {
        List {
            // ── Dossiers ───────────────────────────────
            ForEach(folderStore.folders) { folder in
                let filtered = selectedTag.map { tag in
                    folder.documents.filter { TagStore.extract(from: $0.content).contains(tag) }
                } ?? folder.documents

                Section(folder.name) {
                    ForEach(filtered) { doc in
                        DocumentRowView(title: doc.title) {
                            NSDocumentController.shared.openDocument(withContentsOf: doc.fileURL, display: true) { _, _, _ in }
                        }
                    }
                }
            }

            // ── Tags ───────────────────────────────────
            let allTags = folderStore.folders
                .flatMap { $0.documents }
                .flatMap { TagStore.extract(from: $0.content) }
                .uniqueSorted()

            if !allTags.isEmpty {
                Section("Tags") {
                    Label("Tous", systemImage: "tag")
                        .foregroundStyle(selectedTag == nil ? Color.accentColor : .primary)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedTag = nil }

                    ForEach(allTags, id: \.self) { tag in
                        TagRowView(tag: tag, isSelected: selectedTag == tag, tagStore: tagStore) {
                            selectedTag = selectedTag == tag ? nil : tag
                        }
                    }
                }
            }
        }
        .navigationTitle("Fold")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { openFolder() } label: {
                    Label("Ouvrir un dossier", systemImage: "folder.badge.plus")
                }
                .help("Ouvrir un dossier")
            }
        }
    }

    private func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles          = false
        panel.canChooseDirectories    = true
        panel.allowsMultipleSelection = true
        panel.title = "Ouvrir des dossiers"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { folderStore.addFolder(url: url) }
    }
}

// MARK: - Tag Row

struct TagRowView: View {
    let tag: String
    let isSelected: Bool
    let tagStore: TagStore
    let onTap: () -> Void
    @State private var showPicker = false

    var body: some View {
        HStack {
            Label("@\(tag)", systemImage: "at")
                .foregroundStyle(isSelected ? tagStore.swiftUIColor(for: tag) : .primary)
            Spacer()
            Circle()
                .fill(tagStore.swiftUIColor(for: tag))
                .frame(width: 10, height: 10)
                .onTapGesture { showPicker = true }
                .popover(isPresented: $showPicker, arrowEdge: .trailing) {
                    ColorPickerPopover(tag: tag, tagStore: tagStore)
                }
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}

// MARK: - Color Picker Popover

struct ColorPickerPopover: View {
    let tag: String
    let tagStore: TagStore

    private let palette: [String] = [
        "#fe5000", "#ff3b30", "#ff9500", "#ffcc00",
        "#34c759", "#00b340", "#007aff", "#0066ff",
        "#bf00ff", "#ff2d55", "#8e8e93", "#1c1c1e"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Couleur de @\(tag)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(24), spacing: 6), count: 6), spacing: 6) {
                ForEach(palette, id: \.self) { hex in
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 24, height: 24)
                        .overlay(
                            Circle().strokeBorder(
                                tagStore.tagColors[tag] == hex ? Color.primary : Color.clear,
                                lineWidth: 2
                            )
                        )
                        .onTapGesture { tagStore.setColor(hex, for: tag) }
                }
            }
        }
        .padding(14)
        .frame(width: 200)
    }
}

// MARK: - Document Row

struct DocumentRowView: View {
    let title: String
    let onTap: () -> Void

    var body: some View {
        Text(title)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { onTap() }
    }
}

// MARK: - Helpers

extension Array where Element: Hashable {
    func uniqueSorted() -> [Element] where Element: Comparable {
        Array(Set(self)).sorted()
    }
}
