// CacheStore — local-first persistence protocol (SPEC §2 / issue #4).
// MemoryCacheStore now; a SwiftData-backed store lands with issue #4.
import Foundation

public protocol CacheStore: Sendable {
    func repositories() async -> [HGRepo]
    func setRepositories(_ repos: [HGRepo]) async

    func fileTree(owner: String, repo: String) async -> [HGFileEntry]
    func setFileTree(_ entries: [HGFileEntry], owner: String, repo: String) async

    func pullRequests(owner: String, repo: String) async -> [HGPullRequest]
    func setPullRequests(_ prs: [HGPullRequest], owner: String, repo: String) async

    func issues(owner: String, repo: String) async -> [HGIssue]
    func setIssues(_ issues: [HGIssue], owner: String, repo: String) async

    func tickets(source: String) async -> [HGTicket]
    func setTickets(_ tickets: [HGTicket], source: String) async
}

public actor MemoryCacheStore: CacheStore {
    private var repos: [HGRepo] = []
    private var trees: [String: [HGFileEntry]] = [:]
    private var prs: [String: [HGPullRequest]] = [:]
    private var issuesByRepo: [String: [HGIssue]] = [:]
    private var ticketsBySource: [String: [HGTicket]] = [:]

    public init() {}

    private func key(owner: String, repo: String) -> String { "\(owner)/\(repo)" }

    public func repositories() async -> [HGRepo] { repos }
    public func setRepositories(_ repos: [HGRepo]) async { self.repos = repos }

    public func fileTree(owner: String, repo: String) async -> [HGFileEntry] { trees[key(owner: owner, repo: repo)] ?? [] }
    public func setFileTree(_ entries: [HGFileEntry], owner: String, repo: String) async {
        trees[key(owner: owner, repo: repo)] = entries
    }

    public func pullRequests(owner: String, repo: String) async -> [HGPullRequest] { prs[key(owner: owner, repo: repo)] ?? [] }
    public func setPullRequests(_ prs: [HGPullRequest], owner: String, repo: String) async {
        self.prs[key(owner: owner, repo: repo)] = prs
    }

    public func issues(owner: String, repo: String) async -> [HGIssue] { issuesByRepo[key(owner: owner, repo: repo)] ?? [] }
    public func setIssues(_ issues: [HGIssue], owner: String, repo: String) async {
        issuesByRepo[key(owner: owner, repo: repo)] = issues
    }

    public func tickets(source: String) async -> [HGTicket] { ticketsBySource[source] ?? [] }
    public func setTickets(_ tickets: [HGTicket], source: String) async {
        ticketsBySource[source] = tickets
    }
}
