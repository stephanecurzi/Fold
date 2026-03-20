import Foundation
import Observation

private let readableExtensions = ["md", "txt", "text", "markdown", "mdown", "mkd", "rst", "fountain", "tex", "org"]
private let bookmarksKey = "fold.folderBookmarks"

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
        if let idx = folders.firstIndex(where: { $0.url == url }) {
            folders[idx].documents = loadDocuments(from: url)
        } else {
            folders.append(OpenFolder(id: UUID(), url: url, documents: loadDocuments(from: url)))
        }
        persistFolders()
    }

    func removeFolder(_ folder: OpenFolder) {
        folders.removeAll { $0.id == folder.id }
        persistFolders()
    }

    func refreshAll() {
        for i in folders.indices {
            folders[i].documents = loadDocuments(from: folders[i].url)
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
                folders.append(OpenFolder(id: UUID(), url: url, documents: loadDocuments(from: url)))
            }
        }
    }

    // MARK: - Load documents

    private func loadDocuments(from url: URL) -> [FolderItem] {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let urls = (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        )) ?? []

        return urls
            .filter { readableExtensions.contains($0.pathExtension.lowercased()) }
            .compactMap { fileURL -> FolderItem? in
                guard let content = try? String(contentsOf: fileURL, encoding: .utf8),
                      let attrs   = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
                      let date    = attrs.contentModificationDate
                else { return nil }
                return FolderItem(id: UUID(), title: fileURL.deletingPathExtension().lastPathComponent,
                                  content: content, fileURL: fileURL, updatedAt: date)
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }
}

