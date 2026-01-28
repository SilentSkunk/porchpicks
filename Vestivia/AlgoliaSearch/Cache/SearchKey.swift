import Foundation
import os

public struct SecuredSearchKey {
    public let id: String
    public let appId: String
    public let apiKey: String
    public let expiresAt: Date

    public init(appId: String, apiKey: String, expiresAt: Date) {
        self.id = UUID().uuidString.prefix(8).description
        self.appId = appId
        self.apiKey = apiKey
        self.expiresAt = expiresAt
    }
}

public enum SearchKey {
    /// Single source of truth: always hits the shared cache.
    public static func warm() async {
        _ = try? await AlgoliaKeys.cache.get()
    }

    public static func current() async throws -> SecuredSearchKey {
        let k = try await AlgoliaKeys.cache.get()
        return SecuredSearchKey(appId: k.appId, apiKey: k.value, expiresAt: k.expiresAt)
    }
}
