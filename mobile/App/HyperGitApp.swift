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
        let github = GitHubClient(tokenProvider: { tokens.token(for: .github) }, tokenStore: tokens)
        let linear = LinearClient(tokenProvider: { tokens.token(for: .linear) }, tokenStore: tokens)

        _tokenStore = State(initialValue: tokens)
        _githubOAuth = StateObject(wrappedValue: OAuthService(provider: .github, config: OAuthConfig.github, tokenStore: KeychainTokenStore()))
        _linearOAuth = StateObject(wrappedValue: OAuthService(provider: .linear, config: OAuthConfig.linear, tokenStore: KeychainTokenStore()))
        _store = State(initialValue: AppStore(
            repoSource: GitHubClient(tokenProvider: { KeychainTokenStore().token(for: .github) }, tokenStore: KeychainTokenStore()),
            ticketSources: [
                LinearClient(tokenProvider: { KeychainTokenStore().token(for: .linear) }, tokenStore: KeychainTokenStore())
            ]
        ))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(\.tokenStore, KeychainTokenStore())
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
        let tokenStore = KeychainTokenStore()
        let hasGitHubToken = tokenStore.token(for: .github) != nil || tokenStore.oauthTokens(for: .github) != nil
        _selection = State(initialValue: hasGitHubToken ? .repos : .settings)
    }

    var hasGitHubToken: Bool {
        let tokenStore = KeychainTokenStore()
        return tokenStore.token(for: .github) != nil || tokenStore.oauthTokens(for: .github) != nil
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
            let tokenStore = KeychainTokenStore()
            let hasLinearToken = tokenStore.token(for: .linear) != nil || tokenStore.oauthTokens(for: .linear) != nil
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
extension EnvironmentValues {
    var tokenStore: KeychainTokenStore {
        get { self[TokenStoreKey.self] }
        set { self[TokenStoreKey.self] = newValue }
    }
}