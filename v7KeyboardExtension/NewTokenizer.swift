//
//  NewTokenizer.swift
//  v7Keyboard
//
//  Created by Duc on 29/08/2025.
//  Copyright © 2025 Ethan Sarif-Kattan. All rights reserved.
//

import Foundation
import CoreML
import Darwin // for memcmp

final class NewTokenizer {
    // MARK: - Model data
    private let enumDict: [String: Int]
    private let renumList: [String?]
    private let renumCrtList: [[Any]?]

    // MARK: - Tone caches (index-aligned with renumList)
    private(set) var renumToneList: [Int?]
    private(set) var renumToneMark: [String?]

    // Extra cache: ASCII/diacritics-stripped words for fast prefix checks
    private let asciiList: [String?]

    // MARK: - Preprocess caches
    private let specials: String
    private let allowedSet: CharacterSet     // characters allowed to remain
    private let specialsSet: CharacterSet    // characters that get spaced
    private let whitespaceSet = CharacterSet.whitespacesAndNewlines

    // MARK: - Longest-match trie over tokens
    private final class TrieNode {
        var id: Int? = nil
        var children: [Character: TrieNode] = [:]
    }
    private let trieRoot = TrieNode!

    // MARK: - Tone map
    private let toneMarks: [String: [Int]] = [
        "◌́": [1, 6], "◌": [0], "◌̀": [2],
        "◌̣": [5, 7], "◌̃": [4], "◌̉": [3]
    ]

    // MARK: - Init
    init?() {
        guard
            let enumData = GPTTokenizer.loadJSON(name: "enum_21869") as? [String: Int],
            let renumData = GPTTokenizer.loadJSON(name: "renum_21869") as? [Any],
            let renumCrtData = GPTTokenizer.loadJSON(name: "renum_crt") as? [Any]
        else { return nil }

        self.enumDict = enumData
        self.renumList = renumData as? [String?] ?? []
        self.renumCrtList = renumCrtData.map { $0 is NSNull ? nil : ($0 as? [Any]) }

        // ---- Build tone caches (aligned by index) ----
        let n = max(renumList.count, renumCrtList.count)
        var toneList = Array<Int?>(repeating: nil, count: n)
        var toneMarkList = Array<String?>(repeating: nil, count: n)

        if n > 1 {
            for i in 1..<n {
                if let e = renumCrtList[safe: i], e.count == 3, let tone = e[2] as? Int {
                    toneList[i] = tone
                    if let mark = toneMarks.first(where: { $0.value.contains(tone) })?.key {
                        toneMarkList[i] = mark
                    }
                }
            }
        }
        self.renumToneList = toneList
        self.renumToneMark = toneMarkList

        // ---- Build ASCII/diacritics-stripped cache (aligned by index) ----
        var ascii = Array<String?>(repeating: nil, count: renumList.count)
        if renumList.count > 1 {
            for i in 1..<renumList.count {
                if let w = renumList[i] {
                    let latin = w.applyingTransform(.toLatin, reverse: false) ?? w
                    ascii[i] = latin.applyingTransform(.stripDiacritics, reverse: false)?
                        .lowercased()
                }
            }
        }
        self.asciiList = ascii

        // ---- Preprocess sets (no regex at runtime) ----
        self.specials = ".,!?;:-_()[]{}'\"“”‘’/\\@#$%^&*+=<>~|`…"
        // Only allow characters that appear in the base vocab, everything else is dropped.
        let baseVocabTokens = enumData
            .filter { (_, id) in (1...17788).contains(id) }
            .map { $0.key }
        let allowedChars = baseVocabTokens.joined()
        self.allowedSet  = CharacterSet(charactersIn: allowedChars)
        self.specialsSet = CharacterSet(charactersIn: specials)

        // ---- Build trie using the token vocabulary (IDs 1...17788 only) ----
        // This removes all substring allocation in tokenize()
        for (token, id) in enumData where (1...17788).contains(id) {
            insertToken(token, id: id)
        }
    }

