// Settings — GitHub PAT + Linear API key entry, stored in the Keychain via
// the shared TokenStore. Tokens are read live by the clients, so a refresh
// after saving uses the new credentials.
import SwiftUI
import HyperGitCore

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.tokenStore) private var tokenStore
    @State private var githubToken = ""
    @State private var linearKey = ""
    @State private var saved: String?

    var body: some View {
        Form {
            Section {
                SecureField("GitHub token", text: $githubToken)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                Button("Save GitHub token") { saveGitHub() }
                Text("A classic PAT with `repo` scope. Stored in Keychain.")
                    .font(.footnote).foregroundStyle(.secondary)
            } header: { Text("GitHub") }

            Section {
                SecureField("Linear API key", text: $linearKey)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                Button("Save Linear key") { saveLinear() }
                Text("Personal API key from Linear → Settings → API.")
                    .font(.footnote).foregroundStyle(.secondary)
            } header: { Text("Linear") }

            Section {
                Button("Reload data") {
                    Task {
                        await store.loadRepositories()
                        await store.loadTickets()
                    }
                }
            } header: { Text("Data") }

            if let saved {
                Section { Text(saved).font(.footnote).foregroundStyle(.green) }
            }
        }
        .onAppear { seed() }
    }

    private func seed() {
        githubToken = tokenStore.token(for: .github) ?? ""
        linearKey = tokenStore.token(for: .linear) ?? ""
    }

    private func saveGitHub() {
        try? tokenStore.setToken(githubToken.nilIfEmpty, for: .github)
        saved = "GitHub token saved."
    }
    private func saveLinear() {
        try? tokenStore.setToken(linearKey.nilIfEmpty, for: .linear)
        saved = "Linear key saved."
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
