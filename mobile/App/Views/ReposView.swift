// Repos tab — repository list with offline-first refresh.
import SwiftUI
import HyperGitCore

struct ReposTab: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        NavigationStack {
            ReposView()
                .navigationTitle("Repositories")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Task { await store.loadRepositories() }
                        } label: { Image(systemName: "arrow.clockwise") }
                    }
                }
        }
    }
}

struct ReposView: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        Group {
            switch store.reposState {
            case .loading where store.repositories.isEmpty:
                ProgressView("Loading…").frame(maxWidth: .infinity, maxHeight: .infinity)
            case .error(let msg) where store.repositories.isEmpty:
                PlaceholderView(icon: "exclamationmark.triangle", title: "Couldn’t load", subtitle: msg)
            case .idle where store.repositories.isEmpty:
                PlaceholderView(icon: "person.crop.circle.badge.questionmark",
                                title: "Add a GitHub token",
                                subtitle: "Open Settings to paste a personal access token.")
            default:
                reposList
            }
        }
        .task { if store.repositories.isEmpty { await store.loadRepositories() } }
    }

    private var reposList: some View {
        List(store.repositories) { repo in
            NavigationLink(value: repo) {
                RepoRow(repo: repo)
            }
        }
        .navigationDestination(for: HGRepo.self) { repo in
            RepoDetailView(repo: repo)
        }
    }
}

struct RepoRow: View {
    let repo: HGRepo
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if repo.isPrivate { Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary) }
                Text(repo.fullName).font(.body.weight(.semibold))
            }
            if let d = repo.description, !d.isEmpty {
                Text(d).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
            }
            HStack(spacing: 12) {
                if let lang = repo.language { Theme.badge(text: lang, color: .indigo) }
                Label("\(repo.stargazersCount)", systemImage: "star").font(.caption).foregroundStyle(.secondary)
                if let updated = repo.updatedAt {
                    Spacer()
                    Text(updated.formatted(.relative(presentation: .named)))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
