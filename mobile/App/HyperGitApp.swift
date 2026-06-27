// HyperGitApp — @main entry. Builds the real GitHub + Linear clients over a
// Keychain-backed token store and injects the shared AppStore into SwiftUI.
import SwiftUI
import HyperGitCore

@main
struct HyperGitApp: App {
    @State private var store: AppStore
    @State private var tokenStore: KeychainTokenStore

    init() {
        let tokens = KeychainTokenStore()
        let github = GitHubClient(tokenProvider: { tokens.token(for: .github) })
        let linear = LinearClient(tokenProvider: { tokens.token(for: .linear) })
        _tokenStore = State(initialValue: tokens)
        _store = State(initialValue: AppStore(
            repoSource: github,
            ticketSources: [linear]
        ))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(\.tokenStore, tokenStore)
        }
    }
}

struct RootView: View {
    @Environment(AppStore.self) private var store
    @State private var selection: Tab = .repos

    enum Tab: Hashable { case repos, tickets, search, settings }

    var body: some View {
        TabView(selection: $selection) {
            ReposTab()
                .tabItem { Label("Repos", systemImage: "square.stack.3d.up") }
                .tag(Tab.repos)
            TicketsTab()
                .tabItem { Label("Tickets", systemImage: "ticket") }
                .tag(Tab.tickets)
            SearchTab()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(Tab.search)
            SettingsTab()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        .tint(Theme.tint)
    }
}

private struct SearchTab: View {
    var body: some View {
        NavigationStack {
            PlaceholderView(
                icon: "magnifyingglass",
                title: "Smart Search",
                subtitle: "Fuzzy + symbol + AI search lands in Phase 2 (SPEC §2.2)."
            )
            .navigationTitle("Search")
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
