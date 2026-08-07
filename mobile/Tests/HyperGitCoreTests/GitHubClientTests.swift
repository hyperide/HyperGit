// Tests exercise real production logic: GitHubClient decoding, mapping, pagination
// and error propagation via an injected transport returning canned JSON + headers.
// No network, no mock self-testing.
import Testing
import Foundation
@testable import HyperGitCore

@Suite("GitHubClient parsing + pagination")
struct GitHubClientTests {
    /// Closure-based router: given a request path, return (body, headers). Used so
    /// pagination tests can return a `Link` header and distinct page-2 data.
    private func client(_ router: @escaping @Sendable (String) -> (Data, [String: String])) -> GitHubClient {
        GitHubClient(tokenProvider: { "t" }, transport: { path, _ in router(path) })
    }
    /// Prefix-routed client for single-page cases (no Link header).
    private func routedClient(_ routes: [String: Data]) -> GitHubClient {
        client { path in
            for (prefix, data) in routes where path.hasPrefix(prefix) { return (data, [:]) }
            return (Data("[]".utf8), [:])
        }
    }

    @Test("repos list maps to HGRepo with owner/login accessor")
    func reposMapping() async throws {
        let json = Data(#"""
        [{
          "id": 1, "name": "HyperGit", "full_name": "hyperide/HyperGit",
          "owner": {"id": 99, "login": "hyperide", "name": "Org", "avatar_url": null, "html_url": null},
          "description": "d", "private": false, "default_branch": "main",
          "stargazers_count": 5, "forks_count": 1, "open_issues_count": 2,
          "updated_at": "2024-01-02T03:04:05Z", "ssh_url": null, "clone_url": null,
          "html_url": "https://github.com/hyperide/HyperGit", "language": "Swift"
        }]
        """#.utf8)
        let c = routedClient(["user/repos": json])
        let repos = try await c.repositories()
        #expect(repos.count == 1)
        #expect(repos[0].fullName == "hyperide/HyperGit")
        #expect(repos[0].ownerLogin == "hyperide")
        #expect(repos[0].isPrivate == false)
        #expect(repos[0].updatedAt != nil)
    }

    @Test("issues endpoint drops pull-request entries")
    func issuesFilterPRs() async throws {
        let json = Data(#"""
        [
          {"id": 1, "number": 1, "title": "real issue", "body": null, "state": "open",
           "user": null, "assignees": [], "labels": [], "comments": 0,
           "created_at": null, "updated_at": null, "html_url": null, "pull_request": null},
          {"id": 2, "number": 2, "title": "this is a PR", "body": null, "state": "open",
           "user": null, "assignees": [], "labels": [], "comments": 0,
           "created_at": null, "updated_at": null, "html_url": null,
           "pull_request": {"url": "x"}}
        ]
        """#.utf8)
        let c = routedClient(["repos/hyperide/HyperGit/issues": json])
        let issues = try await c.issues(owner: "hyperide", repo: "HyperGit", state: .open)
        #expect(issues.count == 1)
        #expect(issues.first?.number == 1)
    }

    @Test("pull request list tolerates absent diff stats (default 0)")
    func pullRequestListDefaults() async throws {
        let json = Data(#"""
        [{"id": 10, "number": 1, "title": "PR", "body": null, "state": "open",
          "draft": false, "merged": false, "user": null, "head": {"ref": "f"}, "base": {"ref": "main"},
          "comments": 1, "created_at": "2024-01-01T00:00:00Z", "updated_at": "2024-01-01T00:00:00Z",
          "merged_at": null, "html_url": null}]
        """#.utf8)
        let c = routedClient(["repos/hyperide/HyperGit/pulls": json])
        let prs = try await c.pullRequests(owner: "hyperide", repo: "HyperGit", state: .open)
        #expect(prs.count == 1)
        #expect(prs[0].additions == 0)
        #expect(prs[0].head == "f")
        #expect(prs[0].base == "main")
    }

    @Test("git tree maps blob/tree kinds and skips unknown")
    func treeMapping() async throws {
        let json = Data(#"""
        {"tree": [
          {"path": "README.md", "type": "blob", "sha": "a", "size": 10},
          {"path": "src", "type": "tree", "sha": "b", "size": null},
          {"path": "x", "type": "weird", "sha": "c", "size": null}
        ], "truncated": false}
        """#.utf8)
        let c = routedClient(["repos/hyperide/HyperGit/git/trees": json])
        let entries = try await c.fileTree(owner: "hyperide", repo: "HyperGit", branch: "main")
        #expect(entries.count == 2)
        #expect(entries.contains { $0.kind == .dir && $0.name == "src" })
        #expect(entries.contains { $0.kind == .file && $0.name == "README.md" })
    }

    @Test("file content base64 is decoded to real text")
    func fileContentBase64() async throws {
        // "Hello" → base64 "SGVsbG8="
        let json = Data(#"""
        {"path": "a.txt", "sha": "s", "size": 5, "encoding": "base64", "content": "SGVsbG8="}
        """#.utf8)
        let c = routedClient(["repos/o/r/contents": json])
        let file = try await c.fileContent(owner: "o", repo: "r", path: "a.txt", ref: nil)
        #expect(file.text == "Hello")
        #expect(file.encoding == .utf8)
    }

    @Test("pull request files map status + patch (diff)")
    func pullRequestFilesPatch() async throws {
        let json = Data(#"""
        [{"filename": "src/a.swift", "previous_filename": null, "status": "modified",
          "additions": 2, "deletions": 1,
          "patch": "@@ -1,1 +1,2 @@\n-old\n+new\n+code"}]
        """#.utf8)
        let c = routedClient(["repos/o/r/pulls/1/files": json])
        let files = try await c.pullRequestFiles(owner: "o", repo: "r", number: 1)
        #expect(files.count == 1)
        #expect(files[0].path == "src/a.swift")
        #expect(files[0].status == .modified)
        #expect(files[0].additions == 2)
        #expect(files[0].patch?.contains("+new") == true)
    }

    @Test("commits map subject, shortSHA and author login")
    func commitsParsing() async throws {
        let json = Data(#"""
        [{"sha": "abcdef1234", "commit": {"message": "feat: x\n\nBody line.", "author": {"name": "n", "date": "2024-01-01T00:00:00Z"}},
          "author": {"id": 1, "login": "octo", "name": null, "avatar_url": null, "html_url": null},
          "html_url": null}]
        """#.utf8)
        let c = routedClient(["repos/o/r/commits": json])
        let commits = try await c.commits(owner: "o", repo: "r", branch: nil)
        #expect(commits.count == 1)
        #expect(commits[0].subject == "feat: x")
        #expect(commits[0].shortSHA == "abcdef1")
        #expect(commits[0].authorLogin == "octo")
    }

    @Test("issue detail maps a single issue")
    func issueDetail() async throws {
        let json = Data(#"""
        {"id": 42, "number": 7, "title": "Bug", "body": "desc", "state": "open",
         "user": null, "assignees": [], "labels": [], "comments": 0,
         "created_at": null, "updated_at": null, "html_url": null, "pull_request": null}
        """#.utf8)
        let c = routedClient(["repos/o/r/issues/7": json])
        let issue = try await c.issue(owner: "o", repo: "r", number: 7)
        #expect(issue.number == 7)
        #expect(issue.title == "Bug")
        #expect(issue.body == "desc")
    }

    @Test("currentUser maps the /user payload")
    func currentUser() async throws {
        let json = Data(#"""
        {"id": 1, "login": "octocat", "name": "The Octocat",
         "avatar_url": "https://x/a.png", "html_url": "https://github.com/octocat"}
        """#.utf8)
        let c = routedClient(["user": json])
        let user = try await c.currentUser()
        #expect(user.login == "octocat")
        #expect(user.displayName == "The Octocat")
        #expect(user.avatarURL?.absoluteString == "https://x/a.png")
    }

    // MARK: Pagination (pure parser + end-to-end)

    @Test("nextLink parses rel=next and returns a relative path; nil otherwise")
    func nextLinkParser() {
        let withNext = #"<https://api.github.com/user/repos?page=2>; rel="next", <https://api.github.com/user/repos?page=5>; rel="last""#
        #expect(GitHubClient.nextLink(from: withNext) == "user/repos?page=2")
        let onlyLast = #"<https://api.github.com/user/repos?page=5>; rel="last""#
        #expect(GitHubClient.nextLink(from: onlyLast) == nil)
        #expect(GitHubClient.nextLink(from: "") == nil)
    }

    @Test("list calls follow the Link rel=next to accumulate pages")
    func paginationFollowsLink() async throws {
        let page1 = Data(#"""
        [{"id": 1, "name": "a", "full_name": "o/a", "owner": {"id": 1, "login": "o", "name": null, "avatar_url": null, "html_url": null},
          "description": null, "private": false, "default_branch": "main", "stargazers_count": 0,
          "forks_count": 0, "open_issues_count": 0, "updated_at": null, "ssh_url": null, "clone_url": null, "html_url": null, "language": null}]
        """#.utf8)
        let page2 = Data(#"""
        [{"id": 2, "name": "b", "full_name": "o/b", "owner": {"id": 1, "login": "o", "name": null, "avatar_url": null, "html_url": null},
          "description": null, "private": false, "default_branch": "main", "stargazers_count": 0,
          "forks_count": 0, "open_issues_count": 0, "updated_at": null, "ssh_url": null, "clone_url": null, "html_url": null, "language": null}]
        """#.utf8)
        let c = client { path in
            if path.contains("page=2") { return (page2, [:]) }
            return (page1, ["link": #"<https://api.github.com/user/repos?page=2>; rel="next""#])
        }
        let repos = try await c.repositories()
        #expect(repos.map(\.name).sorted() == ["a", "b"])
    }

    @Test("expired OAuth token uses async refresh provider")
    func expiredOAuthUsesRefreshProvider() async throws {
        let host = "refresh.github.test"
        gitHubAuthorizationRecorder.reset(host: host)
        let tokenStore = InMemoryTokenStore()
        try tokenStore.setOAuthTokens(
            OAuthTokens(
                accessToken: "expired-oauth-token",
                refreshToken: "refresh-token",
                expiresAt: Date(timeIntervalSince1970: 0)
            ),
            for: .github
        )

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GitHubAuthorizationURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = GitHubClient(
            baseURL: URL(string: "https://\(host)")!,
            tokenProvider: { nil },
            oauthAccessTokenProvider: { "refreshed-github-token" },
            session: session,
            tokenStore: tokenStore
        )

        _ = try await client.repositories()

        let authorizations = gitHubAuthorizationRecorder.authorizations(host: host)
        #expect(authorizations == ["Bearer refreshed-github-token"])
    }

    @Test("manual PAT takes precedence over refreshable OAuth token")
    func manualPATPrecedenceOverRefreshableOAuth() async throws {
        let host = "manual.github.test"
        gitHubAuthorizationRecorder.reset(host: host)
        let tokenStore = InMemoryTokenStore()
        try tokenStore.setOAuthTokens(
            OAuthTokens(
                accessToken: "expired-oauth-token",
                refreshToken: "refresh-token",
                expiresAt: Date(timeIntervalSince1970: 0)
            ),
            for: .github
        )

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GitHubAuthorizationURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = GitHubClient(
            baseURL: URL(string: "https://\(host)")!,
            tokenProvider: { "manual-github-token" },
            oauthAccessTokenProvider: { "refreshed-github-token" },
            session: session,
            tokenStore: tokenStore
        )

        _ = try await client.repositories()

        let authorizations = gitHubAuthorizationRecorder.authorizations(host: host)
        #expect(authorizations == ["Bearer manual-github-token"])
    }

    @Test("transport errors propagate (e.g. 401 → unauthorized)")
    func errorPropagation() async {
        let c = GitHubClient(tokenProvider: { "t" }, transport: { _, _ in throw HTTPError.unauthorized })
        var caught: Error?
        do { _ = try await c.repositories() } catch { caught = error }
        #expect((caught as? HTTPError) == .unauthorized)
    }
}

private let gitHubAuthorizationRecorder = GitHubAuthorizationRecorder()

private final class GitHubAuthorizationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: [String?]] = [:]

    func reset(host: String) {
        lock.lock()
        defer { lock.unlock() }
        values[host] = []
    }

    func record(_ authorization: String?, host: String) {
        lock.lock()
        defer { lock.unlock() }
        values[host, default: []].append(authorization)
    }

    func authorizations(host: String) -> [String?] {
        lock.lock()
        defer { lock.unlock() }
        return values[host] ?? []
    }
}

private final class GitHubAuthorizationURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let authorization = request.value(forHTTPHeaderField: "Authorization")
        let host = request.url?.host ?? ""
        gitHubAuthorizationRecorder.record(authorization, host: host)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: [:]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.repositoriesData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static let repositoriesData = Data(#"""
    [{
      "id": 1, "name": "a", "full_name": "o/a",
      "owner": {"id": 1, "login": "o", "name": null, "avatar_url": null, "html_url": null},
      "description": null, "private": false, "default_branch": "main",
      "stargazers_count": 0, "forks_count": 0, "open_issues_count": 0,
      "updated_at": null, "ssh_url": null, "clone_url": null,
      "html_url": null, "language": null
    }]
    """#.utf8)
}
