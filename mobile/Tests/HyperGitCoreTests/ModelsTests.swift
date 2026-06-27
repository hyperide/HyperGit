import Testing
import Foundation
@testable import HyperGitCore

@Suite("Models")
struct ModelsTests {
    @Test("HGCommit subject strips body and shortSHA truncates")
    func commitHelpers() {
        let c = HGCommit(sha: "abcdef1234567890", message: "feat: add x\n\nBody line.", authorName: "n",
                         authorLogin: nil, authorAvatarURL: nil, date: nil, htmlURL: nil)
        #expect(c.shortSHA == "abcdef1")
        #expect(c.subject == "feat: add x")
    }

    @Test("HGFileContent utf8 decodes text")
    func fileContentUtf8() {
        let fc = HGFileContent(path: "a.txt", sha: "s", size: 5, encoding: .utf8, raw: Data("hello".utf8))
        #expect(fc.text == "hello")
    }

    @Test("HGUser displayName falls back to login when name empty")
    func userDisplayName() {
        let u = HGUser(id: 1, login: "octo", name: nil, avatarURL: nil, htmlURL: nil)
        #expect(u.displayName == "octo")
    }

    @Test("AppStore local-first fallback surfaces cache on network failure")
    func storeFallback() async {
        let cache = MemoryCacheStore()
        await cache.setRepositories(HGRepo.samples)
        // A source whose repositories() throws simulates an offline network.
        struct Failing: RepositorySource {
            func currentUser() async throws -> HGUser { throw HTTPError.invalidResponse }
            func repositories() async throws -> [HGRepo] { throw HTTPError.invalidResponse }
            func fileTree(owner: String, repo: String, branch: String?) async throws -> [HGFileEntry] { [] }
            func fileContent(owner: String, repo: String, path: String, ref: String?) async throws -> HGFileContent { throw HTTPError.invalidResponse }
            func pullRequests(owner: String, repo: String, state: HGPullRequest.State) async throws -> [HGPullRequest] { [] }
            func pullRequest(owner: String, repo: String, number: Int) async throws -> HGPullRequest { throw HTTPError.invalidResponse }
            func pullRequestFiles(owner: String, repo: String, number: Int) async throws -> [HGFileChange] { [] }
            func commits(owner: String, repo: String, branch: String?) async throws -> [HGCommit] { [] }
            func issues(owner: String, repo: String, state: HGIssue.State) async throws -> [HGIssue] { [] }
        }
        let store = await AppStore(repoSource: Failing(), cache: cache)
        await store.loadRepositories()
        // MARK: assertion below — main-actor isolated via await.
        await MainActor.run {
            #expect(store.repositories.map(\.fullName) == HGRepo.samples.map(\.fullName))
            #expect(store.reposState == .loaded)
        }
    }
}
