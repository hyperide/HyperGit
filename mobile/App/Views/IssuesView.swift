// Issues list + detail for the selected repo.
import SwiftUI
import HyperGitCore

struct IssuesView: View {
    @Environment(AppStore.self) private var store
    @State private var state: HGIssue.State = .open

    var body: some View {
        Group {
            switch store.issuesState {
            case .loading where store.issues.isEmpty:
                ProgressView("Loading issues…").frame(maxWidth: .infinity, maxHeight: .infinity)
            case .error(let msg) where store.issues.isEmpty:
                PlaceholderView(icon: "exclamationmark.triangle", title: "Couldn’t load", subtitle: msg)
            default:
                if store.issues.isEmpty {
                    PlaceholderView(icon: "smallcircle.filled.circle", title: "No issues", subtitle: "")
                } else {
                    List(store.issues) { issue in
                        NavigationLink(value: issue) {
                            IssueRow(issue: issue)
                        }
                    }
                    .refreshable { await store.loadIssues(state: state) }
                    .safeAreaInset(edge: .top) {
                        if let reason = store.issuesStaleReason { OfflineBanner(reason: reason) }
                    }
                }
            }
        }
        // Registered unconditionally (not nested inside the non-empty
        // branch above): a pushed detail view must keep resolving even if
        // `store.issues` later becomes empty or errors on a refresh.
        .navigationDestination(for: HGIssue.self) { issue in
            IssueDetailView(issue: issue)
        }
        .task(id: state) { await store.loadIssues(state: state) }
    }
}

struct IssueRow: View {
    let issue: HGIssue
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(issue.title).font(.body.weight(.semibold)).lineLimit(2)
            HStack(spacing: 8) {
                Text("#\(issue.number)").font(.caption).foregroundStyle(.secondary)
                Theme.badge(text: issue.state.rawValue,
                            color: issue.state == .open ? .green : .purple)
                ForEach(issue.labels.prefix(3)) { label in
                    Theme.badge(text: label.name, color: Color(hex: label.color))
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct IssueDetailView: View {
    let issue: HGIssue

    var body: some View {
        List {
            headerSection
            if let body = issue.body, !body.isEmpty {
                Section("Description") {
                    Text(body).font(.body)
                }
            }
            metaSection
            if let url = issue.htmlURL {
                Section {
                    Link("Open on GitHub", destination: url)
                }
            }
        }
        .navigationTitle("Issue #\(issue.number)")
        .inlineNavigationBarTitle()
    }

    private var headerSection: some View {
        Section {
            Text(issue.title).font(.headline)
            HStack(spacing: 8) {
                Theme.badge(text: issue.state.rawValue, color: issue.state == .open ? .green : .purple)
                if let author = issue.author {
                    Text("by \(author.displayName)").font(.caption).foregroundStyle(.secondary)
                }
            }
            if !issue.labels.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(issue.labels) { label in
                            Theme.badge(text: label.name, color: Color(hex: label.color))
                        }
                    }
                }
            }
        }
    }

    private var metaSection: some View {
        Section {
            LabeledContent("Comments", value: "\(issue.commentsCount)")
            if !issue.assignees.isEmpty {
                LabeledContent("Assignees", value: issue.assignees.map(\.displayName).joined(separator: ", "))
            }
            if let created = issue.createdAt {
                LabeledContent("Opened", value: created.formatted(.relative(presentation: .named)))
            }
            if let updated = issue.updatedAt {
                LabeledContent("Updated", value: updated.formatted(.relative(presentation: .named)))
            }
        }
    }
}

private extension Color {
    /// GitHub label colors are 6-digit hex without '#'.
    init(hex: String) {
        let cleaned = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        var rgb: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&rgb)
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}