    // MARK: - JSON loader (unchanged from your project)
    static func loadJSON(name: String) -> Any? {
        guard
            let url = Bundle.main.url(forResource: name, withExtension: "json"),
            let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: [])
    }

    // MARK: - Trie insert
    private func insertToken(_ token: String, id: Int) {
        var node = trieRoot
        for ch in token {
            if node.children[ch] == nil { node.children[ch] = TrieNode() }
            node = node.children[ch]!
        }
        node.id = id
    }

    // MARK: - Preprocess (single pass, no regex)
    private func preprocess(_ text: String) -> String {
        // Lowercase once
        let lower = text.lowercased()

        var out = String()
        out.reserveCapacity(lower.count + 8)

        var lastWasSpace = true  // trim leading spaces
        for scalar in lower.unicodeScalars {
            if allowedSet.contains(scalar) {
                out.unicodeScalars.append(scalar)
                lastWasSpace = false
            } else if specialsSet.contains(scalar) {
                if !lastWasSpace { out.append(" ") }
                out.unicodeScalars.append(scalar)
                out.append(" ")
                lastWasSpace = true
            } else {
                // drop disallowed characters; also coalesce spaces
                if !lastWasSpace {
                    out.append(" ")
                    lastWasSpace = true
                }
            }
        }

        // Trim trailing whitespace if any
        if lastWasSpace, !out.isEmpty { out.removeLast() }
        return out
    }

    // MARK: - Tokenize with greedy longest match (trie)
    func tokenize(text: String) -> MLMultiArray {
        let preprocessed = preprocess(text)
        let words = preprocessed.split(separator: " ", omittingEmptySubsequences: true)

        var ids = [Int]()
        ids.reserveCapacity(64)

        for w in words {
            let s = String(w)
            var i = s.startIndex

            while i < s.endIndex {
                var node = trieRoot
                var bestId: Int? = nil
                var bestEnd = i

                var j = i
                while j < s.endIndex, let next = node.children[s[j]] {
                    node = next
                    j = s.index(after: j)
                    if let tid = node.id {
                        bestId = tid
                        bestEnd = j
                    }
                }

                if let tid = bestId {
                    ids.append(tid)
                    i = bestEnd
                } else {
                    // fallback: single character token or unknown (-1 like your code)
                    let ch = String(s[i])
                    ids.append(enumDict[ch] ?? -1)
                    i = s.index(after: i)
                }
            }
        }

        // Left-pad to MAX_SEQUENCE_LEN
        var padded = Array(ids.suffix(Constants.MAX_SEQUENCE_LEN))
        if padded.count < Constants.MAX_SEQUENCE_LEN {
            padded = Array(repeating: 0, count: Constants.MAX_SEQUENCE_LEN - padded.count) + padded
        }

        // Fast fill MLMultiArray via dataPointer (no per-index NSNumber boxing)
        let arr = try! MLMultiArray(shape: [NSNumber(value: Constants.MAX_SEQUENCE_LEN)], dataType: .int32)
        precondition(arr.dataType == .int32)
        let ptr = arr.dataPointer.bindMemory(to: Int32.self, capacity: Constants.MAX_SEQUENCE_LEN)
        for k in 0..<Constants.MAX_SEQUENCE_LEN {
            ptr[k] = Int32(padded[k])
        }
        return arr
    }

    // MARK: - Fast equality (memcmp on Int32 storage when possible)
    func isSameInput(_ a: MLMultiArray?, _ b: MLMultiArray?) -> Bool {
        guard let a = a, let b = b, a.count == b.count else { return false }
        guard a.dataType == .int32, b.dataType == .int32, a.shape == b.shape, a.strides == b.strides else {
            // safe fallback
            for i in 0..<a.count where a[i].intValue != b[i].intValue { return false }
            return true
        }

        let count = a.count
        let ap = a.dataPointer.bindMemory(to: Int32.self, capacity: count)
        let bp = b.dataPointer.bindMemory(to: Int32.self, capacity: count)
        return memcmp(ap, bp, count * MemoryLayout<Int32>.size) == 0
    }

    // MARK: - Filter using caches
    func filter(pattern: String, predictions: [Int], toneMark: String) -> [String] {
        var result: [String] = []
        result.reserveCapacity(Constants.TOP_K)

        let needsTone = !toneMark.isEmpty
        let needsPrefix = !pattern.isEmpty
        let prefix = pattern.lowercased()

        for idx in predictions {
            guard idx > 0, idx < renumList.count, let word = renumList[idx] else { continue }

            if needsTone, idx <= 17788, renumToneMark[safe: idx] != toneMark { continue }

            if needsPrefix {
                if let ascii = asciiList[safe: idx] {
                    if !ascii.hasPrefix(prefix) { continue }
                } else {
                    continue
                }
            }

            result.append(word)
            if result.count >= Constants.TOP_K { break }
        }
        return result
    }
}

// MARK: - Safe subscripting
private extension Array {
    subscript(safe i: Int) -> Element? {
        (i >= 0 && i < count) ? self[i] : nil
    }
}
