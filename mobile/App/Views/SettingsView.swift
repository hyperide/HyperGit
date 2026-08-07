// Settings — GitHub PAT + Linear API key entry, stored in the Keychain.
// Auto-save on change, auto-reload, links with scopes & instructions.
import SwiftUI
import HyperGitCore

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.tokenStore) private var tokenStore
    @Environment(\.githubOAuthService) private var githubOAuth
    @Environment(\.linearOAuthService) private var linearOAuth
    @State private var githubToken = ""
    @State private var linearKey = ""
    @State private var githubValid = false
    @State private var linearValid = false
    @State private var authenticatingProvider: OAuthProvider?
    @State private var authMessage: String?

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

            Button {
                authenticate(githubOAuth, provider: .github)
            } label: {
                if authenticatingProvider == .github {
                    ProgressView()
                } else {
                    Label("Sign in with GitHub", systemImage: "person.crop.circle.badge.checkmark")
                }
            }
            .disabled(authenticatingProvider != nil || !canAuthenticate(githubOAuth))

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

            Button {
                authenticate(linearOAuth, provider: .linear)
            } label: {
                if authenticatingProvider == .linear {
                    ProgressView()
                } else {
                    Label("Sign in with Linear", systemImage: "person.crop.circle.badge.checkmark")
                }
            }
            .disabled(authenticatingProvider != nil || !canAuthenticate(linearOAuth))

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
            if let authMessage {
                Text(authMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
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
        let manual = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if !manual.isEmpty {
            githubValid = manual.hasPrefix("ghp_") || manual.hasPrefix("github_pat_")
        } else {
            githubValid = AuthTokenSelection.hasCredential(
                manual: nil,
                oauth: tokenStore.oauthTokens(for: .github),
                canRefreshOAuth: canAuthenticate(githubOAuth)
            )
        }
    }

    private func validateLinear(_ key: String) {
        let manual = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if !manual.isEmpty {
            linearValid = manual.count >= 20
        } else {
            linearValid = AuthTokenSelection.hasCredential(
                manual: nil,
                oauth: tokenStore.oauthTokens(for: .linear),
                canRefreshOAuth: canAuthenticate(linearOAuth)
            )
        }
    }

    private func seed() {
        githubToken = tokenStore.token(for: .github) ?? ""
        linearKey = tokenStore.token(for: .linear) ?? ""
        validateGitHub(githubToken)
        validateLinear(linearKey)
    }

    private func canAuthenticate(_ service: OAuthService?) -> Bool {
        guard let service else { return false }
        return !service.config.clientId.isEmpty && !service.config.clientSecret.isEmpty
    }

    private func authenticate(_ service: OAuthService?, provider: OAuthProvider) {
        guard authenticatingProvider == nil else {
            authMessage = "Another sign-in is already in progress."
            return
        }
        guard let service else {
            authMessage = "OAuth service is not available."
            return
        }
        Task { @MainActor in
            authenticatingProvider = provider
            defer { authenticatingProvider = nil }
            do {
                _ = try await service.authenticate()
                clearManualCredential(for: provider)
                seed()
                authMessage = "\(provider.displayName) connected."
                if provider == .github {
                    await store.loadRepositories()
                } else {
                    await store.loadTickets()
                }
            } catch OAuthError.invalidConfiguration {
                authMessage = "\(provider.displayName) OAuth is not configured. Use a token instead."
            } catch OAuthError.userCancelled {
                authMessage = "\(provider.displayName) sign-in cancelled."
            } catch OAuthError.authenticationInProgress {
                authMessage = "\(provider.displayName) sign-in is already in progress."
            } catch {
                authMessage = "\(provider.displayName) sign-in failed: \(error.localizedDescription)"
            }
        }
    }

    private func clearManualCredential(for provider: OAuthProvider) {
        switch provider {
        case .github:
            githubToken = ""
            try? tokenStore.setToken(nil, for: .github)
        case .linear:
            linearKey = ""
            try? tokenStore.setToken(nil, for: .linear)
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

private extension OAuthProvider {
    var displayName: String {
        switch self {
        case .github: return "GitHub"
        case .linear: return "Linear"
        }
    }
}
