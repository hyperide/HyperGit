// Repo detail — Files / Pull Requests / Issues / Commits sections for one repo.
import SwiftUI
import HyperGitCore

struct RepoDetailView: View {
    @Environment(AppStore.self) private var store
    let repo: HGRepo
    @State private var section: Section = .files

    enum Section: String, CaseIterable, Identifiable {
        case files = "Files", pulls = "Pulls", issues = "Issues", commits = "Commits"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $section) {
                ForEach(Section.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding()

            switch section {
            case .files: FileTreeView(branch: repo.defaultBranch)
            case .pulls: PullRequestsView()
            case .issues: IssuesView()
            case .commits: CommitsView(branch: repo.defaultBranch)
            }
        }
        .navigationTitle(repo.name)
        .inlineNavigationBarTitle()
        .onAppear { store.select(repo) }
    }
}

struct CommitsView: View {
    @Environment(AppStore.self) private var store
    let branch: String?
    var body: some View {
        Group {
            if store.commits.isEmpty {
                PlaceholderView(icon: "clock.arrow.circlepath", title: "No commits loaded",
                                subtitle: "Commit history is fetched when the repo is opened.")
            } else {
                List(store.commits) { commit in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(commit.subject).font(.subheadline.weight(.medium))
                        HStack(spacing: 8) {
                            Text(commit.shortSHA).font(.caption.monospaced()).foregroundStyle(.secondary)
                            if let who = commit.authorLogin { Text(who).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
        }
        .task { await store.loadCommits(branch: branch) }
    }
}
