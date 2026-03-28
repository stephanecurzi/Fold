//
//  GlobalSearchResult.swift
//  Fold
//
//  Created by Stephane Curzi on 2026-03-28.
//


import Foundation
import Observation

struct GlobalSearchResult: Identifiable {
    let id       = UUID()
    let fileURL  : URL
    let fileTitle: String
    let lineNumber: Int      // 1-based
    let lineContent: String  // ligne complète (trimmée)
    let matchRange: Range<String.Index>  // dans lineContent
}

@MainActor
@Observable
final class GlobalSearchStore {

    var query:   String = "" { didSet { scheduleSearch() } }
    var results: [GlobalSearchResult] = []
    var isSearching = false

    private var debounceTask: Task<Void, Never>? = nil
    private weak var folderStore: FolderStore? = nil

    func bind(to store: FolderStore) { folderStore = store }

    func clear() {
        query   = ""
        results = []
    }

    // MARK: - Search

    private func scheduleSearch() {
        debounceTask?.cancel()
        guard !query.isEmpty else { results = []; return }
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 200_000_000) // 200 ms
            guard !Task.isCancelled else { return }
            await runSearch()
        }
    }

    private func runSearch() async {
        guard let store = folderStore, !query.isEmpty else { results = []; return }
        isSearching = true
        let q = query
        let allDocs = store.folders.flatMap { $0.documents }

        var found: [GlobalSearchResult] = []

        for doc in allDocs {
            let lines = doc.content.components(separatedBy: "\n")
            var lineNum = 0
            for line in lines {
                lineNum += 1
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }
                let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
                if let range = trimmed.range(of: q, options: options) {
                    found.append(GlobalSearchResult(
                        fileURL:     doc.fileURL,
                        fileTitle:   doc.title,
                        lineNumber:  lineNum,
                        lineContent: trimmed,
                        matchRange:  range
                    ))
                }
                if found.count >= 200 { break }
            }
            if found.count >= 200 { break }
        }

        results = found
        isSearching = false
    }
}
