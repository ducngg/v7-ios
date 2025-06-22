//
//  GPTModel.swift
//  v7Keyboard
//
//  Created by Duc on 08/05/2025.
//  Copyright © 2025 Ethan Sarif-Kattan. All rights reserved.
//

import Foundation
import CoreML

import UIKit

class GPTModel {
    private let model: MLModel
    private let enumDict: [String: Int]
    private let renumList: [String?]
    private let renumCrtList: [[Any]?]
    private let toneMarks = [
        "◌́": [1, 6],  // Tone ◌́ maps to both 1 and 6
        "◌": [0],     // Tone ◌ maps to 0
        "◌̀": [2],     // Tone ◌̀ maps to 2
        "◌̣": [5, 7],  // Tone ◌̣ maps to both 5 and 7
        "◌̃": [4],     // Tone ◌̃ maps to 4
        "◌̉": [3]      // Tone ◌̉ maps to 3
    ]


    init?(modelName: String) {
        guard let modelURL = Bundle.main.url(forResource: modelName, withExtension: "mlmodelc"),
              let model = try? MLModel(contentsOf: modelURL),
              let enumData = GPTModel.loadJSON(name: "enum") as? [String: Int],
              let renumData = GPTModel.loadJSON(name: "renum") as? [Any],
              let renumCrtData = GPTModel.loadJSON(name: "renum_crt") as? [Any] else {
            return nil
        }

        self.model = model
        self.enumDict = enumData
        self.renumList = renumData as? [String?] ?? []
        self.renumCrtList = renumCrtData as? [[Any]?] ?? []
    }

    func predict(raw: String, context: String) -> [String] {
        // Step 1: Tokenize context
        let words = context.split(separator: " ").compactMap { enumDict[String($0)] }
        var inputTokens = Array(words.suffix(Constants.MAX_SEQUENCE_LEN))

        if inputTokens.count < Constants.MAX_SEQUENCE_LEN {
            let padCount = Constants.MAX_SEQUENCE_LEN - inputTokens.count
            inputTokens = Array(repeating: 0, count: padCount) + inputTokens
        }

        guard let inputMultiArray = try? MLMultiArray(shape: [NSNumber(value: Constants.MAX_SEQUENCE_LEN)], dataType: .int32) else {
            return []
        }
        
        for i in 0..<Constants.MAX_SEQUENCE_LEN {
            inputMultiArray[i] = NSNumber(value: inputTokens[i])
        }

        // Step 2: Model prediction
        var outputArray: MLMultiArray?

        do {
            let output = try model.prediction(from: GPTModelInput(inputTokenIds: inputMultiArray))
            outputArray = output.featureValue(for: "ranked_desc_token_ids")?.multiArrayValue
        } catch {
            proxy.insertText("Prediction error: \(error.localizedDescription)")
            return []
        }
        
        guard let array = outputArray else {
            proxy.insertText("Failed to get output array.")
            return []
        }
        
        let allRankedIndices = (0..<array.count).map { array[$0].intValue }

        let filtered = accept(raw: raw, outputTokens: allRankedIndices)

        let predictions = filtered.prefix(50).compactMap { idx -> String? in
            guard idx < renumList.count else { return nil }
            return renumList[idx]
        }
        
        return predictions
    }

    private func accept(raw: String, outputTokens: [Int]) -> [Int] {
        // Extract initial consonant and tone from raw
        let (toBeCheckedConsonant, toBeCheckedRhyme, toBeCheckedTones) = extractInitialConsonantRhymeTone(from: raw)
        
//        proxy.insertText("[\(toBeCheckedConsonant)][\(toBeCheckedRhyme)][\(toBeCheckedTones)]")
        
        // Filter renumCrtList based on initial consonant and tone
        let filteredIndices = outputTokens.filter { tokenIndex in
            guard tokenIndex < renumCrtList.count else { return false }
            let entry = renumCrtList[tokenIndex] ?? []
                                
            // Check if entry is a valid entry with 3 elements: [initial consonant, rhyme, tone]
            if entry.count == 3,
                let entryConsonant = entry[0] as? String,
                let entryRhyme = entry[1] as? String,
                let entryTone = entry[2] as? Int,
                let entryWord = renumList[tokenIndex] {
                
                return match(
                    toBeCheckedConsonant: toBeCheckedConsonant,
                    toBeCheckedRhyme: toBeCheckedRhyme,
                    toBeCheckedTones: toBeCheckedTones,
                    entryWord: entryWord,
                    entryConsonant: entryConsonant,
                    entryRhyme: entryRhyme,
                    entryTone: entryTone
                )
            }
            return false
        }
        
        return filteredIndices
    }
    
