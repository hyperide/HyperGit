// ScreenshotHarness — renders HyperGit's shared SwiftUI screens to PNG so PRs can be
// visually reviewed WITHOUT Xcode.app or an iOS Simulator. Only the Swift toolchain
// that ships with Command Line Tools is required.
//
// Views are the real production code (symlinked in from ../../App/Views and
// ../../App/Theme — never copied, so they can't drift). Only the data comes from this
// file, built from the app's own PreviewRepositorySource / PreviewTicketSource /
// *.samples mock data (already used by SwiftUI Previews and unit tests — see
// Sources/HyperGitCore/Models/Samples.swift and
// Sources/HyperGitCore/Clients/RepositorySource.swift).
//
// Two things needed hand-holding vs. a naive `ImageRenderer(content:).cgImage`:
//
// 1. `List`-backed screens (which is most of this app: repos, tickets, PRs, issues,
//    file tree) render as a "content unavailable" placeholder glyph when the SwiftUI
//    hosting view is never attached to a real window — `ImageRenderer` snapshots it
//    before AppKit ever lays out the native NSTableView backing that `List` uses.
//    Confirmed NOT sandbox-related (identical broken output with the sandbox
//    disabled). Fix: host the view in a real (off-screen, positioned far outside any
//    display) `NSWindow`, force a layout + display pass, then snapshot via
//    `NSView.cacheDisplay(in:to:)` instead of `ImageRenderer`. Plain declarative
//    content (Text, VStack, …) also works fine through this path, so it's the only
//    render function here.
//
// 2. Views are populated with hand-set store state rather than relying on their
//    `.task { … }` load-on-appear modifiers, which need a running async task tied to
//    view identity that a one-shot headless render doesn't reliably drive. Note
//    `RepoDetailView` still runs its (synchronous) `.onAppear` handler, which calls
//    `AppStore.select(_:)` and resets fileTree/pullRequests/issues/commits to empty —
//    that's real production behavior (the same thing happens navigating into a repo in
//    the live app before the fetch completes), not a harness bug.
//
// Usage:
//   swift run --package-path mobile/Tools/ScreenshotHarness ScreenshotHarness [outputDir]
// Defaults outputDir to ./screenshots relative to the package's cwd.
import AppKit
import SwiftUI
import HyperGitCore

enum HarnessError: Error, CustomStringConvertible {
    case renderFailed(String)
    case encodeFailed(String)

    var description: String {
        switch self {
        case .renderFailed(let name): return "Could not produce a CGImage for '\(name)'"
        case .encodeFailed(let name): return "Could not encode PNG data for '\(name)'"
        }
    }
}

@MainActor
func makeSampleStore() -> AppStore {
    let sampleIssues: [HGIssue] = [
        HGIssue(
            id: 501, number: 42, title: "Offline cache drops stale entries on cold start",
            body: "Repro: kill app while offline, relaunch — repo list is empty for ~2s.",
            state: .open,
            author: HGUser(id: 7, login: "agent", name: "HyperGit Agent", avatarURL: nil, htmlURL: nil),
            assignees: [], labels: [HGLabel(id: 1, name: "bug", color: "d73a4a")],
            commentsCount: 3, createdAt: Date(timeIntervalSinceNow: -86400),
            updatedAt: Date(timeIntervalSinceNow: -3600), htmlURL: nil
        ),
    ]

    let store = AppStore(
        repoSource: PreviewRepositorySource(
            repos: HGRepo.samples,
            prs: HGPullRequest.samples,
            issues: sampleIssues
        ),
        ticketSources: [PreviewTicketSource()]
    )

    // Populate state directly — a headless render never triggers `.task {}`.
    store.repositories = HGRepo.samples
    store.reposState = .loaded
    store.pullRequests = HGPullRequest.samples
    store.prsState = .loaded
    store.issues = sampleIssues
    store.issuesState = .loaded
    store.tickets = HGTicket.samples
    store.ticketsState = .loaded
    store.selectedRepo = HGRepo.samples.first
    store.fileTree = [
        HGFileEntry(path: "README.md", name: "README.md", sha: "abc", size: 512, kind: .file),
        HGFileEntry(path: "Sources", name: "Sources", sha: "def", size: nil, kind: .dir),
    ]
    store.commits = []
    return store
}

/// Renders `content` to a PNG at `outputDir/<name>.png`. Hosts the view in a real,
/// off-screen `NSWindow` so native List/Table backing lays out correctly — see the
/// file header for why a bare `ImageRenderer(content:).cgImage` is not enough here.
@MainActor
func render(name: String, size: CGSize, outputDir: URL, @ViewBuilder content: () -> some View) throws {
    let framed = content()
        .frame(width: size.width, height: size.height)
        .background(Color(.windowBackgroundColor))
        .environment(\.colorScheme, .light)

    let hosting = NSHostingView(rootView: framed)
    hosting.frame = NSRect(origin: .zero, size: size)

    let window = NSWindow(
        contentRect: NSRect(origin: CGPoint(x: -10000, y: -10000), size: size),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    window.contentView = hosting
    window.orderFrontRegardless() // must actually be ordered in for AppKit to lay out List/NSTableView
    hosting.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.05)) // let one display pass complete

    guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
        window.orderOut(nil)
        throw HarnessError.renderFailed(name)
    }
    rep.size = hosting.bounds.size
    hosting.cacheDisplay(in: hosting.bounds, to: rep)
    window.orderOut(nil)

    guard let cgImage = rep.cgImage else {
        throw HarnessError.renderFailed(name)
    }
    guard let pngData = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else {
        throw HarnessError.encodeFailed(name)
    }
    let url = outputDir.appendingPathComponent("\(name).png")
    try pngData.write(to: url)
    print("wrote \(url.path) (\(cgImage.width)x\(cgImage.height) px)")
}

@main
struct ScreenshotHarness {
    static func main() async throws {
        let outputDir = URL(fileURLWithPath: CommandLine.arguments.count > 1
            ? CommandLine.arguments[1]
            : "screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        await MainActor.run {
            // A real (even off-screen) NSApplication + window-server connection is
            // required for List/NSTableView-backed views to lay out correctly.
            _ = NSApplication.shared
            NSApp.setActivationPolicy(.accessory)

            let store = makeSampleStore()
            let phoneSize = CGSize(width: 390, height: 844) // iPhone 14/15 point size

            let screens: [(name: String, view: AnyView)] = [
                ("repos_list", AnyView(ReposView().environment(store))),
                ("tickets_list", AnyView(TicketsView().environment(store))),
                ("pull_requests_list", AnyView(PullRequestsView().environment(store))),
                ("issues_list", AnyView(IssuesView().environment(store))),
                ("file_tree", AnyView(FileTreeView(branch: "main").environment(store))),
                ("repo_detail", AnyView(RepoDetailView(repo: HGRepo.samples[0]).environment(store))),
            ]

            var failures: [String] = []
            for screen in screens {
                do {
                    try render(name: screen.name, size: phoneSize, outputDir: outputDir) { screen.view }
                } catch {
                    failures.append("\(screen.name): \(error)")
                }
            }

            if failures.isEmpty {
                print("All \(screens.count) screenshots written to \(outputDir.path)")
            } else {
                print("FAILURES:")
                for failure in failures { print("  - \(failure)") }
            }
        }
    }
}
