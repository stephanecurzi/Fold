import SwiftUI

struct SidebarView: View {
    @Environment(FolderStore.self) var folderStore
    @Environment(TagStore.self) var tagStore

    @Binding var selectedFileURL: URL?
    var currentDocumentTags: [String] = []
    @Binding var activeTag: String?

    @State private var expandedFolders: Set<UUID> = []

    var body: some View {
        List {

            // ── Dossiers ───────────────────────────────
            Section {
                ForEach(folderStore.folders) { folder in
                    FolderSectionRow(
                        folder: folder,
                        isExpanded: expandedFolders.contains(folder.id),
                        selectedFileURL: $selectedFileURL,
                        onToggle: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if expandedFolders.contains(folder.id) {
                                    expandedFolders.remove(folder.id)
                                } else {
                                    expandedFolders.insert(folder.id)
                                }
                            }
                        },
                        onRemove: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                folderStore.removeFolder(folder)
                            }
                        }
                    )
                }
            } header: {
                Text("Dossiers")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(nil)
            }

            // ── Étiquettes ─────────────────────────────
            if !currentDocumentTags.isEmpty {
                Section {
                    ForEach(currentDocumentTags, id: \.self) { tag in
                        TagRowView(
                            tag: tag,
                            tagStore: tagStore,
                            isActive: activeTag == tag
                        ) {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                activeTag = activeTag == tag ? nil : tag
                            }
                        }
                    }
                } header: {
                    Text("Étiquettes")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Fold")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { openFolders() } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .help("Ouvrir un dossier")
            }
        }
    }

    private func openFolders() {
        let panel = NSOpenPanel()
        panel.canChooseFiles          = false
        panel.canChooseDirectories    = true
        panel.allowsMultipleSelection = true
        panel.title = "Ouvrir un dossier"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { folderStore.addFolder(url: url) }
    }
}

// MARK: - Folder header + children

struct FolderSectionRow: View {
    let folder: OpenFolder
    let isExpanded: Bool
    @Binding var selectedFileURL: URL?
    let onToggle: () -> Void
    let onRemove: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 12)
            Image(systemName: "folder.fill")
                .font(.system(size: 12))
                .foregroundStyle(.orange)
            Text(folder.name)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
            Spacer()
            if isHovered {
                Button(action: onRemove) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.tertiary)
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
                .help("Retirer ce dossier")
            }
        }
        .contentShape(Rectangle())
        .onHover { h in
            withAnimation(.easeInOut(duration: 0.15)) { isHovered = h }
        }
        .onTapGesture { onToggle() }
        .listRowInsets(EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8))

        if isExpanded {
            ForEach(folder.documents) { doc in
                SidebarDocRow(url: doc.fileURL, selectedURL: $selectedFileURL)
                    .padding(.leading, 16)
            }
        }
    }
}

// MARK: - Doc row
// Clic simple  → prévisualisation inline (selectedURL)
// Double-clic  → ouvre dans une nouvelle fenêtre via NSDocumentController

struct SidebarDocRow: View {
    let url: URL
    @Binding var selectedURL: URL?
    @State private var isHovered = false

    private var title: String { url.deletingPathExtension().lastPathComponent }
    private var isSelected: Bool { selectedURL == url }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isSelected
                      ? Color.accentColor.opacity(0.18)
                      : (isHovered ? Color.secondary.opacity(0.12) : Color.clear))
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(count: 2) {
            openInNewWindow(url)
        }
        .onTapGesture(count: 1) {
            selectedURL = url
        }
        .help("Clic : aperçu — Double-clic : nouvelle fenêtre")
        .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 8))
    }

    private func openInNewWindow(_ url: URL) {
        // Efface l'aperçu inline — la fenêtre courante retrouve son document
        selectedURL = nil

        _ = url.startAccessingSecurityScopedResource()

        if let existing = NSDocumentController.shared.document(for: url) {
            existing.makeWindowControllers()
            existing.showWindows()
            return
        }
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { doc, _, error in
            if let error {
                print("Fold openDocument error: \(error.localizedDescription)")
                NSWorkspace.shared.open(url)
            }
            doc?.showWindows()
        }
    }
}

// MARK: - Tag Row

struct TagRowView: View {
    let tag: String
    let tagStore: TagStore
    let isActive: Bool
    let onTap: () -> Void

    @State private var showPicker = false
    @State private var isHovered  = false

    var body: some View {
        HStack(spacing: 6) {
            Text("@")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 14)
            Text(tag)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer()
            Circle()
                .fill(tagStore.swiftUIColor(for: tag))
                .frame(width: 10, height: 10)
                .onTapGesture { showPicker = true }
                .popover(isPresented: $showPicker, arrowEdge: .trailing) {
                    TagColorPicker(tag: tag, tagStore: tagStore)
                }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isActive
                      ? tagStore.swiftUIColor(for: tag).opacity(0.18)
                      : (isHovered ? Color.secondary.opacity(0.12) : Color.clear))
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { onTap() }
        .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 8))
    }
}

// MARK: - Color Picker

struct TagColorPicker: View {
    let tag: String
    let tagStore: TagStore

    private let palette: [String] = [
        "#FF383C", "#FF8D28", "#FFCC00", "#34C759",
        "#00C8B3", "#00C3D0", "#00C0E8", "#0088FF",
        "#6155F5", "#CB30E0", "#FF2D55", "#AC7F5E",
        "#FE5000", "#C50018", "#F5A623", "#1D7E23",
        "#005CB8", "#8E8E93"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Couleur de \"\(tag)\"")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(26), spacing: 6), count: 6), spacing: 6) {
                ForEach(palette, id: \.self) { hex in
                    ZStack {
                        Circle().fill(Color(hex: hex)).frame(width: 30, height: 30)
                        if tagStore.tagColors[tag] == hex {
                            Circle()
                                .strokeBorder(Color.primary.opacity(0.5), lineWidth: 2)
                                .frame(width: 30, height: 30)
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .onTapGesture { tagStore.setColor(hex, for: tag) }
                }
            }
        }
        .padding(16)
        .frame(width: 240)
    }
}