    private func normalizeChar(_ char: Character) -> Character {
        switch char {
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

    
    private func match(
        toBeCheckedConsonant: String,
        toBeCheckedRhyme: String,
        toBeCheckedTones: [Int],
        entryWord: String,
        entryConsonant: String,
        entryRhyme: String,
        entryTone: Int
    ) -> Bool {
        // Tone check
        guard isToneMatch(toBeCheckedTones, entryTone) else {
            return false
        }

        if toBeCheckedConsonant == "q" {
            // Q-specific consonant check
            guard entryWord.first == "q" else { return false }

            // Q-specific rhyme transformation
            let transformedRhyme = toBeCheckedRhyme
                .replacingOccurrences(of: "ua", with: "oa")
                .replacingOccurrences(of: "uă", with: "oă")
                .replacingOccurrences(of: "ue", with: "oe")

            // Rhyme character-by-character comparison
            let minLen = min(transformedRhyme.count, entryRhyme.count)
            for i in 0..<minLen {
                let rawChar = transformedRhyme[transformedRhyme.index(transformedRhyme.startIndex, offsetBy: i)]
                let entryChar = entryRhyme[entryRhyme.index(entryRhyme.startIndex, offsetBy: i)]
                if rawChar != normalizeChar(entryChar) {
                    return false
                }
            }
        } else {
            // Consonant checks
            if toBeCheckedConsonant == "c" && entryWord.first != "c" { return false }
            if toBeCheckedConsonant == "k" && entryWord.first != "k" { return false }
            if toBeCheckedConsonant == "f" && !entryWord.hasPrefix("ph") { return false }
            if toBeCheckedConsonant.isEmpty && entryConsonant != "0" { return false }
            
            if !(
                (toBeCheckedConsonant == "c" && entryConsonant == "k")
                ||
                (toBeCheckedConsonant.isEmpty && entryConsonant == "0")
                ||
                (toBeCheckedConsonant == "f" && entryWord.hasPrefix("ph"))
                ||
                (toBeCheckedConsonant == entryConsonant)
            ) {return false}

            // Rhyme check
            var startIndex = 0
            if toBeCheckedConsonant.isEmpty {
                guard let rawFirst = toBeCheckedRhyme.first,
                      let wordFirst = entryWord.first,
                      rawFirst == normalizeChar(wordFirst) else {
                    return false
                }
                startIndex = 1
            }

            let minLen = min(toBeCheckedRhyme.count, entryRhyme.count)
            for i in startIndex..<minLen {
                let rawChar = toBeCheckedRhyme[toBeCheckedRhyme.index(toBeCheckedRhyme.startIndex, offsetBy: i)]
                let entryChar = entryRhyme[entryRhyme.index(entryRhyme.startIndex, offsetBy: i)]
                if rawChar != normalizeChar(entryChar) {
                    return false
                }
            }
        }

        return true
    }

        


    private func extractInitialConsonantRhymeTone(from raw: String) -> (String, String, [Int]) {
        // Extract initial consonant
        let initial = extractInitialConsonant(from: raw)

        // Remove initial consonant from raw to process the rest
        let remaining = raw.dropFirst(initial.count)

        // Identify tone character (if any) at the end
        let lastChar = String(remaining.last ?? " ")
        let tones = toneMarks[lastChar] ?? []

        // Remove tone character from remaining to get the rhyme
        let rhyme = tones.isEmpty ? String(remaining) : String(remaining.dropLast())
    
        return (initial, rhyme, tones)
    }


    // Extract the initial consonant or consonant cluster (first one or two characters)
    private func extractInitialConsonant(from raw: String) -> String {
        let consonants = "bcdđfghklmnpqrstvxz" // Add all possible consonants
        var cluster = ""
        
        for (_, char) in raw.enumerated() {
            let character = String(char).lowercased()
            if consonants.contains(character) {
                cluster += character
            } else {
                break
            }
            
            // If we already have a consonant cluster (like "nh", "ng"), stop after two
            if cluster.count == 2 { break }
        }
        
        return cluster
    }

    private func isToneMatch(_ rawTones: [Int], _ renumTone: Int) -> Bool {
        return rawTones.contains(renumTone)
    }

    private static func loadJSON(name: String) -> Any? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONSerialization.jsonObject(with: data, options: [])
    }
}

class GPTModelInput: MLFeatureProvider {
    var inputTokenIds: MLMultiArray

    init(inputTokenIds: MLMultiArray) {
        self.inputTokenIds = inputTokenIds
    }

    var featureNames: Set<String> {
        return ["input_token_ids"]
    }

    func featureValue(for featureName: String) -> MLFeatureValue? {
        if featureName == "input_token_ids" {
            return MLFeatureValue(multiArray: inputTokenIds)
        }
        return nil
    }
}
