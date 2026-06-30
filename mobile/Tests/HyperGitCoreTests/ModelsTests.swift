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
            func issue(owner: String, repo: String, number: Int) async throws -> HGIssue { throw HTTPError.invalidResponse }
        }
        let store = await AppStore(repoSource: Failing(), cache: cache)
        await store.loadRepositories()
        // MARK: assertion below — main-actor isolated via await.
        await MainActor.run {
            #expect(store.repositories.map(\.fullName) == HGRepo.samples.map(\.fullName))
            #expect(store.reposState == .loaded)
        }
    }

    @Test("AppStore keeps partial ticket results when pagination limit is hit")
    func storeKeepsPartialTickets() async {
        let partial = Self.ticket(
            id: "linear-1",
            identifier: "ENG-1",
            title: "Partial",
            updatedAt: Date(timeIntervalSince1970: 2)
        )
        let cachedBeyondLimit = Self.ticket(
            id: "linear-2",
            identifier: "ENG-2",
            title: "Cached beyond limit",
            updatedAt: Date(timeIntervalSince1970: 1)
        )

        struct Partial: TicketSource {
            var displayName: String { "Linear" }
            let ticketsToReturn: [HGTicket]

            func tickets() async throws -> [HGTicket] {
                throw LinearClientError.paginationLimitExceeded(maxPages: 1, partialTickets: ticketsToReturn)
            }
        }

        let cache = MemoryCacheStore()
        await cache.setTickets([Self.ticket(id: "linear-1", identifier: "ENG-1", title: "Old partial"), cachedBeyondLimit], source: "Linear")
        let store = await AppStore(ticketSources: [Partial(ticketsToReturn: [partial])], cache: cache)
        await store.loadTickets()

        await MainActor.run {
            #expect(store.tickets.map(\.id) == ["linear-1", "linear-2"])
            #expect(store.tickets.first?.title == "Partial")
            #expect(store.ticketsState == .error("Loaded 1 Linear tickets from the first 1 pages."))
        }

        let cached = await cache.tickets(source: "Linear")
        #expect(cached.map(\.id) == ["linear-1", "linear-2"])
        #expect(cached.first?.title == "Partial")
    }

    @Test("AppStore ignores missing credentials for optional ticket sources when another source loads")
    func optionalTicketSourceUnauthorizedDoesNotPoisonLoadedTickets() async {
        enum Outcome: Sendable {
            case success([HGTicket])
            case unauthorized
        }

        struct Source: TicketSource {
            var displayName: String
            var outcome: Outcome

            func tickets() async throws -> [HGTicket] {
                switch outcome {
                case .success(let tickets): return tickets
                case .unauthorized: throw HTTPError.unauthorized
                }
            }
        }

        let githubTicket = Self.ticket(id: "github-1", identifier: "GH-1", title: "GitHub")
        let linearTicket = Self.ticket(id: "linear-1", identifier: "LIN-1", title: "Linear")

        let githubOnly = await AppStore(ticketSources: [
            Source(displayName: "GitHub", outcome: .success([githubTicket])),
            Source(displayName: "Linear", outcome: .unauthorized),
        ])
        await githubOnly.loadTickets()

        let linearOnly = await AppStore(ticketSources: [
            Source(displayName: "GitHub", outcome: .unauthorized),
            Source(displayName: "Linear", outcome: .success([linearTicket])),
        ])
        await linearOnly.loadTickets()

        await MainActor.run {
            #expect(githubOnly.tickets == [githubTicket])
            #expect(githubOnly.ticketsState == .loaded)
            #expect(linearOnly.tickets == [linearTicket])
            #expect(linearOnly.ticketsState == .loaded)
        }
    }

    private static func ticket(id: String, identifier: String, title: String, updatedAt: Date? = nil) -> HGTicket {
        HGTicket(
            id: id,
            source: .linear,
            identifier: identifier,
            title: title,
            stateName: "Todo",
            team: "Engineering",
            assignee: nil,
            labels: [],
            url: nil,
            updatedAt: updatedAt
        )
    }
}
