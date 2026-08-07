// HyperGitApp — @main entry. Builds the real GitHub + Linear clients over a
// Keychain-backed token store and injects the shared AppStore into SwiftUI.
import SwiftUI
import HyperGitCore

@main
struct HyperGitApp: App {
    @State private var store: AppStore
    @State private var tokenStore: KeychainTokenStore
    @StateObject private var githubOAuth: OAuthService
    @StateObject private var linearOAuth: OAuthService

    init() {
        let tokens = KeychainTokenStore()

        // Initialize OAuth services with config from environment/Config.plist
        let githubOAuth = OAuthService(provider: .github, config: OAuthConfig.githubWithConfig, tokenStore: tokens)
        let linearOAuth = OAuthService(provider: .linear, config: OAuthConfig.linearWithConfig, tokenStore: tokens)

        // Build clients with tokenStore for OAuth support
        let github = GitHubClient(
            tokenProvider: { tokens.token(for: .github) },
            oauthAccessTokenProvider: { try await githubOAuth.validAccessToken() },
            tokenStore: tokens
        )
        let linear = LinearClient(
            tokenProvider: { tokens.token(for: .linear) },
            oauthAccessTokenProvider: { try await linearOAuth.validAccessToken() },
            tokenStore: tokens
        )

        _tokenStore = State(initialValue: tokens)
        _githubOAuth = StateObject(wrappedValue: githubOAuth)
        _linearOAuth = StateObject(wrappedValue: linearOAuth)
        _store = State(initialValue: AppStore(
            repoSource: github,
            ticketSources: [github, linear]
        ))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(\.tokenStore, tokenStore)
                .environment(\.githubOAuthService, githubOAuth)
                .environment(\.linearOAuthService, linearOAuth)
                .onOpenURL { url in
                    // OAuth callbacks handled by ASWebAuthenticationSession internally
                }
        }
    }
}

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.tokenStore) private var tokenStore
    @State private var selection: Tab

    enum Tab: String, Hashable, CaseIterable {
        case repos = "Repos"
        case tickets = "Tickets"
        case search = "Search"
        case settings = "Settings"
    }

    init() {
        _selection = State(initialValue: .settings)
    }

    var hasGitHubToken: Bool {
        AuthTokenSelection.hasStoredCredential(
            manual: tokenStore.token(for: .github),
            oauth: tokenStore.oauthTokens(for: .github)
        )
    }

    var body: some View {
        TabView(selection: $selection) {
            reposTab
                .tabItem { Label("Repos", systemImage: "square.stack.3d.up") }
                .tag(Tab.repos)
            ticketsTab
                .tabItem { Label("Tickets", systemImage: "ticket") }
                .tag(Tab.tickets)
            searchTab
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(Tab.search)
            SettingsTab()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        .tint(Theme.tint)
        .onAppear {
            if selection == .settings, hasGitHubToken {
                selection = .repos
            }
        }
    }

    private var reposTab: some View {
        NavigationStack {
            if hasGitHubToken {
                ReposView()
                    .navigationTitle("Repositories")
                    .toolbar {
                        ToolbarItem(placement: .appTrailing) {
                            Button { Task { await store.loadRepositories() } } label: { Image(systemName: "arrow.clockwise") }
                        }
                    }
            } else {
                EmptyStateWithSettingsLink(
                    icon: "person.crop.circle.badge.questionmark",
                    title: "Add GitHub token",
                    subtitle: "Enter a GitHub PAT in Settings to browse repositories.",
                    settingsAction: { selection = .settings }
                )
            }
        }
    }

    private var ticketsTab: some View {
        NavigationStack {
            let hasLinearToken = AuthTokenSelection.hasStoredCredential(
                manual: tokenStore.token(for: .linear),
                oauth: tokenStore.oauthTokens(for: .linear)
            )
            if hasGitHubToken || hasLinearToken {
                TicketsView()
                    .navigationTitle("Tickets")
                    .toolbar {
                        ToolbarItem(placement: .appTrailing) {
                            Button { Task { await store.loadTickets() } } label: { Image(systemName: "arrow.clockwise") }
                        }
                    }
            } else {
                EmptyStateWithSettingsLink(
                    icon: "ticket",
                    title: "Add tokens to see tickets",
                    subtitle: "Add a GitHub PAT and/or Linear API key in Settings.",
                    settingsAction: { selection = .settings }
                )
            }
        }
    }

    private var searchTab: some View {
        NavigationStack {
            if hasGitHubToken {
                PlaceholderView(
                    icon: "magnifyingglass",
                    title: "Smart Search",
                    subtitle: "Fuzzy + symbol + AI search lands in Phase 2 (SPEC §2.2)."
                )
                .navigationTitle("Search")
            } else {
                EmptyStateWithSettingsLink(
                    icon: "magnifyingglass",
                    title: "Add GitHub token",
                    subtitle: "Search requires a GitHub token in Settings.",
                    settingsAction: { selection = .settings }
                )
            }
        }
    }
}

private struct EmptyStateWithSettingsLink: View {
    let icon: String
    let title: String
    let subtitle: String
    let settingsAction: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
        } description: {
            Text(subtitle)
        } actions: {
            Button("Open Settings", action: settingsAction)
                .buttonStyle(.borderedProminent)
        }
    }
}

private struct SettingsTab: View {
    var body: some View {
        NavigationStack {
            SettingsView()
                .navigationTitle("Settings")
        }
    }
}

// SwiftUI environment carrier for the token store (Keychain on device).
private struct TokenStoreKey: EnvironmentKey {
    static let defaultValue: KeychainTokenStore = KeychainTokenStore()
}
private struct GitHubOAuthServiceKey: EnvironmentKey {
    static let defaultValue: OAuthService? = nil
}
private struct LinearOAuthServiceKey: EnvironmentKey {
    static let defaultValue: OAuthService? = nil
}
extension EnvironmentValues {
    var tokenStore: KeychainTokenStore {
        get { self[TokenStoreKey.self] }
        set { self[TokenStoreKey.self] = newValue }
    }
    var githubOAuthService: OAuthService? {
        get { self[GitHubOAuthServiceKey.self] }
        set { self[GitHubOAuthServiceKey.self] = newValue }
    }
    var linearOAuthService: OAuthService? {
        get { self[LinearOAuthServiceKey.self] }
        set { self[LinearOAuthServiceKey.self] = newValue }
    }
}
