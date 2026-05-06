//
//  V7GPTTokenizer.swift
//  v7Keyboard
//
//  Created by Duc on 22/06/2025.
//

import Foundation
import CoreML

class GPTTokenizer {
    let enumDict: [String: Int]
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
    let specials: String
    let numbers: String
    private let allowRegex: NSRegularExpression
    private let specialsRegex: NSRegularExpression
    
    // 🔹 Prefix caches
    var cachedPatterns: [String: [Int]] = [:]

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
        self.numbers = "0123456789"
        self.specials = ".,!?;:-_()[]{}'\"“”‘’/\\\\@#$%^&*+=<>~|`… "
        
        let baseVocab = enumData
            .filter { (_, id) in (1...Constants.BASE_VIET_VOCAB_SIZE).contains(id) }
            .map { (token, _) in token }
        let charset = Set(baseVocab.joined() + specials)
        let escaped = charset
            .map { NSRegularExpression.escapedPattern(for: String($0)) }
            .joined()
        let allowPattern = "[^ \(escaped)]"

        self.allowRegex = try! NSRegularExpression(pattern: allowPattern, options: [])

        let specialsPattern = "([\(NSRegularExpression.escapedPattern(for: specials))])"
        self.specialsRegex = try! NSRegularExpression(pattern: specialsPattern, options: [])
        
        // 🔹 Load cached patterns (a, b, …, aa, ab, …, zz)
        let fm = FileManager.default
        if let resourceURL = Bundle.main.resourceURL {
            if let files = try? fm.contentsOfDirectory(at: resourceURL, includingPropertiesForKeys: nil) {
                for file in files where file.pathExtension == "json" {
                    let key = file.deletingPathExtension().lastPathComponent.lowercased()
                    // ✅ Only add if key length is 1 or 2
                    if key.count == 1 || key.count == 2 {
                        if let arr = GPTTokenizer.loadJSON(url: file) as? [Int] {
                            cachedPatterns[key] = arr
                        }
                    }
                }
            }
        }

