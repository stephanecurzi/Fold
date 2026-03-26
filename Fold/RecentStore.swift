import Foundation
import AppKit
import Observation

private let recentsKey = "fold.recentURLs"
private let maxStored  = 50

@MainActor
@Observable
final class RecentStore {

    private(set) var urls: [URL] = []

    init() { load() }

    // MARK: - Public

    func add(_ url: URL) {
        var list = urls.filter { $0 != url }
        list.insert(url, at: 0)
        urls = Array(list.prefix(maxStored))
        save()
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
    }

    func addAll(_ newURLs: [URL]) {
        var list = urls
        for url in newURLs.reversed() {
            list.removeAll { $0 == url }
            list.insert(url, at: 0)
        }
        urls = Array(list.prefix(maxStored))
        save()
        newURLs.forEach { NSDocumentController.shared.noteNewRecentDocumentURL($0) }
    }

    // MARK: - Persistance

    private func save() {
        UserDefaults.standard.set(urls.map { $0.path }, forKey: recentsKey)
    }

    private func load() {
        let paths = UserDefaults.standard.stringArray(forKey: recentsKey) ?? []
        urls = paths
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }
}
