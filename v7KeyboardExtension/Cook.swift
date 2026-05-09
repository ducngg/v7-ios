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
typealias PredictionResult = (candidates: [Int], scores: [Float])
class NGramDatabase {
    private var db: OpaquePointer?
    
    // 🔥 The Cache
    private var lastQueryKey: String = ""
    private var cachedResults: [NGramEntryWithTokens] = []

    init() {
        guard let path = Bundle.main.path(forResource: Constants.NGRAM_PATH, ofType: "sqlite") else {
            print("Database file not found")
            return
        }

        if sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            print("Error opening database")
        }

        sqlite3_exec(db, "PRAGMA cache_size = -64;", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA temp_store = FILE;", nil, nil, nil)
    }

    func queryWithTokens(key: String) -> [NGramEntryWithTokens] {
        // 1. Check if we already have this key in the cache
        if key == lastQueryKey {
            return cachedResults
        }
        // 2. Query
        var statement: OpaquePointer?
        let query = """
        SELECT text, score, tokens
        FROM ngrams
        WHERE key = ?
        ORDER BY score DESC
        LIMIT \(Constants.NGRAM_LIMIT_QUERY)
        """
        var results: [NGramEntryWithTokens] = []

        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (key as NSString).utf8String, -1, nil)
            
            while sqlite3_step(statement) == SQLITE_ROW {
                let text = String(cString: sqlite3_column_text(statement, 0))
                let score = Int(sqlite3_column_int(statement, 1))
                
                var tokenArray: [Int] = []
                if let blob = sqlite3_column_blob(statement, 2) {
                    let blobSize = Int(sqlite3_column_bytes(statement, 2))
                    let count = blobSize / MemoryLayout<UInt16>.size
                    let typedPointer = blob.bindMemory(to: UInt16.self, capacity: count)
                    let buffer = UnsafeBufferPointer(start: typedPointer, count: count)
                    tokenArray = buffer.map { Int($0) }
                }

                results.append((text: text, score: score, tokens: tokenArray))
            }
        }
        
        sqlite3_finalize(statement)

        // 3. Save to cache for next time
        self.lastQueryKey = key
        self.cachedResults = results
        
        return results
    }

    // Call this if the keyboard is dismissed or memory is low
    func clearCache() {
        lastQueryKey = ""
        cachedResults = []
    }

    deinit {
        sqlite3_close(db)
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
    ) -> PredictionResult? {
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

            // 1. Get sorted IDs (Candidates)
            // Convert [Int32] to [Int]
            let candidates = output.ranked_desc_token_idsShapedArray.scalars.map { Int($0) }
            
            // 2. Get the corresponding scores (Probabilities)
            // Note: probsArray[scalarAt:] is fast, but we map it into a clean [Float] array
            let probsArray = output.final_probsShapedArray
            let scores = candidates.map { id in
                Float(probsArray[scalarAt: id])
            }

            return (candidates: candidates, scores: scores)

        } catch {
            keyboardLogger.error("Prediction error: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Bias Update
    func updateBias(with phrase: String) {
        guard let tokenizer = self.tokenizer else {
            keyboardLogger.debug("❌ tokenizer is nil")
            return
        }

        guard let biasVectorManager = self.biasVectorManager else {
            keyboardLogger.debug("❌ biasVectorManager is nil")
            return
        }

        // Split by whitespace/newlines
        let words = phrase
            .lowercased()
            .split(whereSeparator: \.isWhitespace)

        var updatedCount = 0

        for wordSubstr in words {
            let word = String(wordSubstr)

            guard let index = tokenizer.enumDict[word] else {
                keyboardLogger.debug("⚠️ Token not found for '\(word)'")
                continue
            }

            biasVectorManager.updateBiasVector(at: index)
            updatedCount += 1

            keyboardLogger.debug("✅ Updated bias for '\(word)' at index \(index)")
        }

        // Save once
        if updatedCount > 0 {
            CacheManager.saveBiasVectorWeights(
                biasVectorManager.biasVector
            )

            keyboardLogger.debug("💾 Saved bias vector (\(updatedCount) updates)")
        }
    }
    
    private func buildKey(from signals: [String]) -> String {
        let chars: [Character] = signals.compactMap { part in
            guard let first = part.first else { return nil }
            return tokenizer!.normalizeChar(first)
        }
        return String(chars)
    }
    
    private func sortNgramCandidates(
        candidates: [NGramEntryWithTokens],
        predictions: PredictionResult
    ) -> [NGramEntryWithTokens] {

        // O(1) token score lookup
        var scoreMap: [Int: Float] = [:]
        scoreMap.reserveCapacity(predictions.candidates.count)

        for (index, id) in predictions.candidates.enumerated() {
            scoreMap[id] = predictions.scores[index]
        }

        // Precompute summed score once
        let scoredCandidates = candidates.map { candidate in
            let predictionScore = candidate.tokens.reduce(Float(0)) {
                $0 + (scoreMap[$1] ?? 0)
            }

            return (
                candidate: candidate,
                predictionScore: predictionScore
            )
        }

        // Sort cached scores
        return scoredCandidates
            .sorted { a, b in

                if a.predictionScore == b.predictionScore {
                    return a.candidate.score > b.candidate.score
                }

                return a.predictionScore > b.predictionScore
            }
            .map(\.candidate)
    }
    
    func cookSuggestions(
        signals: String,
        predictions: PredictionResult,
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

        // 2. 🔥 Query SQLite N-Grams
        let lowerSignals = signals.lowercased()
        let tornSignals = tokenizer?.signalTearer(signals: lowerSignals) ?? []
        let key = buildKey(from: tornSignals)

        var ngramCandidates = ngramDB.queryWithTokens(key: key)

        // NEW: Sort candidates by LLM token probability before matching
        ngramCandidates = sortNgramCandidates(candidates: ngramCandidates, predictions: predictions)

        // Apply matching with Early Stopping
        var validNgrams: [String] = []
        for candidate in ngramCandidates {
            if validNgrams.count >= Constants.NGRAM_TOP_K { break }
            
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
