//
//  SearchStore.swift
//  Fold
//
//  Created by Stephane Curzi on 2026-03-19.
//


import Foundation
import AppKit
import Observation

@MainActor
@Observable
final class SearchStore {

    var query: String = ""
    var replacement: String = ""
    var isCaseSensitive: Bool = false
    var matchCount: Int = 0
    var currentMatch: Int = 0

    // Référence faible au NSTextView courant
    weak var textView: NSTextView?

    // MARK: - Recherche

    func findNext() {
        guard !query.isEmpty, let tv = textView else { return }
        let text = tv.string as NSString
        let options: NSString.CompareOptions = isCaseSensitive ? [] : .caseInsensitive
        let startFrom = tv.selectedRange().location + tv.selectedRange().length
        var searchRange = NSRange(location: startFrom, length: text.length - startFrom)

        var found = text.range(of: query, options: options, range: searchRange)

        // Wrap around
        if found.location == NSNotFound {
            searchRange = NSRange(location: 0, length: text.length)
            found = text.range(of: query, options: options, range: searchRange)
        }

        if found.location != NSNotFound {
            tv.setSelectedRange(found)
            tv.scrollRangeToVisible(found)
            updateMatchCount()
        }
    }

    func findPrevious() {
        guard !query.isEmpty, let tv = textView else { return }
        let text = tv.string as NSString
        let options: NSString.CompareOptions = isCaseSensitive
            ? .backwards
            : [.caseInsensitive, .backwards]

        let endAt = tv.selectedRange().location
        var searchRange = NSRange(location: 0, length: endAt)
        var found = text.range(of: query, options: options, range: searchRange)

        // Wrap around
        if found.location == NSNotFound {
            searchRange = NSRange(location: 0, length: text.length)
            found = text.range(of: query, options: options, range: searchRange)
        }

        if found.location != NSNotFound {
            tv.setSelectedRange(found)
            tv.scrollRangeToVisible(found)
            updateMatchCount()
        }
    }

    // MARK: - Remplacement

    func replaceCurrent() {
        guard !query.isEmpty, let tv = textView else { return }
        let sel = tv.selectedRange()
        let selected = (tv.string as NSString).substring(with: sel)
        let options: NSString.CompareOptions = isCaseSensitive ? [] : .caseInsensitive
        if selected.compare(query, options: options) == .orderedSame {
            tv.insertText(replacement, replacementRange: sel)
        }
        findNext()
        updateMatchCount()
    }

    func replaceAll() {
        guard !query.isEmpty, let tv = textView else { return }
        let options: NSString.CompareOptions = isCaseSensitive ? [] : .caseInsensitive
        var result = tv.string
        let range = result.startIndex..<result.endIndex
        if isCaseSensitive {
            result = result.replacingOccurrences(of: query, with: replacement, options: options, range: range)
        } else {
            result = result.replacingOccurrences(of: query, with: replacement, options: options, range: range)
        }
        tv.string = result
        tv.didChangeText()
        updateMatchCount()
    }

    func updateMatchCount() {
        guard !query.isEmpty, let tv = textView else { matchCount = 0; return }
        let text = tv.string as NSString
        let options: NSString.CompareOptions = isCaseSensitive ? [] : .caseInsensitive
        var count = 0
        var searchRange = NSRange(location: 0, length: text.length)
        while true {
            let found = text.range(of: query, options: options, range: searchRange)
            guard found.location != NSNotFound else { break }
            count += 1
            searchRange = NSRange(location: found.location + found.length,
                                  length: text.length - found.location - found.length)
        }
        matchCount = count
    }

    func clearHighlights() {
        guard let tv = textView else { return }
        tv.setSelectedRange(NSRange(location: 0, length: 0))
    }
}