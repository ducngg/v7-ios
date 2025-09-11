//
//  CacheManager.swift
//  v7Keyboard
//
//  Created by Duc on 09/09/2025.
//  Copyright © 2025 Ethan Sarif-Kattan. All rights reserved.
//

import Foundation

struct CacheManager {
    static let appGroupID = "group.com.test.v7keyboard"
    static let cacheFileName = "keyboardCache.json"

    private static var cacheFileURL: URL? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) else {
            return nil
        }
        return containerURL.appendingPathComponent(cacheFileName)
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
}

