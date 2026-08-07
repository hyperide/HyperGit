// Pull requests list + detail (meta, files diff, checks).
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
    // Checks are fetched only here (per-PR, on detail open), never in the
    // list — fetching per row would be an N+1 call for every visible PR.
    @State private var checkRuns: [HGCheckRun] = []
    // Tracked separately from `checkRuns.isEmpty`: a failed fetch must not
    // read as "No checks reported" — that's a materially different, higher-
    // stakes claim (a PR could have failing checks the app just couldn't
    // load) than "this commit genuinely has none".
    @State private var checksState: LoadState = .idle

    private var checksSummary: HGChecksSummary { HGChecksSummary(runs: checkRuns) }

    var body: some View {
        List {
            if let pr = store.pullRequests.first(where: { $0.number == number }) {
                metaSection(for: pr)
            }
            checksSection
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
            await loadDetail(owner: repo.ownerLogin, repo: repo.name)
        }
        .navigationTitle("PR #\(number)")
        .inlineNavigationBarTitle()
    }

    private func loadDetail(owner: String, repo: String) async {
        // Files and checks are independent fetches — run them concurrently
        // instead of paying their latencies back-to-back.
        let ref = store.pullRequests.first(where: { $0.number == number })?.checksRef
        async let filesResult = (try? await store.repoSource.pullRequestFiles(owner: owner, repo: repo, number: number)) ?? []
        async let checksResult = fetchChecks(owner: owner, repo: repo, ref: ref)
        files = await filesResult
        checkRuns = await checksResult
    }

    private func fetchChecks(owner: String, repo: String, ref: String?) async -> [HGCheckRun] {
        guard let ref else {
            // No head SHA available (e.g. a non-GitHub source) — there is
            // genuinely nothing to fetch, not a failure.
            checksState = .loaded
            return []
        }
        checksState = .loading
        do {
            let runs = try await store.repoSource.checkRuns(owner: owner, repo: repo, ref: ref)
            checksState = .loaded
            return runs
        } catch {
            checksState = .error("Couldn’t load checks.")
            return []
        }
    }

    private func metaSection(for pr: HGPullRequest) -> some View {
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

    @ViewBuilder
    private var checksSection: some View {
        Section("Checks") {
            switch checksState {
            // .idle covers the first frame before `.task` has run at all —
            // grouping it with .loaded would flash (or, if `.task`'s guard
            // never fires, permanently show) "No checks reported" before
            // anything has actually been fetched.
            case .idle, .loading:
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Loading checks…").foregroundStyle(.secondary)
                }
            case .error(let msg):
                Label(msg, systemImage: "wifi.exclamationmark")
                    .font(.footnote).foregroundStyle(.orange)
            case .loaded:
                if checkRuns.isEmpty {
                    Text("No checks reported for this commit.").foregroundStyle(.secondary)
                } else {
                    LabeledContent("Overall") {
                        Theme.badge(text: checksSummary.label, color: checksSummary.badgeColor)
                    }
                    ForEach(checkRuns) { run in CheckRunRow(run: run) }
                }
            }
        }
    }
}

private extension HGChecksSummary {
    var badgeColor: Color {
        switch self {
        case .none: return .secondary
        case .pending: return .orange
        case .passing: return .green
        case .failing: return .red
        }
    }
}

struct CheckRunRow: View {
    let run: HGCheckRun
    var body: some View {
        HStack {
            Image(systemName: icon).foregroundStyle(color)
            Text(run.name).font(.subheadline)
            Spacer()
            if let url = run.detailsURL {
                Link(destination: url) {
                    Image(systemName: "arrow.up.right.square").foregroundStyle(.secondary)
                }
            }
        }
    }

    private var icon: String {
        guard run.status == .completed else { return "clock" }
        switch run.conclusion {
        case .success: return "checkmark.circle.fill"
        case .failure, .timedOut, .cancelled, .actionRequired, .startupFailure: return "xmark.circle.fill"
        default: return "minus.circle.fill"
        }
    }

    private var color: Color {
        guard run.status == .completed else { return .orange }
        switch run.conclusion {
        case .success: return .green
        case .failure, .timedOut, .cancelled, .actionRequired, .startupFailure: return .red
        default: return .secondary
        }
    }
}

struct FileChangeRow: View {
    let file: HGFileChange
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            if let patch = file.patch, !patch.isEmpty {
                PatchView(patch: patch)
            } else {
                Text("No diff available (binary file, too large, or unchanged).")
                    .font(.footnote).foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(file.path).font(.subheadline).lineLimit(2)
                HStack(spacing: 8) {
                    Theme.badge(text: file.status.rawValue, color: color(for: file.status))
                    Text("+\(file.additions) −\(file.deletions)").font(.caption.monospaced()).foregroundStyle(.secondary)
                }
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

/// Renders a unified diff patch, monospaced, with added/removed/hunk-header
/// lines colored — nice-to-have coloring over the plain patch text.
///
/// Built as ONE `Text`/`AttributedString` rather than a `Text` per line: a
/// `DisclosureGroup` inside a `List` row doesn't virtualize its content, so
/// a `ForEach` of per-line views would materialize every line of a large
/// diff synchronously (a lockfile-sized patch would visibly hang the UI).
/// Also caps rendering at `maxRenderedLines` as a safety net against
/// pathologically large generated-file diffs.
private struct PatchView: View {
    let patch: String
    private static let maxRenderedLines = 1000

    // Computed once per `patch` value (via `.task(id:)`, keyed on the patch
    // itself so it never re-runs for a `patch` that hasn't changed) rather
    // than inline in `body` — `body` re-evaluates on any state/environment
    // change while this row is on screen, and re-splitting + re-coloring up
    // to 1000 lines on every one of those passes is wasted, avoidable work.
    @State private var rendered: AttributedString?
    @State private var truncationNotice: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 4) {
                if let rendered {
                    Text(rendered).font(Theme.mono)
                }
                if let truncationNotice {
                    Text(truncationNotice).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
        .task(id: patch) { render() }
    }

    private func render() {
        let lines = patch.split(separator: "\n", omittingEmptySubsequences: false)
        let shown = lines.prefix(Self.maxRenderedLines)
        rendered = Self.colored(shown)
        truncationNotice = lines.count > shown.count
            ? "Diff truncated — showing the first \(shown.count) of \(lines.count) lines."
            : nil
    }

    private static func colored(_ lines: some Collection<Substring>) -> AttributedString {
        var result = AttributedString()
        for (index, line) in lines.enumerated() {
            var attributedLine = AttributedString(String(line))
            attributedLine.foregroundColor = color(for: line)
            result += attributedLine
            if index < lines.count - 1 { result += AttributedString("\n") }
        }
        return result
    }

    /// GitHub's per-file `patch` field starts at the first `@@` hunk header
    /// and never contains `+++`/`---` file-header lines (the file identity
    /// is already known from `filename`), so those aren't checked here — a
    /// real content line that happens to start with `++`/`--` (e.g. `++i;`
    /// or a `-- comment`) would otherwise be miscategorized as a header.
    private static func color(for line: Substring) -> Color {
        if line.hasPrefix("+") { return .green }
        if line.hasPrefix("-") { return .red }
        if line.hasPrefix("@@") { return Theme.tint }
        return .primary
    }
}

private extension Color {
    func mix(deletion: Bool) -> Color { deletion ? .red : self }
}
