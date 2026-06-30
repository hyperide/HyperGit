// Settings — GitHub PAT + Linear API key entry, stored in the Keychain.
// Auto-save on change, auto-reload, links with scopes & instructions.
import SwiftUI
import HyperGitCore

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.tokenStore) private var tokenStore
    @State private var githubToken = ""
    @State private var linearKey = ""
    @State private var githubValid = false
    @State private var linearValid = false

    var body: some View {
        NavigationStack {
            Form {
                githubSection
                linearSection
                dataSection
            }
            .navigationTitle("Settings")
            .onAppear { seed() }
            .onChange(of: githubToken) { _, new in
                autoSave(new, for: .github)
                validateGitHub(new)
            }
            .onChange(of: linearKey) { _, new in
                autoSave(new, for: .linear)
                validateLinear(new)
            }
        }
    }

    private var githubSection: some View {
        Section {
            SecureField("GitHub Personal Access Token (classic)", text: $githubToken)
                .textContentType(.password)
                .autocorrectionDisabled()
#if os(iOS)
                .textInputAutocapitalization(.never)
#endif

            validationBadge(githubValid, text: githubValid ? "Valid token format" : "Enter a classic PAT with repo scope")

            VStack(alignment: .leading, spacing: 6) {
                Link("Create GitHub PAT →", destination: URL(string: "https://github.com/settings/tokens/new?scopes=repo&description=HyperGit")!)
                    .font(.footnote)
                Text("Scope: **repo** (full control of private repositories)")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Paste the token above. It never leaves your device (stored in Keychain).")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Label("GitHub", systemImage: githubValid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(githubValid ? .green : .orange)
        }
    }

    private var linearSection: some View {
        Section {
            SecureField("Linear API Key", text: $linearKey)
                .textContentType(.password)
                .autocorrectionDisabled()
#if os(iOS)
                .textInputAutocapitalization(.never)
#endif

            validationBadge(linearValid, text: linearValid ? "Valid key format" : "Enter a Linear API key")

            VStack(alignment: .leading, spacing: 6) {
                Link("Create Linear API Key →", destination: URL(string: "https://linear.app/settings/api")!)
                    .font(.footnote)
                Text("Personal API key from Linear → Settings → API → Generate new key")
                    .font(.caption).foregroundStyle(.secondary)
                Text("No scopes needed — key has full access to your workspace.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Label("Linear", systemImage: linearValid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(linearValid ? .green : .orange)
        }
    }

    private var dataSection: some View {
        Section {
            if store.reposState == .loading || store.ticketsState == .loading {
                ProgressView("Loading…")
            } else {
                Text("Data refreshes automatically when tokens are saved.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Text("Repos: \(store.repositories.count) · Tickets: \(store.tickets.count)")
                .font(.footnote).foregroundStyle(.secondary)
        } header: { Text("Data") }
    }

    private func validationBadge(_ valid: Bool, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: valid ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(valid ? .green : .orange)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func autoSave(_ value: String, for key: TokenKey) {
        try? tokenStore.setToken(value.nilIfEmpty, for: key)
    }

    private func validateGitHub(_ token: String) {
        githubValid = !token.isEmpty && (token.hasPrefix("ghp_") || token.hasPrefix("github_pat_"))
    }

    private func validateLinear(_ key: String) {
        linearValid = !key.isEmpty && key.count >= 20
    }

    private func seed() {
        githubToken = tokenStore.token(for: .github) ?? ""
        linearKey = tokenStore.token(for: .linear) ?? ""
        validateGitHub(githubToken)
        validateLinear(linearKey)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}