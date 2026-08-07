// CacheStore — local-first persistence protocol (SPEC §2 / issue #4).
// MemoryCacheStore below is the process-lifetime implementation used by default in
// tests/previews; SwiftDataCacheStore (Cache/SwiftDataCacheStore.swift) is the
// persistent, on-disk implementation the real app wires up.
import Foundation

public protocol CacheStore: Sendable {
    func repositories() async -> [HGRepo]
    func setRepositories(_ repos: [HGRepo]) async

    // `branch` is part of the cache key: RepositorySource.fileTree fetches per-branch,
    // so collapsing branches into one slot would let a fetch of branch A silently serve
    // branch B's cached tree under an offline fallback.
    func fileTree(owner: String, repo: String, branch: String) async -> [HGFileEntry]
    func setFileTree(_ entries: [HGFileEntry], owner: String, repo: String, branch: String) async

    // `state` is part of the cache key, not just the fetch: a persistent store that
    // collapsed "open" and "closed" into one slot would silently serve the wrong list
    // under a stale-offline fallback (fetch "open", get back cached "closed").
    func pullRequests(owner: String, repo: String, state: HGPullRequest.State) async -> [HGPullRequest]
    func setPullRequests(_ prs: [HGPullRequest], owner: String, repo: String, state: HGPullRequest.State) async

    func issues(owner: String, repo: String, state: HGIssue.State) async -> [HGIssue]
    func setIssues(_ issues: [HGIssue], owner: String, repo: String, state: HGIssue.State) async

    func tickets(source: String) async -> [HGTicket]
    func setTickets(_ tickets: [HGTicket], source: String) async

    /// Wipes all cached data. Not wired to a sign-out flow yet — the app has no
    /// explicit sign-out UI to hook it into today — but the primitive needs to exist so
    /// that work isn't blocked on a CacheStore protocol change of its own. Tracked as a
    /// follow-up: cached private repo/PR/issue/ticket data currently outlives a cleared
    /// token.
    func clearAll() async
}

public actor MemoryCacheStore: CacheStore {
    private var repos: [HGRepo] = []
    private var trees: [String: [HGFileEntry]] = [:]
    private var prs: [String: [HGPullRequest]] = [:]
    private var issuesByRepo: [String: [HGIssue]] = [:]
    private var ticketsBySource: [String: [HGTicket]] = [:]

    public init() {}

    private func key(owner: String, repo: String, branch: String) -> String { "\(owner)/\(repo)/\(branch)" }
    private func key(owner: String, repo: String, state: HGPullRequest.State) -> String { "\(owner)/\(repo)/\(state.rawValue)" }
    private func key(owner: String, repo: String, state: HGIssue.State) -> String { "\(owner)/\(repo)/\(state.rawValue)" }

    public func repositories() async -> [HGRepo] { repos }
    public func setRepositories(_ repos: [HGRepo]) async { self.repos = repos }

    public func fileTree(owner: String, repo: String, branch: String) async -> [HGFileEntry] {
        trees[key(owner: owner, repo: repo, branch: branch)] ?? []
    }
    public func setFileTree(_ entries: [HGFileEntry], owner: String, repo: String, branch: String) async {
        trees[key(owner: owner, repo: repo, branch: branch)] = entries
    }

    public func pullRequests(owner: String, repo: String, state: HGPullRequest.State) async -> [HGPullRequest] {
        prs[key(owner: owner, repo: repo, state: state)] ?? []
    }
    public func setPullRequests(_ prs: [HGPullRequest], owner: String, repo: String, state: HGPullRequest.State) async {
        self.prs[key(owner: owner, repo: repo, state: state)] = prs
    }

    public func issues(owner: String, repo: String, state: HGIssue.State) async -> [HGIssue] {
        issuesByRepo[key(owner: owner, repo: repo, state: state)] ?? []
    }
    public func setIssues(_ issues: [HGIssue], owner: String, repo: String, state: HGIssue.State) async {
        issuesByRepo[key(owner: owner, repo: repo, state: state)] = issues
    }

    public func tickets(source: String) async -> [HGTicket] { ticketsBySource[source] ?? [] }
    public func setTickets(_ tickets: [HGTicket], source: String) async {
        ticketsBySource[source] = tickets
    }

    public func clearAll() async {
        repos = []
        trees = [:]
        prs = [:]
        issuesByRepo = [:]
        ticketsBySource = [:]
    }
}
