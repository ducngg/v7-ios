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

class GPTModel {
    private let model: MLModel

    init?(modelName: String) {
        guard let modelURL = Bundle.main.url(forResource: modelName, withExtension: "mlpackage") else {
            keyboardLogger.error("❌ Could not find model resource \(modelName).mlmodelc in bundle")
            return nil
        }

        do {
            let model = try MLModel(contentsOf: modelURL)
            self.model = model
        } catch {
            keyboardLogger.error("❌ Failed to load MLModel: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }


    func predict(input: MLMultiArray) -> [Int] {
        do {
            let output = try model.prediction(from: GPTModelInput(inputTokenIds: input))
            guard let array = output.featureValue(for: "ranked_desc_token_ids")?.multiArrayValue else {
                return []
            }

            return (0..<array.count).map { array[$0].intValue }

        } catch {
            print("Prediction error: \(error)")
            return []
        }
    }
}
