import SwiftUI

private let defaultRecentCount = 10

struct FileListView: View {
    let sidebarSelection: SidebarItem?
    @Binding var selectedURL: URL?

    @Environment(FolderStore.self) var folderStore
    @Environment(RecentStore.self) var recentStore

    @State private var showAllRecents = false

    // ── Données selon la sélection ─────────────────

    private var allFiles: [URL] {
        switch sidebarSelection {
        case .recents:
            return recentStore.urls
        case .folder(let id):
            return folderStore.folders
                .first { $0.id == id }?
                .documents.map { $0.fileURL } ?? []
        case nil:
            return []
        }
    }

    private var visibleFiles: [URL] {
        guard case .recents = sidebarSelection else { return allFiles }
        return showAllRecents ? allFiles : Array(allFiles.prefix(defaultRecentCount))
    }

    private var hiddenCount: Int {
        guard case .recents = sidebarSelection else { return 0 }
        return max(0, allFiles.count - defaultRecentCount)
    }

    private var columnTitle: String {
        switch sidebarSelection {
        case .recents:        return "Récents"
        case .folder(let id): return folderStore.folders.first { $0.id == id }?.name ?? "Dossier"
        case nil:             return ""
        }
    }

    // ── Vue ────────────────────────────────────────

    var body: some View {
        Group {
            if sidebarSelection == nil {
                ContentUnavailableView(
                    "Sélectionne une section",
                    systemImage: "sidebar.left",
                    description: Text("Choisis « Récents » ou un dossier dans la barre latérale.")
                )
            } else if allFiles.isEmpty {
                ContentUnavailableView(
                    "Aucun fichier",
                    systemImage: "doc.text",
                    description: Text("Cette section ne contient pas encore de fichiers.")
                )
            } else {
                List(selection: $selectedURL) {
                    ForEach(visibleFiles, id: \.self) { url in
                        FileRowView(url: url)
                            .tag(url)
                    }

                    if hiddenCount > 0 || (showAllRecents && allFiles.count > defaultRecentCount) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showAllRecents.toggle()
                            }
                        } label: {
                            Text(showAllRecents
                                 ? "Voir moins"
                                 : "Voir plus… (\(hiddenCount))")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 4, trailing: 8))
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .navigationTitle(columnTitle)
        .onChange(of: sidebarSelection) { _, _ in showAllRecents = false }
    }
}

// MARK: - File Row

struct FileRowView: View {
    let url: URL

    private var title: String { url.deletingPathExtension().lastPathComponent }
    private var ext:   String { url.pathExtension.lowercased() }

    private var relativeDate: String {
        guard let attrs = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
              let date  = attrs.contentModificationDate else { return "" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text")
                .font(.system(size: 14))
                .foregroundStyle(.tertiary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(ext)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.secondary.opacity(0.35)))
                    Text(relativeDate)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .listRowInsets(EdgeInsets(top: 2, leading: 10, bottom: 2, trailing: 10))
    }
}

