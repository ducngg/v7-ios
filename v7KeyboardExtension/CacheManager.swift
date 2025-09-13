//
//  CacheManager.swift
//  v7Keyboard
//
//  Created by Duc on 09/09/2025.
//  Copyright © 2025 Ethan Sarif-Kattan. All rights reserved.
//

import Foundation

struct CacheManager {
    static let cacheFileName = "keyboardCache.json"

    /// URL in Library/Caches (per-app sandbox)
    private static var cacheFileURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent(cacheFileName)
    }

    static func saveCache(_ values: [Float]) {
        guard let url = cacheFileURL else { return }
        do {
            let data = try JSONEncoder().encode(values)
            try data.write(to: url, options: [.atomic])
        } catch {
            print("❌ Failed to save cache:", error)
        }
    }

    static func loadCache() -> [Float]? {
        guard let url = cacheFileURL,
              FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([Float].self, from: data)
        } catch {
            print("⚠️ Failed to decode cache:", error)
            return nil
        }
    }

    static func clearCache() {
        guard let url = cacheFileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

