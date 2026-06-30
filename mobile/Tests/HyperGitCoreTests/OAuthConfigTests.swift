// OAuthConfig tests pin the mobile app's requested provider scopes. The MVP is
// read-only for Linear, so authorization must not request write access.
import Foundation
import Testing
@testable import HyperGitCore

@Suite("OAuth config")
struct OAuthConfigTests {
    @Test("Linear OAuth requests read-only scope")
    func linearReadOnlyScope() {
        #expect(OAuthConfig.linear.scopes == ["read"])
        #expect(OAuthConfig.linearWithConfig.scopes == ["read"])
    }

    @Test("manual credentials are preferred over stale OAuth tokens")
    func manualCredentialsPreferred() {
        let token = AuthTokenSelection.preferred(
            manual: " manual-token ",
            oauth: OAuthTokens(accessToken: "oauth-token")
        )
        #expect(token == "manual-token")
    }

    @Test("expired OAuth token is not selected")
    func expiredOAuthTokenIgnored() {
        let oauth = OAuthTokens(
            accessToken: "oauth-token",
            refreshToken: "refresh-token",
            expiresAt: Date(timeIntervalSince1970: 0)
        )
        let token = AuthTokenSelection.preferred(
            manual: nil,
            oauth: oauth
        )
        #expect(token == nil)
        #expect(AuthTokenSelection.hasCredential(manual: nil, oauth: oauth, canRefreshOAuth: true))
        #expect(!AuthTokenSelection.hasCredential(manual: nil, oauth: oauth, canRefreshOAuth: false))
        #expect(AuthTokenSelection.hasStoredCredential(manual: nil, oauth: oauth))
    }

    @Test("refresh response preserves old refresh token when omitted")
    func refreshTokenFallback() {
        let refreshed = OAuthTokens(accessToken: "new-token", refreshToken: nil)
            .preservingRefreshToken("old-refresh-token")
        #expect(refreshed.refreshToken == "old-refresh-token")
    }
}
