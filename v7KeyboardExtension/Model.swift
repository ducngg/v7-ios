//
//  GPTModel.swift
//  v7Keyboard
//
//  Created by Duc on 09/09/2025.
//

import CoreML

func makeMLMultiArray(from array: [Float]) -> MLMultiArray? {
    do {
        let mlArray = try MLMultiArray(shape: [NSNumber(value: array.count)], dataType: .float32)
        for (i, value) in array.enumerated() {
            mlArray[i] = NSNumber(value: value)
        }
        return mlArray
    } catch {
        print("❌ Failed to create MLMultiArray:", error)
        return nil
    }
}
func makeMLMultiArray(from value: Float) -> MLMultiArray? {
    do {
        let mlArray = try MLMultiArray(shape: [1], dataType: .float32)
        mlArray[0] = NSNumber(value: value)
        return mlArray
    } catch {
        print("❌ Failed to create MLMultiArray for single float:", error)
        return nil
    }
}

func model_predict(
    model: v7gpt_2_2_small_20250909_with_bias,
    input: MLMultiArray,
    biasVector: [Float],
    alpha: Float,
    temperature: Float,
) -> [Int]? {
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
            temperature: temperatureArray,
        )

        return output.ranked_desc_token_idsShapedArray.scalars.map { Int($0) }
    } catch {
        keyboardLogger.error("Prediction error: \(error.localizedDescription)")
        return nil
    }
}
