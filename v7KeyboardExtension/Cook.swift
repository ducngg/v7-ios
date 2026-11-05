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

    func queryWithTokens(
        key: String,
        limit: Int = Constants.NGRAM_LIMIT_QUERY
    ) -> [NGramEntryWithTokens] {
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
        LIMIT \(limit)
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

private struct LLMCacheKey: Hashable {
    let input: [Int32]
    let biasVector: [Float]
    let alpha: Float
    let temperature: Float
}

private var llmCache: [LLMCacheKey: PredictionResult] = [:]
private var llmCacheOrder: [LLMCacheKey] = []

private let llmCacheLimit = 32

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

        // MARK: - Cache lookup

        let inputTokens: [Int32] = (0..<input.count).map {
            input[$0].int32Value
        }

        let key = LLMCacheKey(
            input: inputTokens,
            biasVector: biasVector,
            alpha: alpha,
            temperature: temperature
        )

        if let cached = llmCache[key] {
            // Move to MRU
            if let index = llmCacheOrder.firstIndex(of: key) {
                llmCacheOrder.remove(at: index)
            }
            llmCacheOrder.append(key)
            cookLogger.debug("CACHE HIT!")

            return cached
        }

        // MARK: - LLM inference

        do {
            guard
                let biasArray = makeMLMultiArray(from: biasVector),
                let alphaArray = makeMLMultiArray(from: alpha),
                let temperatureArray = makeMLMultiArray(from: temperature)
            else {
                return nil
            }

            let output = try model.prediction(
                input_token_ids: input,
                bias_vector: biasArray,
                alpha: alphaArray,
                temperature: temperatureArray
            )

            // 1. Get sorted IDs
            let candidates = output
                .ranked_desc_token_idsShapedArray
                .scalars
                .map { Int($0) }

            // 2. Get corresponding probabilities
            let probsArray = output.final_probsShapedArray

            let scores = candidates.map { id in
                Float(probsArray[scalarAt: id])
            }

            let result: PredictionResult = (
                candidates: candidates,
                scores: scores
            )

            // MARK: - Insert into LRU

            llmCache[key] = result
            llmCacheOrder.append(key)

            // Evict oldest
            if llmCacheOrder.count > llmCacheLimit {
                let oldest = llmCacheOrder.removeFirst()
                llmCache.removeValue(forKey: oldest)
            }

            return result

        } catch {
            keyboardLogger.error(
                "Prediction error: \(error.localizedDescription)"
            )
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

        //------------------------------------------
        // LLM lookup table
        //------------------------------------------

        var tokenProb: [Int: Float] = [:]
        tokenProb.reserveCapacity(predictions.candidates.count)

        for (i, id) in predictions.candidates.enumerated() {
            tokenProb[id] = predictions.scores[i]
        }

        //------------------------------------------
        // Build P(ngram)
        //------------------------------------------

        let invTemp = 1.0 / Constants.FUSION_NGRAM_COUNT_TEMP

        var softenedCounts = [Float]()
        softenedCounts.reserveCapacity(candidates.count)

        var total: Float = 0

        for candidate in candidates {
            let value = pow(Float(candidate.score), invTemp)
            softenedCounts.append(value)
            total += value
        }

        //------------------------------------------
        // Score candidates
        //------------------------------------------

        let lnBase = log(Constants.FUSION_TOKEN_PROB_LOGBASE)

        let scored = zip(candidates, softenedCounts).map { candidate, softenedCount in

            //-----------------------------
            // LLM score
            //-----------------------------

            let llmLogProb =
                candidate.tokens.reduce(Float(0)) { partial, token in

                    let p = max(tokenProb[token] ?? Constants.FUSION_TOKEN_PROB_EPSILON,
                                Constants.FUSION_TOKEN_PROB_EPSILON)

                    return partial + log(p) / lnBase
                } / Float(candidate.tokens.count)

            //-----------------------------
            // Ngram probability
            //-----------------------------

            let pNgram = max(
                softenedCount / total,
                Constants.FUSION_TOKEN_PROB_EPSILON
            )

            let ngramLogProb = log(pNgram)

            //-----------------------------
            // Final
            //-----------------------------

            let finalScore =
                Constants.FUSION_LLM_WEIGHT   * llmLogProb
                + Constants.FUSION_NGRAM_WEIGHT * ngramLogProb

            return (
                candidate: candidate,
                score: finalScore
            )
        }

        return scored
            .sorted { $0.score > $1.score }
            .map(\.candidate)
    }
    
//    func cookSuggestions(
//        segments: [String],
//        predictions: PredictionResult,
//        toneMark: String,
//        extraSuggestion: Int,
//        ngram_top_k: Int = Constants.NGRAM_TOP_K,
//        
//        // Initial context
//        input: MLMultiArray,
//        biasVector: [Float],
//        alpha: Float,
//        temperature: Float
//    ) -> [String] {
//
//        let segments = segments.map { $0.lowercased() }
//
//        // 1. Get filtered results from LLM predictions
//        var outs: [String] = []
//
//        // Zero when no signal, >= 2 for multi
//        if segments.count <= 1 {
//            let effectiveSignal = segments.first ?? ""
//            outs = tokenizer?.filter(
//                pattern: effectiveSignal,
//                predictions: predictions,
//                toneMark: toneMark,
//                extraSuggestion: extraSuggestion,
//                activateForceStop: true,
//            ) ?? []
//        }
//
//        outs = outs.filter { ![",", "."].contains($0) }
//
//        // 2. Query SQLite N-Grams
//        let key = buildKey(from: segments)
//
//        var ngramCandidates = ngramDB.queryWithTokens(key: key)
//
//        // Sort candidates by LLM token probability
//        ngramCandidates = sortNgramCandidates(
//            candidates: ngramCandidates,
//            predictions: predictions
//        )
//
//        for candidate in ngramCandidates {
//            if outs.count >= ngram_top_k { break }
//
//            if tokenizer!.isMatchNgram(
//                tornSignals: segments,
//                ngram: candidate.text,
//                tokens: candidate.tokens,
//                lastToneMark: toneMark,
//            ) {
//                outs.append(candidate.text)
//            }
//        }
//
//        return outs
//    }
    func cookSuggestions(
        segments: [String],
        predictions: PredictionResult,
        toneMark: String,
        extraSuggestion: Int,
        ngram_top_k: Int = Constants.NGRAM_TOP_K,
        
        // Initial context
        input: MLMultiArray,
        biasVector: [Float],
        alpha: Float,
        temperature: Float,
        
        fallback: Bool = true,
        master: Bool = true,
    ) -> [String] {
        
        if segments.contains(where: { $0.contains { "fjwz".contains($0) } }) {
            return []
        }
        
        if segments.count > 16 {
            return []
        }

        let segments = segments.map { $0.lowercased() }

        // MARK: - 1. LLM suggestions for <= 1 segment
        var toks: [String] = []
        var ngrams: [String] = []

        if segments.count <= 1 || master {
            let effectiveSignal = segments.first ?? ""

            toks = tokenizer?.filter(
                pattern: effectiveSignal,
                predictions: predictions,
                toneMark: toneMark,
                extraSuggestion: extraSuggestion,
                activateForceStop: true
            ) ?? []
            toks = toks.filter { ![",", "."].contains($0) }
            
            if segments.count <= 1 {
                return toks
            }
        }

        // MARK: - 2. Exact N-Gram lookup
        if segments.count <= 4 {
            let key = buildKey(from: segments)
            var ngramCandidates = ngramDB.queryWithTokens(
                key: key
            )
            
            ngramCandidates = sortNgramCandidates(
                candidates: ngramCandidates,
                predictions: predictions
            )
            
            for candidate in ngramCandidates {
                if ngrams.count >= ngram_top_k {
                    break
                }
                
                if tokenizer!.isMatchNgram(
                    tornSignals: segments,
                    ngram: candidate.text,
                    tokens: candidate.tokens,
                    lastToneMark: toneMark
                ) {
                    ngrams.append(candidate.text)
                }
            }
        }

        // If we found suggestions normally, we're done.
        if !ngrams.isEmpty {
            if master {
                return Array(ngrams.prefix(4)) + Array(toks)
            }
            return Array(ngrams.prefix(ngram_top_k))
        }

        // MARK: - 3. Fallback section for unmatched (where no return above) (covers >4 segments)
        guard fallback else {
            // This is when no sub-ngram for sub-segments -> Recursion logic automatically break the sub-segments more as below
            return []
        }
        
        // Try prefixes:
        // segments[0..<1]
        // segments[0..<2]
        // ...
        // segments[0..<s-1]
        for prefixLength in stride(from: segments.count - 1, through: 1, by: -1) {
            let prefixSegments = Array(segments.prefix(prefixLength))
            let latterSegments = Array(segments.dropFirst(prefixLength))

            cookLogger.debug(
                "NO NGRAM LEN \(segments.count) -> SPLIT [\(prefixSegments.joined(separator: ", "), privacy: .public)] & [\(latterSegments.joined(separator: ", "), privacy: .public)]"
            )
            
            let prefixOuts = cookSuggestions(
                segments: prefixSegments,
                predictions: predictions,
                toneMark: "",
                extraSuggestion: extraSuggestion,
                ngram_top_k: master ? 3 : 2,
                input: input,
                biasVector: biasVector,
                alpha: alpha,
                temperature: temperature,
                fallback: false, // Prevent recursion at this
                master: false,
            )

            guard let prefixSuggestion = prefixOuts.first else {
                continue
            }

            // MARK: - 4. Add prefix suggestion to LLM context
            let newInput = tokenizer!.concat_tokens(
                input,
                prefixSuggestion
            )

            guard let newPredictions = llm_predict(
                input: newInput,
                biasVector: biasVector,
                alpha: alpha,
                temperature: temperature
            ) else {
                continue
            }

            let finalOuts = cookSuggestions(
                segments: latterSegments,
                predictions: newPredictions,
                toneMark: toneMark,
                extraSuggestion: extraSuggestion,
                ngram_top_k: 4,
                input: newInput,
                biasVector: biasVector,
                alpha: alpha,
                temperature: temperature,
                master: false,
            )

            if !finalOuts.isEmpty {
                let combinedOuts = finalOuts.prefix(1).map { latterOut in
                    prefixSuggestion + " " + latterOut
                }

                if master {
                    return Array(combinedOuts.prefix(2)) + Array(prefixOuts.prefix(4)) + Array(toks.prefix(16))
                }

                return combinedOuts
            }
        }

        return []
    }
}
