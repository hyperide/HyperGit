// Tests exercise real production logic: GitHubClient decoding & mapping via an
// injected transport returning canned JSON. No network, no mock self-testing.
import Testing
import Foundation
@testable import HyperGitCore

@Suite("GitHubClient parsing")
struct GitHubClientTests {
    /// Route canned JSON by the leading path segment, mirroring GitHub's REST layout.
    private func client(_ routes: [String: Data]) -> GitHubClient {
        let transport: HTTPTransport = { path, _ in
            for (key, data) in routes where path.hasPrefix(key) { return data }
            throw HTTPError.notFound
        }
        return GitHubClient(tokenProvider: { "t" }, transport: transport)
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
        let c = client(["user/repos": json])
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
        let c = client(["repos/hyperide/HyperGit/issues": json])
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
        let c = client(["repos/hyperide/HyperGit/pulls": json])
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
        let c = client(["repos/hyperide/HyperGit/git/trees": json])
        let entries = try await c.fileTree(owner: "hyperide", repo: "HyperGit", branch: "main")
        #expect(entries.count == 2)
        #expect(entries.contains { $0.kind == .dir && $0.name == "src" })
        #expect(entries.contains { $0.kind == .file && $0.name == "README.md" })
    }
}
