// Auth — token storage for GitHub / Linear credentials.
// Keychain-backed on device; in-memory alternative for tests/previews.
import Foundation
import Security

public enum TokenKey: String, Sendable {
    case github
    case linear
}

public enum OAuthProvider: String, Sendable, CaseIterable {
    case github
    case linear
}

public struct OAuthTokens: Sendable, Equatable, Codable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresAt: Date?
    public let scope: String?
    public let tokenType: String?

    public init(accessToken: String, refreshToken: String? = nil, expiresAt: Date? = nil, scope: String? = nil, tokenType: String? = "Bearer") {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.scope = scope
        self.tokenType = tokenType
    }

    public var isExpired: Bool {
        guard let expiresAt else { return false }
        return Date() >= expiresAt.addingTimeInterval(-60) // 60s buffer
    }
}

public protocol TokenStore: Sendable {
    func token(for key: TokenKey) -> String?
    func setToken(_ token: String?, for key: TokenKey) throws

    // OAuth token methods
    func oauthTokens(for provider: OAuthProvider) -> OAuthTokens?
    func setOAuthTokens(_ tokens: OAuthTokens?, for provider: OAuthProvider) throws
}

public enum KeychainError: Error, Equatable, Sendable {
    case unhandled(OSStatus)
    case encodingFailed
    case decodingFailed
}

/// Keychain-backed TokenStore. The Keychain itself is thread-safe; this type is a
/// stateless struct and therefore trivially Sendable.
public struct KeychainTokenStore: TokenStore {
    public let service: String

    public init(service: String = "ai.hypergit.mobile") {
        self.service = service
    }

    // MARK: - Legacy PAT/Token storage

    public func token(for key: TokenKey) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let string = String(data: data, encoding: .utf8) else { return nil }
        return string
    }

    public func setToken(_ token: String?, for key: TokenKey) throws {
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
        SecItemDelete(baseQuery as CFDictionary)
        guard let token, !token.isEmpty, let data = token.data(using: .utf8) else { return }
        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status != errSecSuccess { throw KeychainError.unhandled(status) }
    }

    // MARK: - OAuth Token Storage

    private func oauthAccount(for provider: OAuthProvider) -> String {
        "oauth_\(provider.rawValue)"
    }

    public func oauthTokens(for provider: OAuthProvider) -> OAuthTokens? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: oauthAccount(for: provider),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let tokens = try? JSONDecoder().decode(OAuthTokens.self, from: data) else { return nil }
        return tokens
    }

    public func setOAuthTokens(_ tokens: OAuthTokens?, for provider: OAuthProvider) throws {
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: oauthAccount(for: provider),
        ]
        SecItemDelete(baseQuery as CFDictionary)
        guard let tokens, let data = try? JSONEncoder().encode(tokens) else { return }
        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status != errSecSuccess { throw KeychainError.unhandled(status) }
    }
}

/// In-memory TokenStore for previews and tests.
public struct InMemoryTokenStore: TokenStore {
    public let storage = AsyncBox<[TokenKey: String]>([:])
    public let oauthStorage = AsyncBox<[OAuthProvider: OAuthTokens]>([:])

    public init() {}

    public func token(for key: TokenKey) -> String? { storage.syncValue[key] }
    public func setToken(_ token: String?, for key: TokenKey) throws { storage.syncMutate { $0[key] = token } }

    public func oauthTokens(for provider: OAuthProvider) -> OAuthTokens? { oauthStorage.syncValue[provider] }
    public func setOAuthTokens(_ tokens: OAuthTokens?, for provider: OAuthProvider) throws { oauthStorage.syncMutate { $0[provider] = tokens } }
}

/// Lock-protected mutable box (the only mutable stateless-safe shared holder).
public final class AsyncBox<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value
    public init(_ value: Value) { self.value = value }
    public var syncValue: Value { lock.lock(); defer { lock.unlock() }; return value }
    public func syncMutate(_ change: @Sendable (inout Value) -> Void) {
        lock.lock(); defer { lock.unlock() }; change(&value)
    }
}