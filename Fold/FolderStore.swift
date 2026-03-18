import Foundation
import Observation

private let readableExtensions = ["md", "txt", "text", "markdown", "mdown", "mkd", "rst", "fountain", "tex", "org"]

// Document simplifié — remplace TextDocument
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

    init() {}

    func addFolder(url: URL) {
        if let idx = folders.firstIndex(where: { $0.url == url }) {
            folders[idx].documents = loadDocuments(from: url)
            return
        }
        folders.append(OpenFolder(id: UUID(), url: url, documents: loadDocuments(from: url)))
    }

    func refreshAll() {
        for i in folders.indices {
            folders[i].documents = loadDocuments(from: folders[i].url)
        }
    }

    func removeFolder(_ folder: OpenFolder) {
        folders.removeAll { $0.id == folder.id }
    }

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
                return FolderItem(
                    id:        UUID(),
                    title:     fileURL.deletingPathExtension().lastPathComponent,
                    content:   content,
                    fileURL:   fileURL,
                    updatedAt: date
                )
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }
}
