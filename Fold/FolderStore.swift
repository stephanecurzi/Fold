import Foundation
import AppKit
import Observation

private let readableExtensions = ["md", "txt", "text", "markdown", "mdown", "mkd", "rst", "fountain", "tex", "org"]
private let bookmarksKey = "fold.folderBookmarks"

// 🔴 FIX: id dérivé de fileURL (stable) au lieu d'un UUID() recréé chaque seconde.
//         SwiftUI ne re-rend plus toute la liste à chaque tick du timer.
struct FolderItem: Identifiable, Equatable {
    var id: URL { fileURL }
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

    private var openAccesses: [URL: Bool] = [:]
    private var timer: Timer?

    // 🔵 FIX: didSet alimente recentStore avec les dossiers déjà chargés
    //         (restorePersistedFolders s'exécute avant que recentStore soit injecté).
    var recentStore: RecentStore? = nil {
        didSet {
            guard let rs = recentStore else { return }
            let allURLs = folders.flatMap { $0.documents.map { $0.fileURL } }
            if !allURLs.isEmpty { rs.addAll(allURLs) }
        }
    }

    init() {
        restorePersistedFolders()
        startLiveTimer()
    }

    // MARK: - Public

    func addFolder(url: URL) {
        openAccess(url: url)
        let docs = loadDocuments(from: url)
        recentStore?.addAll(docs.map { $0.fileURL })

        if let idx = folders.firstIndex(where: { $0.url == url }) {
            folders[idx].documents = docs
        } else {
            folders.append(OpenFolder(id: UUID(), url: url, documents: docs))
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

    // MARK: - Timer live

    private func startLiveTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.refreshAll() }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    // MARK: - Security-scoped access

    private func openAccess(url: URL) {
        guard openAccesses[url] == nil else { return }
        openAccesses[url] = url.startAccessingSecurityScopedResource()
    }

    private func closeAccess(url: URL) {
        if openAccesses[url] == true { url.stopAccessingSecurityScopedResource() }
        openAccesses.removeValue(forKey: url)
    }

    // MARK: - Persistance

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
        // Note : recentStore est nil ici (injecté plus tard depuis FoldApp).
        //        L'alimentation des récents se fait dans le didSet de recentStore.
    }

    // MARK: - Chargement

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
                // 🔴 FIX: plus de UUID() ici — id est dérivé de fileURL
                return FolderItem(
                    title: fileURL.deletingPathExtension().lastPathComponent,
                    content: content,
                    fileURL: fileURL,
                    updatedAt: date
                )
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }
}

