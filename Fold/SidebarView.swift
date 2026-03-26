import SwiftUI
import AppKit
import Combine

struct SidebarView: View {
    @Environment(FolderStore.self) var folderStore
    @Environment(TagStore.self) var tagStore

    var currentDocumentTags: [String] = []
    @Binding var activeTag: String?

    @State private var expandedFolders:  Set<UUID> = []
    @State private var openDocumentURLs: Set<URL>  = []

    var body: some View {
        List {

            // ── Dossiers ───────────────────────────────
            Section {
                ForEach(folderStore.folders) { folder in
                    FolderSectionRow(
                        folder: folder,
                        isExpanded: expandedFolders.contains(folder.id),
                        openDocumentURLs: openDocumentURLs,
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
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(nil)
                    .padding(.bottom, 2)
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
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                        .padding(.bottom, 2)
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
        .onAppear { refreshOpenURLs() }
        .onReceive(windowPublisher) { _ in refreshOpenURLs() }
    }

    private var windowPublisher: AnyPublisher<Notification, Never> {
        let nc = NotificationCenter.default
        let a = nc.publisher(for: NSWindow.didBecomeKeyNotification)
        let b = nc.publisher(for: NSWindow.willCloseNotification)
        return a.merge(with: b).eraseToAnyPublisher()
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

    private func refreshOpenURLs() {
        openDocumentURLs = Set(
            NSDocumentController.shared.documents.compactMap { $0.fileURL }
        )
    }
}

// MARK: - Folder header + children

struct FolderSectionRow: View {
    let folder: OpenFolder
    let isExpanded: Bool
    let openDocumentURLs: Set<URL>
    let onToggle: () -> Void
    let onRemove: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 10)

            Image(systemName: "folder")
                .font(.system(size: 14))
                .foregroundStyle(.primary)
                .frame(width: 18, alignment: .center)

            Text(folder.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer()

            if isHovered {
                Button(action: onRemove) {
                    Image(systemName: "minus.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale(scale: 0.85)))
                .help("Retirer ce dossier")
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { h in
            withAnimation(.easeInOut(duration: 0.15)) { isHovered = h }
        }
        .onTapGesture { onToggle() }
        .listRowInsets(EdgeInsets(top: 2, leading: 10, bottom: 2, trailing: 10))

        if isExpanded {
            ForEach(folder.documents) { doc in
                SidebarDocRow(url: doc.fileURL, openDocumentURLs: openDocumentURLs)
                    .padding(.leading, 18)
            }
        }
    }
}

// MARK: - Doc row

struct SidebarDocRow: View {
    let url: URL
    let openDocumentURLs: Set<URL>

    @State private var isHovered = false

    private var title: String { url.deletingPathExtension().lastPathComponent }

    private var isOpenInFocus: Bool { openDocumentURLs.contains(url) }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "doc.text")
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .frame(width: 16, alignment: .center)

            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer()

            if isOpenInFocus {
                Circle()
                    .fill(Color.accentColor.opacity(0.8))
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.secondary.opacity(0.10) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { openDocument() }
        .contextMenu {
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } label: {
                Label("Révéler dans le Finder", systemImage: "folder")
            }
        }
        .listRowInsets(EdgeInsets(top: 1, leading: 10, bottom: 1, trailing: 10))
    }

    private func openDocument() {
        _ = url.startAccessingSecurityScopedResource()
        // Réutilise la fenêtre existante si le document est déjà ouvert
        if let existing = NSDocumentController.shared.document(for: url) {
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
        HStack(spacing: 7) {
            Image(systemName: "at")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 16, alignment: .center)

            Text(tag)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer()

            Circle()
                .fill(tagStore.swiftUIColor(for: tag))
                .frame(width: 9, height: 9)
                .onTapGesture { showPicker = true }
                .popover(isPresented: $showPicker, arrowEdge: .trailing) {
                    TagColorPicker(tag: tag, tagStore: tagStore)
                }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive
                      ? tagStore.swiftUIColor(for: tag).opacity(0.14)
                      : (isHovered ? Color.secondary.opacity(0.10) : Color.clear))
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { onTap() }
        .listRowInsets(EdgeInsets(top: 1, leading: 10, bottom: 1, trailing: 10))
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

