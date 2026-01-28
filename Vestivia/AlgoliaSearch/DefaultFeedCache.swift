//
//  DefaultFeedCache.swift
//  Exchange
//
//  Created by William Hunsucker on 8/21/25.
//


import Foundation

/// Simple on-disk cache for a "default feed" (first page, no query, no filters).
/// Generic over any Codable hit model (e.g., ListingHit).
final class DefaultFeedCache<T: Codable> {

  struct Payload: Codable {
    let savedAt: TimeInterval
    let hits: [T]
  }

  private let filename: String
  private let ttl: TimeInterval

  /// - Parameters:
  ///   - filename: Cache file name in Caches dir.
  ///   - ttl: Time-to-live in seconds (default: 24h).
  init(filename: String = "defaultFeed.json", ttl: TimeInterval = 24 * 60 * 60) {
    self.filename = filename
    self.ttl = ttl
  }

  // MARK: Paths

  private var fileURL: URL {
    let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    return base.appendingPathComponent(filename)
  }

  // MARK: API

  /// Load cached hits if they exist and are still fresh.
  func load() -> [T]? {
    guard
      let data = try? Data(contentsOf: fileURL),
      let payload = try? JSONDecoder().decode(Payload.self, from: data)
    else { return nil }

    let age = Date().timeIntervalSince1970 - payload.savedAt
    guard age < ttl else { return nil }
    return payload.hits
  }

  /// Save hits.
  func save(_ hits: [T]) {
    let payload = Payload(savedAt: Date().timeIntervalSince1970, hits: hits)
    guard let data = try? JSONEncoder().encode(payload) else { return }
    try? data.write(to: fileURL, options: .atomic)
  }

  /// Remove the cache file.
  func clear() {
    try? FileManager.default.removeItem(at: fileURL)
  }
}