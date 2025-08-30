//
//  V7GPTTokenizer.swift
//  v7Keyboard
//
//  Created by Duc on 22/06/2025.
//  Copyright © 2025 Ethan Sarif-Kattan. All rights reserved.
//

import Foundation
import CoreML

class GPTTokenizer {
    private let enumDict: [String: Int]
    private let renumList: [String?]
    private let renumCrtList: [[Any]?]
    private let toneMarks = [
        "◌́": [1, 6], "◌": [0], "◌̀": [2],
        "◌̣": [5, 7], "◌̃": [4], "◌̉": [3]
    ]
    
    // 🔹 Cached parallel lists (index 0 reserved as nil/empty)
    private(set) var renumToneList: [Int?] = [nil]
    private(set) var renumToneMark: [String?] = [nil]
    
    // New cached regex + specials
    private let specials: String
    private let allowRegex: NSRegularExpression
    private let specialsRegex: NSRegularExpression

    init?() {
        guard let enumData = GPTTokenizer.loadJSON(name: "enum_21869") as? [String: Int],
              let renumData = GPTTokenizer.loadJSON(name: "renum_21869") as? [Any],
              let renumCrtData = GPTTokenizer.loadJSON(name: "renum_crt") as? [Any] else {
            return nil
        }
        
        self.enumDict = enumData
        self.renumList = renumData as? [String?] ?? []
        self.renumCrtList = renumCrtData.map { elem in
            if elem is NSNull { return nil }
            return elem as? [Any]
        }
        // 🔹 Build tone caches, keeping index 0 as nil
        for entry in self.renumCrtList.dropFirst() {
            if let e = entry, e.count == 3,
               let _ = e[0] as? String,     // consonant
               let _ = e[1] as? String,     // rhyme
               let eTone = e[2] as? Int {

                if let toneMark = toneMarks.first(where: { $0.value.contains(eTone) })?.key {
                    self.renumToneList.append(eTone)
                    self.renumToneMark.append(toneMark)
                }
            }
        }
        
        // ---- Build constants once ----
        self.specials = ".,!?;:-_()[]{}'\"“”‘’/\\\\@#$%^&*+=<>~|`…"
        
        let baseVocab = enumData
            .filter { (_, id) in (1...17788).contains(id) }
            .map { (token, _) in token }
        let charset = Set(baseVocab.joined() + specials)
        let escaped = charset
            .map { NSRegularExpression.escapedPattern(for: String($0)) }
            .joined()
        let allowPattern = "[^ \(escaped)]"

        self.allowRegex = try! NSRegularExpression(pattern: allowPattern, options: [])

        let specialsPattern = "([\(NSRegularExpression.escapedPattern(for: specials))])"
        self.specialsRegex = try! NSRegularExpression(pattern: specialsPattern, options: [])
        keyboardLogger.debug("Done init tokenizer")
    }
    
