//
//  BiasVectorManager.swift
//  v7Keyboard
//
//  Created by Duc on 10/09/2025.
//  Copyright © 2025 Ethan Sarif-Kattan. All rights reserved.
//

import Foundation

class BiasVectorManager {
    var biasVector: [Float]

    /// Initialize with an optional vector. If invalid, fall back to uniform.
    init(initialVector: [Float]? = nil) {
        if let vec = initialVector,
           !vec.isEmpty,
           vec.reduce(0, +) > 0 {
            // Normalize provided vector
            let total = vec.reduce(0, +)
            self.biasVector = vec.map { $0 / total }
        } else {
            // Fallback: uniform distribution
            let size = Constants.VOCAB_SIZE
            self.biasVector = Array(repeating: 1.0 / Float(size), count: size)
        }
    }

    /// Increase the value at a given index and renormalize
    func updateBiasVector(at index: Int) {
        guard index >= 0 && index < biasVector.count else { return }

        // Increase target index
        biasVector[index] += Constants.BIAS_INCREMENT_STEP

        // Normalize so sum = 1
        let total = biasVector.reduce(0, +)
        if total > 0 {
            biasVector = biasVector.map { $0 / total }
        }
    }
}
