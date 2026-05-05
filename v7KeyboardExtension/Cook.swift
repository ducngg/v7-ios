//
//  GPTModel.swift
//  v7Keyboard
//
//  Created by Duc on 09/09/2025.
//

import Foundation
import CoreML

final class Cooker {

    // MARK: - Core Components
    let tokenizer = GPTTokenizer()
    var biasVectorManager: BiasVectorManager?
    private(set) var LLM: v7gpt_2_2_small_20250909_with_bias?

    // MARK: - Init
    init() {
        loadModel()

        let initialVector = CacheManager.loadBiasVectorWeights()
        self.biasVectorManager = BiasVectorManager(initialVector: initialVector)
    }

    // MARK: - Model Loading
    private func loadModel() {
        autoreleasepool {
            let config = MLModelConfiguration()
//                config.computeUnits = .all
                    config.computeUnits = .cpuAndNeuralEngine   // avoids GPU memory overhead
            //        config.computeUnits = .cpuOnly
//                    config.computeUnits = .cpuAndGPU
//            config.computeUnits = .cpuOnly   // ✅ safest for extensions
            do {
                let t0 = Date()
                LLM = try v7gpt_2_2_small_20250909_with_bias(configuration: config)
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
    // MARK: - Model Predict

    func llm_predict(
        input: MLMultiArray,
        biasVector: [Float],
        alpha: Float,
        temperature: Float
    ) -> [Int]? {

        guard let model = self.LLM else {
            keyboardLogger.error("❌ Model not loaded")
            return nil
        }

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

            return output.ranked_desc_token_idsShapedArray.scalars.map { Int($0) }

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
}
