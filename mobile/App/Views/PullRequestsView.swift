// Pull requests list + detail (meta, files, diff patch).
import SwiftUI
import HyperGitCore

struct PullRequestsView: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        Group {
            switch store.prsState {
            case .loading where store.pullRequests.isEmpty:
                ProgressView("Loading pull requests…").frame(maxWidth: .infinity, maxHeight: .infinity)
            case .error(let msg) where store.pullRequests.isEmpty:
                PlaceholderView(icon: "exclamationmark.triangle", title: "Couldn’t load", subtitle: msg)
            default:
                if store.pullRequests.isEmpty {
                    PlaceholderView(icon: "arrow.triangle.pull", title: "No pull requests", subtitle: "")
                } else {
                    List(store.pullRequests) { pr in
                        NavigationLink {
                            PullRequestDetailView(number: pr.number)
                        } label: { PRRow(pr: pr) }
                    }
                }
            }
        }
        .task { await store.loadPullRequests() }
    }
}

struct PRRow: View {
    let pr: HGPullRequest
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: pr.isMerged ? "arrow.triangle.merge" : (pr.isDraft ? "pencil" : "arrow.triangle.pull"))
                    .foregroundStyle(pr.isMerged ? .purple : (pr.isDraft ? .gray : .green))
                Text(pr.title).font(.body.weight(.semibold)).lineLimit(2)
            }
            HStack(spacing: 10) {
                Text("#\(pr.number)").font(.caption).foregroundStyle(.secondary)
                Theme.badge(text: pr.displayState, color: pr.isMerged ? .purple : (pr.isDraft ? .gray : .green))
                if let who = pr.author?.login { Text(who).font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Text("+\(pr.additions) −\(pr.deletions)").font(.caption.monospaced())
                    .foregroundStyle(.green.mix(deletion: pr.deletions > pr.additions))
            }
        }
        .padding(.vertical, 2)
    }
}

struct PullRequestDetailView: View {
    @Environment(AppStore.self) private var store
    let number: Int
    @State private var files: [HGFileChange] = []

    var body: some View {
        List {
            if let pr = store.pullRequests.first(where: { $0.number == number }) {
                Section {
                    Text(pr.title).font(.headline)
                    if let body = pr.body, !body.isEmpty {
                        Text(body).font(.footnote).foregroundStyle(.secondary)
                    }
                    LabeledContent("State", value: pr.displayState)
                    LabeledContent("Branch", value: "\(pr.head) → \(pr.base)")
                    LabeledContent("Changes", value: "+\(pr.additions) −\(pr.deletions) · \(pr.changedFiles) files")
                }
            }
            Section("Files") {
                if files.isEmpty {
                    Text("No file changes loaded.").foregroundStyle(.secondary)
                }
                ForEach(files) { file in
                    FileChangeRow(file: file)
                }
            }
        }
        .task {
            guard let repo = store.selectedRepo else { return }
            files = (try? await store.repoSource.pullRequestFiles(owner: repo.ownerLogin, repo: repo.name, number: number)) ?? []
        }
        .navigationTitle("PR #\(number)")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct FileChangeRow: View {
    let file: HGFileChange
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(file.path).font(.subheadline).lineLimit(2)
            HStack(spacing: 8) {
                Theme.badge(text: file.status.rawValue, color: color(for: file.status))
                Text("+\(file.additions) −\(file.deletions)").font(.caption.monospaced()).foregroundStyle(.secondary)
            }
        }
    }
    private func color(for status: HGFileChange.Status) -> Color {
        switch status {
        case .added: return .green
        case .removed: return .red
        case .modified, .changed: return .yellow
        case .renamed, .copied: return .blue
        }
    }
}

private extension Color {
    func mix(deletion: Bool) -> Color { deletion ? .red : self }
}
