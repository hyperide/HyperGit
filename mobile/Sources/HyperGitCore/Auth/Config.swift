// Config — loads OAuth credentials from environment variables or Config.plist.
// Priority: 1) Environment variables, 2) Config.plist in bundle.
import Foundation

public struct OAuthAppConfig: Sendable {
    public let githubClientId: String
    public let githubClientSecret: String
    public let linearClientId: String
    public let linearClientSecret: String

    public init(githubClientId: String, githubClientSecret: String, linearClientId: String, linearClientSecret: String) {
        self.githubClientId = githubClientId
        self.githubClientSecret = githubClientSecret
        self.linearClientId = linearClientId
        self.linearClientSecret = linearClientSecret
    }

    public static func load() -> OAuthAppConfig {
        // 1. Environment variables (highest priority)
        let githubClientId = ProcessInfo.processInfo.environment["HYPERGIT_GITHUB_CLIENT_ID"] ?? ""
        let githubClientSecret = ProcessInfo.processInfo.environment["HYPERGIT_GITHUB_CLIENT_SECRET"] ?? ""
        let linearClientId = ProcessInfo.processInfo.environment["HYPERGIT_LINEAR_CLIENT_ID"] ?? ""
        let linearClientSecret = ProcessInfo.processInfo.environment["HYPERGIT_LINEAR_CLIENT_SECRET"] ?? ""

        // 2. Config.plist in bundle (for release builds)
        var githubId = githubClientId
        var githubSecret = githubClientSecret
        var linearId = linearClientId
        var linearSecret = linearClientSecret

        if githubId.isEmpty || githubSecret.isEmpty || linearId.isEmpty || linearSecret.isEmpty {
            if let url = Bundle.main.url(forResource: "Config", withExtension: "plist"),
               let data = try? Data(contentsOf: url),
               let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String] {
                if githubId.isEmpty { githubId = plist["GITHUB_CLIENT_ID"] ?? "" }
                if githubSecret.isEmpty { githubSecret = plist["GITHUB_CLIENT_SECRET"] ?? "" }
                if linearId.isEmpty { linearId = plist["LINEAR_CLIENT_ID"] ?? "" }
                if linearSecret.isEmpty { linearSecret = plist["LINEAR_CLIENT_SECRET"] ?? "" }
            }
        }

        return OAuthAppConfig(
            githubClientId: githubId,
            githubClientSecret: githubSecret,
            linearClientId: linearId,
            linearClientSecret: linearSecret
        )
    }
}

// Extension to create configured OAuthConfig instances
extension OAuthConfig {
    public static var githubWithConfig: OAuthConfig {
        let config = OAuthAppConfig.load()
        return OAuthConfig(
            provider: .github,
            clientId: config.githubClientId,
            clientSecret: config.githubClientSecret,
            redirectURI: "hypergit://oauth-callback?provider=github",
            scopes: ["repo", "read:user", "user:email"],
            authURL: URL(string: "https://github.com/login/oauth/authorize")!,
            tokenURL: URL(string: "https://github.com/login/oauth/access_token")!
        )
    }

    public static var linearWithConfig: OAuthConfig {
        let config = OAuthAppConfig.load()
        return OAuthConfig(
            provider: .linear,
            clientId: config.linearClientId,
            clientSecret: config.linearClientSecret,
            redirectURI: "hypergit://oauth-callback?provider=linear",
            scopes: ["read", "write"],
            authURL: URL(string: "https://linear.app/oauth/authorize")!,
            tokenURL: URL(string: "https://api.linear.app/oauth/token")!
        )
    }
}