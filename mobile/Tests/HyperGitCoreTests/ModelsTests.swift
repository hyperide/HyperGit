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

    @Test("HGChecksSummary rolls up check runs: none/pending/passing/failing")
    func checksSummaryRollup() {
        func run(_ status: HGCheckRun.Status, _ conclusion: HGCheckRun.Conclusion?) -> HGCheckRun {
            HGCheckRun(id: 1, name: "x", status: status, conclusion: conclusion,
                      detailsURL: nil, startedAt: nil, completedAt: nil)
        }
        #expect(HGChecksSummary(runs: []) == .none)
        #expect(HGChecksSummary(runs: [run(.inProgress, nil)]) == .pending)
        #expect(HGChecksSummary(runs: [run(.completed, .success), run(.completed, .neutral)]) == .passing)
        #expect(HGChecksSummary(runs: [run(.completed, .success), run(.completed, .failure)]) == .failing)
    }

    @Test("HGChecksSummary treats skipped and stale conclusions as non-blocking (passing)")
    func checksSummarySkippedAndStaleArePassing() {
        // Deliberate policy, matching GitHub's own PR UI: a conditionally
        // skipped check isn't a blocker, and a stale (superseded) result
        // isn't treated as a failure either. Pinned so moving either bucket
        // later is a reviewed choice, not an accidental regression.
        func run(_ conclusion: HGCheckRun.Conclusion) -> HGCheckRun {
            HGCheckRun(id: 1, name: "x", status: .completed, conclusion: conclusion,
                      detailsURL: nil, startedAt: nil, completedAt: nil)
        }
        #expect(HGChecksSummary(runs: [run(.skipped)]) == .passing)
        #expect(HGChecksSummary(runs: [run(.stale)]) == .passing)
    }

    @Test("HGChecksSummary reports a failure even while a sibling check is still running")
    func checksSummaryFailureBeatsPending() {
        func run(_ status: HGCheckRun.Status, _ conclusion: HGCheckRun.Conclusion?) -> HGCheckRun {
            HGCheckRun(id: 1, name: "x", status: status, conclusion: conclusion,
                      detailsURL: nil, startedAt: nil, completedAt: nil)
        }
        // One job already failed, another is still building — this must not
        // read as "pending" and hide the failure.
        let mixed = [run(.completed, .failure), run(.inProgress, nil)]
        #expect(HGChecksSummary(runs: mixed) == .failing)
    }

    @Test("HGChecksSummary treats a completed run with no recognized conclusion as failing, not passing")
    func checksSummaryUnknownConclusionIsConservative() {
        // GitHub only omits `conclusion` while a run is queued/in-progress —
        // never once completed — so a nil conclusion on a *completed* run
        // means "an unrecognized conclusion string", not "not decided yet".
        // Defaulting that into the passing bucket would hide a real failure
        // (or a future GitHub conclusion this build doesn't know about).
        let unknown = HGCheckRun(id: 1, name: "x", status: .completed, conclusion: nil,
                                 detailsURL: nil, startedAt: nil, completedAt: nil)
        #expect(HGChecksSummary(runs: [unknown]) == .failing)
    }

    @Test("HGChecksSummary honors a failing conclusion even if the run's status wasn't recognized as completed")
    func checksSummaryFailingConclusionWinsOverUnrecognizedStatus() {
        // The DTO falls back unrecognized status strings to `.queued`; a run
        // with a real (failing) conclusion attached has still genuinely
        // finished regardless of that fallback, and must not read as
        // "pending" forever.
        let run = HGCheckRun(id: 1, name: "x", status: .queued, conclusion: .failure,
                             detailsURL: nil, startedAt: nil, completedAt: nil)
        #expect(HGChecksSummary(runs: [run]) == .failing)
    }

    @Test("HGPullRequest.checksRef is the head SHA, or nil — never the ambiguous branch name")
    func pullRequestChecksRefNeverFallsBackToBranchName() {
        let withSHA = HGPullRequest(id: 1, number: 1, title: "t", body: nil, state: .open,
                                    isDraft: false, isMerged: false, author: nil,
                                    head: "feature", headSHA: "abc123", base: "main",
                                    additions: 0, deletions: 0, changedFiles: 0, commits: 0,
                                    commentsCount: 0, createdAt: nil, updatedAt: nil,
                                    mergedAt: nil, htmlURL: nil)
        #expect(withSHA.checksRef == "abc123")

        // No headSHA (e.g. a non-GitHub source, or a stub) means "don't
        // fetch checks" — NOT "fetch by branch name", which for a
        // forked-repo PR would query the wrong repo's branch.
        let withoutSHA = HGPullRequest(id: 2, number: 2, title: "t", body: nil, state: .open,
                                       isDraft: false, isMerged: false, author: nil,
                                       head: "feature", base: "main",
                                       additions: 0, deletions: 0, changedFiles: 0, commits: 0,
                                       commentsCount: 0, createdAt: nil, updatedAt: nil,
                                       mergedAt: nil, htmlURL: nil)
        #expect(withoutSHA.checksRef == nil)
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

    @Test("AppStore sets reposStaleReason on cache fallback and clears it once the network recovers")
    func storeStaleReasonSetThenCleared() async {
        actor Toggleable: RepositorySource {
            var isOnline = true
            func setOnline(_ value: Bool) { isOnline = value }
            func currentUser() async throws -> HGUser { throw HTTPError.invalidResponse }
            func repositories() async throws -> [HGRepo] {
                guard isOnline else { throw HTTPError.invalidResponse }
                return HGRepo.samples
            }
            func fileTree(owner: String, repo: String, branch: String?) async throws -> [HGFileEntry] { [] }
            func fileContent(owner: String, repo: String, path: String, ref: String?) async throws -> HGFileContent { throw HTTPError.invalidResponse }
            func pullRequests(owner: String, repo: String, state: HGPullRequest.State) async throws -> [HGPullRequest] { [] }
            func pullRequest(owner: String, repo: String, number: Int) async throws -> HGPullRequest { throw HTTPError.invalidResponse }
            func pullRequestFiles(owner: String, repo: String, number: Int) async throws -> [HGFileChange] { [] }
            func commits(owner: String, repo: String, branch: String?) async throws -> [HGCommit] { [] }
            func issues(owner: String, repo: String, state: HGIssue.State) async throws -> [HGIssue] { [] }
            func issue(owner: String, repo: String, number: Int) async throws -> HGIssue { throw HTTPError.invalidResponse }
        }

        let source = Toggleable()
        let store = await AppStore(repoSource: source, cache: MemoryCacheStore())

        await store.loadRepositories()
        await MainActor.run { #expect(store.reposStaleReason == nil) }

        await source.setOnline(false)
        await store.loadRepositories()
        await MainActor.run {
            #expect(store.reposState == .loaded)
            #expect(store.reposStaleReason != nil)
        }

        await source.setOnline(true)
        await store.loadRepositories()
        await MainActor.run { #expect(store.reposStaleReason == nil) }
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
