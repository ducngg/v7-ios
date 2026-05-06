//
//  GPTModel.swift
//  v7Keyboard
//
//  Created by Duc on 09/09/2025.
//

import Foundation
import CoreML

import SQLite3

typealias NGramEntryWithTokens = (text: String, score: Int, tokens: [Int])

class NGramDatabase {
    var db: OpaquePointer?

    init() {
        let path = Bundle.main.path(forResource: "v7ngram-1.0-20260504.234lookup", ofType: "sqlite")!
        if sqlite3_open(path, &db) != SQLITE_OK {
            print("Error opening database")
        }
    }

    func queryWithTokens(key: String) -> [NGramEntryWithTokens] {
        var statement: OpaquePointer?
        let query = "SELECT text, score, tokens FROM ngrams WHERE key = ? ORDER BY score DESC"
        
        var results: [NGramEntryWithTokens] = []

        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (key as NSString).utf8String, -1, nil)
            
            while sqlite3_step(statement) == SQLITE_ROW {
                let text = String(cString: sqlite3_column_text(statement, 0))
                let score = Int(sqlite3_column_int(statement, 1))
                
                // 🔥 Decode the JSON string back to [Int]
                let tokensString = String(cString: sqlite3_column_text(statement, 2))
                if let data = tokensString.data(using: .utf8),
                   let tokenArray = try? JSONDecoder().decode([Int].self, from: data) {
                    results.append((text: text, score: score, tokens: tokenArray))
                }
            }
        }
        sqlite3_finalize(statement)
        return results
    }
}

final class Cooker {

    // MARK: - Core Components
    let tokenizer = GPTTokenizer()
    var biasVectorManager: BiasVectorManager?
    private(set) var LLM: v7gpt_2_2_small_20250909_with_bias_with_final_probs?
    private let ngramDB = NGramDatabase()

    // MARK: - Init
    init() {
        loadLLM()

        let initialVector = CacheManager.loadBiasVectorWeights()
        self.biasVectorManager = BiasVectorManager(initialVector: initialVector)
    }