    // MARK: - Preprocess (String -> String)
//    private func preprocess(_ text: String) -> String {
//        var clean = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
//        
//        clean = allowRegex.stringByReplacingMatches(
//            in: clean,
//            options: [],
//            range: NSRange(location: 0, length: clean.count),
//            withTemplate: ""
//        )
//        
//        clean = specialsRegex.stringByReplacingMatches(
//            in: clean,
//            options: [],
//            range: NSRange(location: 0, length: clean.count),
//            withTemplate: " $1 "
//        )
//        
//        clean = clean.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
//        return clean.trimmingCharacters(in: .whitespacesAndNewlines)
//    }
//    
    private func preprocess(_ text: String) -> String {
        var clean = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // use NSString length for NSRange
        var nsClean = clean as NSString
        var range = NSRange(location: 0, length: nsClean.length)
        clean = allowRegex.stringByReplacingMatches(in: clean, options: [], range: range, withTemplate: "")

        nsClean = clean as NSString
        range = NSRange(location: 0, length: nsClean.length)
        clean = specialsRegex.stringByReplacingMatches(in: clean, options: [], range: range, withTemplate: " $1 ")

        clean = clean.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return clean.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Tokenize with greedy merge
    func tokenize(text: String) -> MLMultiArray {
        let preprocessed = preprocess(text)
        let words = preprocessed.split(separator: " ").map { String($0) }
        var ids: [Int] = []
        
        for w in words {
            let chars = w.map { String($0) }
            var i = 0
            while i < chars.count {
                var match: String? = nil
                var j = chars.count
                while j > i {
                    let sub = chars[i..<j].joined()
                    if let _ = enumDict[sub] {
                        match = sub
                        break
                    }
                    j -= 1
                }
                if let sub = match, let id = enumDict[sub] {
                    ids.append(id)
                    i += sub.count
                } else {
                    let id = enumDict[chars[i]] ?? -1
                    ids.append(id)
                    i += 1
                }
            }
        }
        
        // Left-pad to MAX_SEQUENCE_LEN
        var padded = Array(ids.suffix(Constants.MAX_SEQUENCE_LEN))
        if padded.count < Constants.MAX_SEQUENCE_LEN {
            let padCount = Constants.MAX_SEQUENCE_LEN - padded.count
            padded = Array(repeating: 0, count: padCount) + padded
        }

        let array = try! MLMultiArray(shape: [NSNumber(value: Constants.MAX_SEQUENCE_LEN)], dataType: .int32)
        for i in 0..<Constants.MAX_SEQUENCE_LEN {
            array[i] = padded[i] as NSNumber
        }

        return array
    }

    func isSameInput(_ a: MLMultiArray?, _ b: MLMultiArray?) -> Bool {
        guard let a = a, let b = b else { return false }
        guard a.count == b.count else { return false }

        for i in 0..<a.count {
            if a[i].intValue != b[i].intValue {
                return false
            }
        }
        return true
    }


//    func tokenize(text: String) -> MLMultiArray {
//        let tokens = text.split(separator: " ").compactMap { enumDict[String($0)] }
//        var padded = Array(tokens.suffix(Constants.MAX_SEQUENCE_LEN))
//        if padded.count < Constants.MAX_SEQUENCE_LEN {
//            let padCount = Constants.MAX_SEQUENCE_LEN - padded.count
//            padded = Array(repeating: 0, count: padCount) + padded
//        }
//
//        let array = try! MLMultiArray(shape: [NSNumber(value: Constants.MAX_SEQUENCE_LEN)], dataType: .int32)
//        for i in 0..<Constants.MAX_SEQUENCE_LEN {
//            array[i] = NSNumber(value: padded[i])
//        }
//        return array
//    }

    func filter(pattern: String, predictions: [Int], toneMark: String) -> [String] {
        var result: [String] = []
        
        var iterate = 0
        for idx in predictions {
            iterate += 1
            if iterate > Constants.MAX_FILTER_ITERATE { break }

            guard idx < renumList.count else { continue }
            guard let word = renumList[idx] else { continue }
            
            // 🔹 Tone check
            if !toneMark.isEmpty {
                if idx < 1 || idx > 17788 { continue }
                if renumToneMark[idx] != toneMark { continue }
            }
            
            // 🔹 Pattern check
            if !pattern.isEmpty {
                var asciiWord = word.applyingTransform(.toLatin, reverse: false)?
                                        .applyingTransform(.stripDiacritics, reverse: false) ?? word
                asciiWord = asciiWord.replacingOccurrences(of: "đ", with: "d")
                                     .replacingOccurrences(of: "Đ", with: "D")
                if !asciiWord.hasPrefix(pattern) { continue }
            }
            
            result.append(word)
            if result.count >= Constants.TOP_K { break }
        }

        return result
    }

    private static func loadJSON(name: String) -> Any? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONSerialization.jsonObject(with: data, options: [])
    }
}
