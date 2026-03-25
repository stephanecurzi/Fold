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

    // Accès security-scoped gardés ouverts — clé = url, valeur = résultat de startAccessing
    private var openAccesses: [URL: Bool] = [:]
    private var timer: Timer?

    init() {
        restorePersistedFolders()
        startLiveTimer()
    }

    // MARK: - Public

    func addFolder(url: URL) {
        openAccess(url: url)
        if let idx = folders.firstIndex(where: { $0.url == url }) {
            folders[idx].documents = loadDocuments(from: url)
        } else {
            folders.append(OpenFolder(id: UUID(), url: url, documents: loadDocuments(from: url)))
        }
        persistFolders()
    }

    func removeFolder(_ folder: OpenFolder) {
        folders.removeAll { $0.id == folder.id }
        closeAccess(url: folder.url)
        persistFolders()
    }

    func refreshAll() {
        for i in folders.indices {
            folders[i].documents = loadDocuments(from: folders[i].url)
        }
    }

    // MARK: - Timer live toutes les secondes

    private func startLiveTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.refreshAll()
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    // MARK: - Gestion de l'accès security-scoped

    private func openAccess(url: URL) {
        guard openAccesses[url] == nil else { return }
        openAccesses[url] = url.startAccessingSecurityScopedResource()
    }

    private func closeAccess(url: URL) {
        if openAccesses[url] == true {
            url.stopAccessingSecurityScopedResource()
        }
        openAccesses.removeValue(forKey: url)
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
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            openAccess(url: url)
            folders.append(OpenFolder(id: UUID(), url: url, documents: loadDocuments(from: url)))
        }
    }

    // MARK: - Chargement des documents

    private func loadDocuments(from url: URL) -> [FolderItem] {
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
                return FolderItem(
                    id: UUID(),
                    title: fileURL.deletingPathExtension().lastPathComponent,
                    content: content,
                    fileURL: fileURL,
                    updatedAt: date
                )
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }
}