    // MARK: - Model Loading
    private func loadLLM() {
        autoreleasepool {
            let config = MLModelConfiguration()
//                config.computeUnits = .all
                    config.computeUnits = .cpuAndNeuralEngine   // avoids GPU memory overhead
            //        config.computeUnits = .cpuOnly
//                    config.computeUnits = .cpuAndGPU
//            config.computeUnits = .cpuOnly   // ✅ safest for extensions
            do {
                let t0 = Date()
                LLM = try v7gpt_2_2_small_20250909_with_bias_with_final_probs(configuration: config)
                keyboardLogger.debug("✅ Model loaded in \(Date().timeIntervalSince(t0))s")
            } catch {
                keyboardLogger.error("⚠️ Failed to load model: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - MLMultiArray Helpers

    private func makeMLMultiArray(from array: [Float]) -> MLMultiArray? {
        do {
            let mlArray = try MLMultiArray(shape: [NSNumber(value: array.count)], dataType: .float32)
            for (i, value) in array.enumerated() {
                mlArray[i] = NSNumber(value: value)
            }
            return mlArray
        } catch {
            keyboardLogger.error("❌ MLMultiArray (array) error: \(error.localizedDescription)")
            return nil
        }
    }

    private func makeMLMultiArray(from value: Float) -> MLMultiArray? {
        do {
            let mlArray = try MLMultiArray(shape: [1], dataType: .float32)
            mlArray[0] = NSNumber(value: value)
            return mlArray
        } catch {
            keyboardLogger.error("❌ MLMultiArray (float) error: \(error.localizedDescription)")
            return nil
        }
    }
    
    func llm_predict(
        input: MLMultiArray,
        biasVector: [Float],
        alpha: Float,
        temperature: Float
    ) -> [(id: Int, score: Float)]? {
        guard let model = self.LLM else { return nil }

        do {
            guard let biasArray = makeMLMultiArray(from: biasVector),
                  let alphaArray = makeMLMultiArray(from: alpha),
                  let temperatureArray = makeMLMultiArray(from: temperature) else {
                return nil
            }
            let output = try model.prediction(
                input_token_ids: input,
                bias_vector: biasArray,
                alpha: alphaArray,
                temperature: temperatureArray
            )

            // 1. Convert Int32 scalars to standard Swift Ints
            let sortedIDs = output.ranked_desc_token_idsShapedArray.scalars.map { Int($0) }
            
            // 2. Access the probability ShapedArray
            let probsArray = output.final_probsShapedArray

            // 3. Map IDs to their specific scores
            let rankedWithScores: [(id: Int, score: Float)] = sortedIDs.map { id in
                // Use scalarAt to get the Float directly, avoiding NSNumber
                let score: Float = probsArray[scalarAt: id]
                return (id: id, score: score)
            }

            return rankedWithScores

        } catch {
            keyboardLogger.error("Prediction error: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Bias Update

    func updateBias(with word: String) {
        guard let tokenizer = self.tokenizer else {
            keyboardLogger.debug("❌ tokenizer is nil")
            return
        }
        guard let biasVectorManager = self.biasVectorManager else {
            keyboardLogger.debug("❌ biasVectorManager is nil")
            return
        }

        let lower = word.lowercased()

        guard let index = tokenizer.enumDict[lower] else {
            keyboardLogger.debug("⚠️ Token not found for '\(word)'")
            return
        }

        // Update bias
        biasVectorManager.updateBiasVector(at: index)

        // Persist
        CacheManager.saveBiasVectorWeights(biasVectorManager.biasVector)

        keyboardLogger.debug("✅ Updated bias for '\(word)' at index \(index)")
    }
    
    private func buildKey(from signals: [String]) -> String {
        let chars: [Character] = signals.compactMap { part in
            guard let first = part.first else { return nil }
            return tokenizer!.normalizeChar(first)
        }
        return String(chars)
    }
    
    func cookSuggestions(
        signals: String,
        predictions: [(id: Int, score: Float)],
        toneMark: String,
        extraSuggestion: Int
    ) -> [String] {
        // 1. Get filtered results from LLM predictions (using existing logic)
        var filteredLLM = tokenizer?.filter(
            pattern: signals,
            predictions: predictions,
            toneMark: toneMark,
            extraSuggestion: extraSuggestion
        ) ?? []

        filteredLLM = filteredLLM.filter { ![",", "."].contains($0) }

        // 2. 🔥 Query and Filter SQLite N-Grams
        let lowerSignals = signals.lowercased()
        let tornSignals = tokenizer?.signalTearer(signals: lowerSignals) ?? []
        let key = buildKey(from: tornSignals)

        // Fetch candidates from SQLite
        let ngramCandidates = ngramDB.queryWithTokens(key: key)

        // Apply the custom matching logic with Early Stopping
        var validNgrams: [String] = []
        for candidate in ngramCandidates {
            // Check if we've reached our limit
            if validNgrams.count >= Constants.TOP_K {
                break
            }
            
            // Perform the heavy matching logic only until TOP_K is filled
            if tokenizer!.isMatchNgram(
                tornSignals: tornSignals,
                ngram: candidate.text,
                tokens: candidate.tokens
            ) {
                validNgrams.append(candidate.text)
            }
        }

        // 3. Combine: N-Grams on top for better UX, followed by LLM results
        // We use Set to prevent duplicates if the same word is in both N-Gram and LLM
        var seen = Set<String>()
        var finalResult: [String] = []

        for word in validNgrams {
            if !seen.contains(word) {
                finalResult.append(word)
                seen.insert(word)
            }
        }

        for word in filteredLLM {
            if !seen.contains(word) {
                finalResult.append(word)
                seen.insert(word)
            }
        }

        return finalResult
    }
}
