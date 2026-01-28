//
//  AlgoliaKeyCache.swift
//  Exchange
//
//  Cleaned for Swift 6 concurrency — single source of truth.
//

import Foundation
@preconcurrency import FirebaseFunctions

// MARK: - Private helper

private struct FetchedKeyFields: Sendable {
    let appId: String
    let key: String
    let exp: TimeInterval
}

// Do not force main-thread; keep this off-main unless the caller requires it
private func fetchSecuredSearchKeyFields() async throws -> FetchedKeyFields {
    // FirebaseFunctions types are not fully Sendable-annotated yet.
    // Using @preconcurrency import avoids Swift 6 sendability errors.
    let functions = Functions.functions(region: "us-central1")
    let callable  = functions.httpsCallable("getSecuredSearchKey")
    let result    = try await callable.call()

    let dict = (result.data as? [String: Any]) ?? [:]
    guard let appId = dict["appId"]     as? String,
          let key   = dict["key"]       as? String,
          let exp   = dict["expiresAt"] as? TimeInterval
    else {
        throw NSError(
            domain: "AlgoliaKeyCache",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Invalid secured key response"]
        )
    }

    return FetchedKeyFields(appId: appId, key: key, exp: exp)
}

// MARK: - Public cache

public actor AlgoliaKeyCache {
    public struct Key {
        public let value: String      // secured search key
        public let appId: String
        public let expiresAt: Date
    }

    private var cached: Key?
    private var inFlight: Task<Key, Error>?

    /// Returns a cached key if still valid, otherwise fetches a new one.
    /// Results are coalesced so only one network call is in-flight.
    public func get(refreshIfExpiringWithin seconds: TimeInterval = 60) async throws -> Key {
        // 1) Serve cache if fresh
        if let c = cached, c.expiresAt.timeIntervalSinceNow > seconds {
            return c
        }

        // 2) Reuse in-flight task if any
        if let t = inFlight {
            return try await t.value
        }

        // 3) Start a new fetch task
        let t = Task<Key, Error> {
            let fields = try await fetchSecuredSearchKeyFields()
            return Key(
                value: fields.key,
                appId: fields.appId,
                expiresAt: Date(timeIntervalSince1970: fields.exp)
            )
        }

        inFlight = t
        let fresh = try await t.value
        // Back on the actor to update state
        cached = fresh
        inFlight = nil
        return fresh
    }
}

// Single shared cache to be used app‑wide.
public enum AlgoliaKeys {
    // Lazily create the cache on first access to avoid any work at type-load time.
    private static var _cache: AlgoliaKeyCache?
    public static var cache: AlgoliaKeyCache {
        if let c = _cache { return c }
        let c = AlgoliaKeyCache()
        _cache = c
        return c
    }

    /// Optional prewarm. Call this *after* Firebase has been configured (e.g., in AppDelegate).
    public static func warm() {
        Task { _ = try? await cache.get() }
    }
}
