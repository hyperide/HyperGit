// OAuthService — Web-based OAuth 2.0 flow with PKCE for GitHub and Linear.
// Uses ASWebAuthenticationSession for secure browser-based auth.
// Redirect URI: hypergit://oauth-callback?provider={github|linear}&code={code}&state={state}
import Foundation
import AuthenticationServices
import CryptoKit

public struct OAuthConfig: Sendable {
    public let provider: OAuthProvider
    public let clientId: String
    public let clientSecret: String
    public let redirectURI: String
    public let scopes: [String]
    public let authURL: URL
    public let tokenURL: URL

    public static let github = OAuthConfig(
        provider: .github,
        clientId: "", // Set from config/environment
        clientSecret: "",
        redirectURI: "hypergit://oauth-callback?provider=github",
        scopes: ["repo", "read:user", "user:email"],
        authURL: URL(string: "https://github.com/login/oauth/authorize")!,
        tokenURL: URL(string: "https://github.com/login/oauth/access_token")!
    )

    public static let linear = OAuthConfig(
        provider: .linear,
        clientId: "",
        clientSecret: "",
        redirectURI: "hypergit://oauth-callback?provider=linear",
        scopes: ["read"],
        authURL: URL(string: "https://linear.app/oauth/authorize")!,
        tokenURL: URL(string: "https://api.linear.app/oauth/token")!
    )
}

public enum OAuthError: Error, Equatable, Sendable {
    case invalidConfiguration(String)
    case userCancelled
    case invalidCallbackURL(String)
    case missingCode
    case missingState
    case stateMismatch(expected: String, received: String)
    case tokenExchangeFailed(String)
    case tokenRefreshFailed(String)
    case invalidTokenResponse
    case pkceGenerationFailed
    case noPresentationContext
    case providerMismatch
    case authenticationInProgress
}

@MainActor
public final class OAuthService: NSObject, ObservableObject {
    public let provider: OAuthProvider
    public let config: OAuthConfig
    public let tokenStore: any TokenStore

    private var currentSession: ASWebAuthenticationSession?
    private var continuation: CheckedContinuation<OAuthTokens, Error>?
    private var pkceVerifier: String?

    public init(provider: OAuthProvider, config: OAuthConfig, tokenStore: any TokenStore) {
        self.provider = provider
        self.config = config
        self.tokenStore = tokenStore
        super.init()
    }

