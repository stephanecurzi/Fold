import Foundation
import Observation

private let readableExtensions = ["md", "txt", "text", "markdown", "mdown", "mkd", "rst", "fountain", "tex", "org"]
private let bookmarksKey = "fold.folderBookmarks"
private let fileLimit    = 500

struct FolderItem: Identifiable, Equatable {
    let id: UUID
    let title: String
    let content: String
    let fileURL: URL
    let updatedAt: Date
    static func == (lhs: FolderItem, rhs: FolderItem) -> Bool { lhs.fileURL == rhs.fileURL }
}

struct OpenFolder: Identifiable, Equatable {
    let id: UUID
    let url: URL
    var documents: [FolderItem]
    var warning: String?                          // ← message si limite atteinte
    var name: String { url.lastPathComponent }
    static func == (lhs: OpenFolder, rhs: OpenFolder) -> Bool { lhs.url == rhs.url }
}

@MainActor
@Observable
final class FolderStore {

    var folders: [OpenFolder] = []

    init() { restorePersistedFolders() }

    // MARK: - Public

    func addFolder(url: URL) {
        let (docs, warning) = loadDocuments(from: url)
        if let idx = folders.firstIndex(where: { $0.url == url }) {
            folders[idx].documents = docs
            folders[idx].warning   = warning
        } else {
            folders.append(OpenFolder(id: UUID(), url: url, documents: docs, warning: warning))
        }
        persistFolders()
    }

    func removeFolder(_ folder: OpenFolder) {
        folders.removeAll { $0.id == folder.id }
        persistFolders()
    }

    func refreshAll() {
        for i in folders.indices {
            let (docs, warning) = loadDocuments(from: folders[i].url)
            folders[i].documents = docs
            folders[i].warning   = warning
        }
    }

    // MARK: - Persistance via Security-Scoped Bookmarks

    private func persistFolders() {
        let bookmarks: [Data] = folders.compactMap { folder in
            try? folder.url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }
        UserDefaults.standard.set(bookmarks, forKey: bookmarksKey)
    }

    private func restorePersistedFolders() {
        guard let saved = UserDefaults.standard.array(forKey: bookmarksKey) as? [Data] else { return }
        for data in saved {
            var stale = false
            guard let url = try? URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) else { continue }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            if FileManager.default.fileExists(atPath: url.path) {
                let (docs, warning) = loadDocuments(from: url)
                folders.append(OpenFolder(id: UUID(), url: url, documents: docs, warning: warning))
            }
        }
    }

    // MARK: - Chargement récursif des documents

    /// Parcourt récursivement `url` (sous-dossiers inclus), limite à `fileLimit` fichiers.
    /// Retourne les items triés + un message d'avertissement si la limite est atteinte.
    private func loadDocuments(from url: URL) -> ([FolderItem], String?) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return ([], nil) }

        var items: [FolderItem] = []
        var truncated = false

        for case let fileURL as URL in enumerator {
            guard readableExtensions.contains(fileURL.pathExtension.lowercased()) else { continue }
            if items.count >= fileLimit { truncated = true; break }
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8),
                  let attrs   = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
                  let date    = attrs.contentModificationDate
            else { continue }
            items.append(FolderItem(
                id: UUID(),
                title: fileURL.deletingPathExtension().lastPathComponent,
                content: content,
                fileURL: fileURL,
                updatedAt: date
            ))
        }

        let warning: String? = truncated
            ? "Limite de \(fileLimit) fichiers atteinte — seuls les \(fileLimit) plus récents sont affichés."
            : nil

        return (items.sorted { $0.updatedAt > $1.updatedAt }, warning)
    }
}


