// RepositorySource — the backend-agnostic protocol for repository data.
// Implemented by GitHubClient today; a HyperGitClient later (SPEC §2.4). UI and
// store depend only on this protocol so the backend can be swapped.
import Foundation

public protocol RepositorySource: Sendable {
    func currentUser() async throws -> HGUser
    func repositories() async throws -> [HGRepo]
    func fileTree(owner: String, repo: String, branch: String?) async throws -> [HGFileEntry]
    func fileContent(owner: String, repo: String, path: String, ref: String?) async throws -> HGFileContent
    func pullRequests(owner: String, repo: String, state: HGPullRequest.State) async throws -> [HGPullRequest]
    func pullRequest(owner: String, repo: String, number: Int) async throws -> HGPullRequest
    func pullRequestFiles(owner: String, repo: String, number: Int) async throws -> [HGFileChange]
    func commits(owner: String, repo: String, branch: String?) async throws -> [HGCommit]
    func issues(owner: String, repo: String, state: HGIssue.State) async throws -> [HGIssue]
    func issue(owner: String, repo: String, number: Int) async throws -> HGIssue
}

/// Source-agnostic factory for previews/tests: returns canned data, never networks.
public struct PreviewRepositorySource: RepositorySource {
    public let user: HGUser
    public let repos: [HGRepo]
    public let prs: [HGPullRequest]
    public let issues: [HGIssue]

    public init(
        user: HGUser = HGUser(id: 1, login: "hyperide", name: "HyperGit", avatarURL: nil, htmlURL: nil),
        repos: [HGRepo] = HGRepo.samples,
        prs: [HGPullRequest] = [],
        issues: [HGIssue] = []
    ) {
        self.user = user
        self.repos = repos
        self.prs = prs
        self.issues = issues
    }

    public func currentUser() async throws -> HGUser { user }
    public func repositories() async throws -> [HGRepo] { repos }
    public func fileTree(owner: String, repo: String, branch: String?) async throws -> [HGFileEntry] {
        [HGFileEntry(path: "README.md", name: "README.md", sha: "abc", size: 12, kind: .file)]
    }
    public func fileContent(owner: String, repo: String, path: String, ref: String?) async throws -> HGFileContent {
        HGFileContent(path: path, sha: "abc", size: 12, encoding: .utf8, raw: Data("# HyperGit\n".utf8))
    }
    public func pullRequests(owner: String, repo: String, state: HGPullRequest.State) async throws -> [HGPullRequest] { prs }
    public func pullRequest(owner: String, repo: String, number: Int) async throws -> HGPullRequest {
        prs.first ?? HGPullRequest.samples[0]
    }
    public func pullRequestFiles(owner: String, repo: String, number: Int) async throws -> [HGFileChange] { [] }
    public func commits(owner: String, repo: String, branch: String?) async throws -> [HGCommit] { [] }
    public func issues(owner: String, repo: String, state: HGIssue.State) async throws -> [HGIssue] { issues }
    public func issue(owner: String, repo: String, number: Int) async throws -> HGIssue {
        issues.first ?? HGIssue(id: 1, number: number, title: "Sample issue", body: nil,
                                state: .open, author: nil, assignees: [], labels: [],
                                commentsCount: 0, createdAt: nil, updatedAt: nil, htmlURL: nil)
    }
}