    /// Start the OAuth authorization flow. Returns tokens on success.
    public func authenticate() async throws -> OAuthTokens {
        guard currentSession == nil, continuation == nil else {
            throw OAuthError.authenticationInProgress
        }
        guard !config.clientId.isEmpty, !config.clientSecret.isEmpty else {
            throw OAuthError.invalidConfiguration("Missing client ID or secret for \(provider.rawValue)")
        }

        let pkce = generatePKCE()
        pkceVerifier = pkce.verifier

        let authURL = buildAuthURL(codeChallenge: pkce.challenge)
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: "hypergit"
            ) { callbackURL, error in
                Task { @MainActor in
                    self.handleCallback(callbackURL: callbackURL, error: error)
                }
            }

            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            session.start()
            self.currentSession = session
        }
    }

    /// Refresh the access token using the stored refresh token.
    public func refreshToken() async throws -> OAuthTokens {
        guard let storedTokens = tokenStore.oauthTokens(for: provider),
              let refreshToken = storedTokens.refreshToken else {
            throw OAuthError.tokenRefreshFailed("No refresh token available")
        }

        var bodyItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "client_id", value: config.clientId),
        ]
        if provider == .github {
            bodyItems.append(URLQueryItem(name: "client_secret", value: config.clientSecret))
        }

        var request = URLRequest(url: config.tokenURL)
        request.httpMethod = "POST"
        request.httpBody = formURLEncodedData(bodyItems)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("HyperGitMobile/1.0", forHTTPHeaderField: "User-Agent")
        if provider == .linear {
            request.setValue(basicAuthorizationHeader(), forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OAuthError.invalidTokenResponse
        }

        switch httpResponse.statusCode {
        case 200..<300:
            let tokens = try parseTokenResponse(data, provider: provider)
                .preservingRefreshToken(refreshToken)
            try tokenStore.setOAuthTokens(tokens, for: provider)
            return tokens
        case 400, 401:
            throw OAuthError.tokenRefreshFailed("Refresh token expired or invalid")
        default:
            throw OAuthError.tokenRefreshFailed("HTTP \(httpResponse.statusCode)")
        }
    }

    /// Get a valid access token, refreshing if necessary.
    public func validAccessToken() async throws -> String {
        guard let tokens = tokenStore.oauthTokens(for: provider) else {
            throw OAuthError.tokenRefreshFailed("Not authenticated")
        }

        if tokens.isExpired {
            return try await refreshToken().accessToken
        }
        return tokens.accessToken
    }

    /// Revoke stored tokens (logout).
    public func revoke() throws {
        try tokenStore.setOAuthTokens(nil, for: provider)
    }

    // MARK: - Private

    private func buildAuthURL(codeChallenge: String) -> URL {
        var components = URLComponents(url: config.authURL, resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "client_id", value: config.clientId),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI),
            URLQueryItem(name: "scope", value: config.scopes.joined(separator: " ")),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: generateState()),
        ]
        if provider == .github {
            items.append(URLQueryItem(name: "allow_signup", value: "true"))
        }
        components.queryItems = items
        return components.url!
    }

    private func handleCallback(callbackURL: URL?, error: Error?) {
        if let error = error as? ASWebAuthenticationSessionError,
           error.code == .canceledLogin {
            finishAuthentication(.failure(OAuthError.userCancelled))
            return
        }

        guard let callbackURL else {
            finishAuthentication(.failure(OAuthError.invalidCallbackURL("No callback URL")))
            return
        }

        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            finishAuthentication(.failure(OAuthError.invalidCallbackURL(callbackURL.absoluteString)))
            return
        }

        let params = Dictionary(uniqueKeysWithValues: queryItems.map { ($0.name, $0.value ?? "") })

        guard params["provider"] == provider.rawValue else {
            finishAuthentication(.failure(OAuthError.providerMismatch))
            return
        }

        guard let code = params["code"], !code.isEmpty else {
            finishAuthentication(.failure(OAuthError.missingCode))
            return
        }

        let receivedState = params["state"]
        let expectedState = UserDefaults.standard.string(forKey: "oauth_state_\(provider.rawValue)")
        UserDefaults.standard.removeObject(forKey: "oauth_state_\(provider.rawValue)")

        guard let expectedState, receivedState == expectedState else {
            finishAuthentication(.failure(OAuthError.stateMismatch(expected: expectedState ?? "", received: receivedState ?? "")))
            return
        }

        guard let verifier = pkceVerifier else {
            finishAuthentication(.failure(OAuthError.pkceGenerationFailed))
            return
        }

        Task {
            do {
                let tokens = try await exchangeCodeForTokens(code: code, verifier: verifier)
                try tokenStore.setOAuthTokens(tokens, for: provider)
                finishAuthentication(.success(tokens))
            } catch {
                finishAuthentication(.failure(error))
            }
        }
    }

    private func exchangeCodeForTokens(code: String, verifier: String) async throws -> OAuthTokens {
        var bodyItems = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI),
            URLQueryItem(name: "client_id", value: config.clientId),
            URLQueryItem(name: "code_verifier", value: verifier),
        ]

        // GitHub uses client_secret in body; Linear uses Basic auth
        if provider == .github {
            bodyItems.append(URLQueryItem(name: "client_secret", value: config.clientSecret))
        }

        var request = URLRequest(url: config.tokenURL)
        request.httpMethod = "POST"
        request.httpBody = formURLEncodedData(bodyItems)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("HyperGitMobile/1.0", forHTTPHeaderField: "User-Agent")

        // Linear uses Basic auth for client credentials
        if provider == .linear {
            request.setValue(basicAuthorizationHeader(), forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OAuthError.invalidTokenResponse
        }

        switch httpResponse.statusCode {
        case 200..<300:
            return try parseTokenResponse(data, provider: provider)
        case 400, 401:
            let errorDesc = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw OAuthError.tokenExchangeFailed(errorDesc)
        default:
            throw OAuthError.tokenExchangeFailed("HTTP \(httpResponse.statusCode)")
        }
    }

    private func finishAuthentication(_ result: Result<OAuthTokens, Error>) {
        let continuation = continuation
        self.continuation = nil
        currentSession = nil
        pkceVerifier = nil

        switch result {
        case .success(let tokens):
            continuation?.resume(returning: tokens)
        case .failure(let error):
            continuation?.resume(throwing: error)
        }
    }

    private func formURLEncodedData(_ queryItems: [URLQueryItem]) -> Data {
        var components = URLComponents()
        components.queryItems = queryItems
        return Data((components.percentEncodedQuery ?? "").utf8)
    }

    private func basicAuthorizationHeader() -> String {
        let credentials = "\(config.clientId):\(config.clientSecret)"
            .data(using: .utf8)?
            .base64EncodedString() ?? ""
        return "Basic \(credentials)"
    }

    private func parseTokenResponse(_ data: Data, provider: OAuthProvider) throws -> OAuthTokens {
        // GitHub returns form-urlencoded by default unless Accept: application/json
        // Linear returns JSON
        if provider == .github {
            // Try JSON first, then form-urlencoded
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let accessToken = json["access_token"] as? String {
                let expiresIn = json["expires_in"] as? Int
                let refreshToken = json["refresh_token"] as? String
                let scope = json["scope"] as? String
                let tokenType = json["token_type"] as? String ?? "Bearer"
                let expiresAt = expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) }
                return OAuthTokens(
                    accessToken: accessToken,
                    refreshToken: refreshToken,
                    expiresAt: expiresAt,
                    scope: scope,
                    tokenType: tokenType
                )
            }
            // Fallback: parse form-urlencoded
            let string = String(data: data, encoding: .utf8) ?? ""
            let params = parseFormURLEncoded(string)
            guard let accessToken = params["access_token"] else {
                throw OAuthError.invalidTokenResponse
            }
            let expiresIn = params["expires_in"].flatMap(Int.init)
            let refreshToken = params["refresh_token"]
            let scope = params["scope"]
            let tokenType = params["token_type"] ?? "Bearer"
            let expiresAt = expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) }
            return OAuthTokens(
                accessToken: accessToken,
                refreshToken: refreshToken,
                expiresAt: expiresAt,
                scope: scope,
                tokenType: tokenType
            )
        } else {
            // Linear returns JSON
            let decoder = JSONDecoder()
            struct LinearTokenResponse: Decodable {
                let access_token: String
                let token_type: String
                let expires_in: Int?
                let refresh_token: String?
                let scope: String?
            }
            let response = try decoder.decode(LinearTokenResponse.self, from: data)
            let expiresAt = response.expires_in.map { Date().addingTimeInterval(TimeInterval($0)) }
            return OAuthTokens(
                accessToken: response.access_token,
                refreshToken: response.refresh_token,
                expiresAt: expiresAt,
                scope: response.scope,
                tokenType: response.token_type
            )
        }
    }

    private func parseFormURLEncoded(_ string: String) -> [String: String] {
        var result: [String: String] = [:]
        for pair in string.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            if kv.count == 2 {
                let key = kv[0].removingPercentEncoding ?? kv[0]
                let value = kv[1].removingPercentEncoding ?? kv[1]
                result[key] = value
            }
        }
        return result
    }

    private func generatePKCE() -> (verifier: String, challenge: String) {
        let verifier = randomBase64URLString(length: 32)
        let challenge = verifier.data(using: .ascii)!
            .sha256
            .base64URLEncodedString()
        return (verifier, challenge)
    }

    private func generateState() -> String {
        let state = randomBase64URLString(length: 32)
        UserDefaults.standard.set(state, forKey: "oauth_state_\(provider.rawValue)")
        return state
    }

    private func randomBase64URLString(length: Int) -> String {
        var bytes = Data(count: length)
        _ = bytes.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, length, $0.baseAddress!) }
        return bytes.base64URLEncodedString()
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension OAuthService: ASWebAuthenticationPresentationContextProviding {
    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(iOS)
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        return windowScene?.windows.first(where: \.isKeyWindow) ?? UIWindow()
        #elseif os(macOS)
        return NSApp.windows.first(where: \.isKeyWindow) ?? NSWindow()
        #endif
    }
}

// MARK: - CryptoKit helpers

private extension Data {
    var sha256: Data {
        let hash = SHA256.hash(data: self)
        return Data(hash)
    }

    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