        keyboardLogger.debug("Done init tokenizer")
    }
    
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
    
    private func isVowel(_ ch: Character) -> Bool {
        return "aeiouy".contains(ch.lowercased())
    }

    private func isMatch(
        effectivePattern: String,
        word: String,
        idx: Int,
        toneMark: String
    ) -> Bool {
        // 🔹 Tone check
        if !toneMark.isEmpty {
            if idx < 1 || idx > Constants.BASE_VIET_VOCAB_SIZE { return false }
            if renumToneMark[idx] != toneMark { return false }
        }
        
        var pattern = effectivePattern
        
        // 🔹 Special rule: double ending vowel
        if pattern.count >= 2 {
            let chars = Array(pattern)
            let last = chars[chars.count - 1]
            let secondLast = chars[chars.count - 2]

            if last == secondLast && isVowel(last) {
                // Enforce shorter word length
                if word.count != pattern.count - 1 {
                    return false
                }
                // Remove last char from pattern
                pattern = String(chars.dropLast())
            }
        }

        // 🔹 Pattern check
        if !effectivePattern.isEmpty {
            // If remove this, effectivePattern="thanh" will still match word="tha"
            if word.count < pattern.count {
                return false
            }
            
            let prefixChars = pattern.map { normalizeChar($0) }
            for (i, ch) in word.enumerated() {
                if i >= prefixChars.count { break }
                if normalizeChar(ch) != prefixChars[i] {
                    return false
                }
            }
        }

        return true
    }

    func filter(
        pattern: String,
        predictions: [(id: Int, score: Float)],
        toneMark: String,
        extraSuggestion: Int
    ) -> [String] {
        let predictionIds = predictions.map { $0.id }
        var result: [String] = []
        var currentPattern = pattern
        
        if pattern.count > 6 {
            return result
        }
        // rule 2: reject if contains digits or forbidden symbols
        let invalidCharacters = CharacterSet(charactersIn: self.numbers + self.specials)
        let patternSet = CharacterSet(charactersIn: pattern)
        if !pattern.isEmpty && patternSet.isSubset(of: invalidCharacters) {
            return result
        }

        // Remove characters on the left that are in specials
        // Patterns like '@x' will still predict 'xin', and the front-end can still choose without delete '@'
        if let firstNonSpecialIndex = currentPattern.firstIndex(where: { !specials.contains($0) }) {
            currentPattern = String(currentPattern[firstNonSpecialIndex...])
        }
        
        var effectiveToneMark = toneMark
        var effectivePattern = currentPattern
        if effectiveToneMark.isEmpty, effectivePattern.count > 1 {
            let toneMap: [Character: String] = [
                "s": "◌́",
                "z": "◌",
                "f": "◌̀",
                "j": "◌̣",
                "x": "◌̃",
                "r": "◌̉"
            ]

            var index = effectivePattern.index(after: effectivePattern.startIndex)

            while index < effectivePattern.endIndex {
                let char = effectivePattern[index]

                if let mappedTone = toneMap[char] {
                    // 🔥 override toneMark
                    effectiveToneMark = mappedTone

                    // 🔥 remove that char from pattern
                    effectivePattern.remove(at: index)

                    break
                }

                index = effectivePattern.index(after: index)
            }
        }
        
        // 🔹 Adjust special consonants
        if !effectiveToneMark.isEmpty, !effectivePattern.isEmpty {
            let firstChar = effectivePattern.first!.lowercased()
            let rest = String(effectivePattern.dropFirst())
            switch firstChar {
                case "j": effectivePattern = "tr" + rest // For future telex usage j+r - tr+r
                case "z": effectivePattern = "gi" + rest
                case "f": effectivePattern = "ph" + rest
                default: break
            }
        }
        effectivePattern = effectivePattern.lowercased()

//        // 🔹 Pre-check for punctuation leading prediction
//        if let first = predictions.first, first == 17818 || first == 17819 {
//            for modal in Constants.modalParticles {
//                if isMatch(word: modal, idx: -1, effectivePattern: effectivePattern, toneMark: toneMark) {
//                    result.append(modal)
//                    if result.count >= Constants.TOP_K { return result }
//                }
//            }
//        }

        // 🔹 Normal prediction loop
        var iterate = 0
        let max_iterate = !effectiveToneMark.isEmpty ? Constants.MAX_FILTER_ITERATE_VIET : Constants.MAX_FILTER_ITERATE
        for idx in predictionIds {
            iterate += 1
            if iterate > max_iterate { break }
            guard idx < renumList.count else { continue }
            guard let word = renumList[idx] else { continue }
            if isMatch(effectivePattern: effectivePattern, word: word, idx: idx, toneMark: effectiveToneMark) {
                result.append(word)
                if result.count >= Constants.TOP_K + extraSuggestion { break }
            }
        }

        return result
    }
    
    /// Validates if an N-Gram entry matches the current sequence of signals typed by the user.
    /// - Parameters:
    ///   - tornSignals: The signals extracted from the pattern (e.g., ["h", "p"] from "h p")
    ///   - ngram: The full text from the SQLite entry (e.g., "học phí")
    ///   - tokens: The token IDs for that phrase (e.g., [120, 450])
    /// - Returns: Bool indicating if the N-Gram is a valid suggestion for the input
    func isMatchNgram(
        tornSignals: [String],
        ngram: String,
        tokens: [Int]
    ) -> Bool {
        // 1. Split the N-Gram text into individual words
        // We use lowercased to match your tokenizer's normalization
        let ngramWords = ngram.lowercased().split(separator: " ").map(String.init)
        
        // 2. Safety check: If the user typed more parts than the N-Gram has words, it's not a match.
        // e.g., pattern "a b c" cannot match N-Gram "apple banana"
        guard tornSignals.count <= ngramWords.count else {
            return false
        }
        
        // 3. Validate each signal against the corresponding word in the N-Gram
        for i in 0..<tornSignals.count {
            let signal = tornSignals[i]
            let word = ngramWords[i]
            
            // We call your existing isMatch logic.
            // We pass empty toneMark as requested.
            // idx is usually used for position-based logic in tokenizers.
            if !isMatch(effectivePattern: signal, word: word, idx: i, toneMark: "") {
                return false
            }
        }
        
        // If all signals passed the check, this N-Gram is a valid match
        return true
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
    
    private static func loadJSON(name: String) -> Any? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONSerialization.jsonObject(with: data, options: [])
    }
    private static func loadJSON(url: URL) -> Any? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: [])
    }
    func normalizeChar(_ char: Character) -> Character {
        switch char {
        case "đ":
            return Constants.haveDD ? "đ" : "d"
        case "ă", "ắ", "ằ", "ẳ", "ẵ", "ặ", "â", "ấ", "ầ", "ẩ", "ẫ", "ậ", "á", "à", "ả", "ã", "ạ":
            return "a"
        case "ê", "ế", "ề", "ể", "ễ", "ệ", "é", "è", "ẻ", "ẽ", "ẹ":
            return "e"
        case "ô", "ố", "ồ", "ổ", "ỗ", "ộ", "ơ", "ớ", "ờ", "ở", "ỡ", "ợ", "ó", "ò", "ỏ", "õ", "ọ":
            return "o"
        case "ư", "ứ", "ừ", "ử", "ữ", "ự", "ú", "ù", "ủ", "ũ", "ụ":
            return "u"
        case "í", "ì", "ỉ", "ĩ", "ị":
            return "i"
        case "ý", "ỳ", "ỷ", "ỹ", "ỵ":
            return "y"
        default:
            return char
        }
    }
    
    func signalTearer(signals: String) -> [String] {
        var parts: [String] = []
        let chars = Array(signals)
        var pos = 0
        let n = chars.count

        while pos < n {
            var lastValidEnd: Int? = nil

            var end = pos + 1
            while end <= n {
                let sub = String(chars[pos..<end])
                let range = NSRange(location: 0, length: sub.utf16.count)

                if let match = caytreRegex.firstMatch(in: sub, options: [], range: range),
                   match.range == range {
                    lastValidEnd = end
                } else if lastValidEnd != nil {
                    break
                }

                end += 1
            }

            if let validEnd = lastValidEnd {
                parts.append(String(chars[pos..<validEnd]))
                pos = validEnd
            } else {
                parts.append(String(chars[pos]))
                pos += 1
            }
        }

        return parts
    }
}
