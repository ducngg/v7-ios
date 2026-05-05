//
//  CacheManager.swift
//  v7Keyboard
//
//  Created by Duc on 09/09/2025.
//

import Foundation

struct CacheManager {
    // MARK: - File Names
    static let biasVectorFileName = "BiasVectorWeight.json"
    static let stateFileName = "State.json"

    // MARK: - URLs
    private static var biasVectorFileURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent(biasVectorFileName)
    }

    private static var stateFileURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent(stateFileName)
    }

    // MARK: - Bias Vector Cache (formerly keyboard cache)
    static func saveBiasVectorWeights(_ values: [Float]) {
        guard let url = biasVectorFileURL else { return }
        do {
            let data = try JSONEncoder().encode(values)
            try data.write(to: url, options: [.atomic])
        } catch {
            print("❌ Failed to save bias vector weights:", error)
        }
    }

    static func loadBiasVectorWeights() -> [Float]? {
        guard let url = biasVectorFileURL,
              FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([Float].self, from: data)
        } catch {
            print("⚠️ Failed to decode bias vector weights:", error)
            return nil
        }
    }

    static func clearBiasVectorWeights() {
        guard let url = biasVectorFileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - UI Code State
    private struct StateModel: Codable {
        let uiCodeState: String
    }

    static func saveUICodeState(_ state: Int) {
        guard let url = stateFileURL else { return }
        do {
            let model = StateModel(uiCodeState: String(state)) // Int -> String
            let data = try JSONEncoder().encode(model)
            try data.write(to: url, options: [.atomic])
        } catch {
            print("❌ Failed to save UI code state:", error)
        }
    }

    static func loadUICodeState() -> Int {
        guard let url = stateFileURL,
              FileManager.default.fileExists(atPath: url.path) else {
            print("⚠️ State file not found")
            return 0
        }
        do {
            let data = try Data(contentsOf: url)
            let jsonString = String(data: data, encoding: .utf8)
            print("📄 Raw state JSON:", jsonString ?? "nil")

            let model = try JSONDecoder().decode(StateModel.self, from: data)
            print("✅ Loaded uiCodeState =", model.uiCodeState)
            return Int(model.uiCodeState) ?? 0
        } catch {
            print("❌ Failed to decode UI code state:", error)
            return 0
        }
    }

    static func clearUICodeState() {
        guard let url = stateFileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
