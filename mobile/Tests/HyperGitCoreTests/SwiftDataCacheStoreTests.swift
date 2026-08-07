// SwiftDataCacheStore tests — restart persistence, an online→offline→online cycle
// through AppStore's fallback path, and LRU eviction (issue #4 acceptance criteria).
import Foundation
import SwiftData
import Testing
@testable import HyperGitCore

@Suite("SwiftDataCacheStore")
struct SwiftDataCacheStoreTests {
    private static func makeContainer(url: URL? = nil) throws -> ModelContainer {
        let schema = Schema([CachedCollection.self])
        let configuration = url.map { ModelConfiguration(schema: schema, url: $0) }
            ?? ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    @Test("restart persistence: repositories written before teardown are present after reopening the store")
    func restartPersistence() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let storeURL = dir.appendingPathComponent("cache.sqlite")

        do {
            let container = try Self.makeContainer(url: storeURL)
            let store = SwiftDataCacheStore(container: container)
            await store.setRepositories(HGRepo.samples)
        }

        // A brand new container over the same on-disk file simulates a cold app restart.
        let reopened = try Self.makeContainer(url: storeURL)
        let restarted = SwiftDataCacheStore(container: reopened)
        let repos = await restarted.repositories()
        #expect(repos.map(\.fullName) == HGRepo.samples.map(\.fullName))
    }

    @Test("online to offline to online: AppStore keeps serving the persisted cache while the network is down")
    func onlineOfflineOnlineCycle() async throws {
        let container = try Self.makeContainer()
        let cache = SwiftDataCacheStore(container: container)
        let source = ToggleableRepositorySource()
        let store = await AppStore(repoSource: source, cache: cache)

        await store.loadRepositories()
        await MainActor.run {
            #expect(store.repositories.map(\.fullName) == HGRepo.samples.map(\.fullName))
            #expect(store.reposState == .loaded)
            #expect(store.reposStaleReason == nil)
        }

        await source.setOnline(false)
        await store.loadRepositories()
        await MainActor.run {
            #expect(store.repositories.map(\.fullName) == HGRepo.samples.map(\.fullName))
            #expect(store.reposState == .loaded)
            #expect(store.reposStaleReason != nil)
        }

        await source.setOnline(true)
        await store.loadRepositories()
        await MainActor.run {
            #expect(store.reposState == .loaded)
            #expect(store.reposStaleReason == nil)
        }
    }

    @Test("eviction: the least-recently-written collection is dropped once the entry cap is exceeded")
    func evictsOldestEntryOnCap() async throws {
        let container = try Self.makeContainer()
        let store = SwiftDataCacheStore(container: container, maxEntries: 2, maxTotalBytes: .max)

        await store.setFileTree([HGFileEntry(path: "a", name: "a", sha: "1", size: 1, kind: .file)], owner: "o", repo: "repo1", branch: "main")
        await store.setFileTree([HGFileEntry(path: "b", name: "b", sha: "2", size: 1, kind: .file)], owner: "o", repo: "repo2", branch: "main")
        await store.setFileTree([HGFileEntry(path: "c", name: "c", sha: "3", size: 1, kind: .file)], owner: "o", repo: "repo3", branch: "main")

        let repo1 = await store.fileTree(owner: "o", repo: "repo1", branch: "main")
        let repo2 = await store.fileTree(owner: "o", repo: "repo2", branch: "main")
        let repo3 = await store.fileTree(owner: "o", repo: "repo3", branch: "main")

        #expect(repo1.isEmpty)
        #expect(repo2.map(\.name) == ["b"])
        #expect(repo3.map(\.name) == ["c"])
    }

    @Test("file trees for different branches of the same repo stay in distinct cache slots")
    func fileTreeKeyedByBranch() async throws {
        let container = try Self.makeContainer()
        let store = SwiftDataCacheStore(container: container)

        await store.setFileTree([HGFileEntry(path: "a", name: "a", sha: "1", size: 1, kind: .file)], owner: "o", repo: "r", branch: "main")
        await store.setFileTree([HGFileEntry(path: "b", name: "b", sha: "2", size: 1, kind: .file)], owner: "o", repo: "r", branch: "dev")

        let main = await store.fileTree(owner: "o", repo: "r", branch: "main")
        let dev = await store.fileTree(owner: "o", repo: "r", branch: "dev")
        #expect(main.map(\.name) == ["a"])
        #expect(dev.map(\.name) == ["b"])
    }

    @Test("open and closed pull request lists for the same repo stay in distinct cache slots")
    func pullRequestsKeyedByState() async throws {
        let container = try Self.makeContainer()
        let store = SwiftDataCacheStore(container: container)
        let openPR = HGPullRequest.samples[0]
        let closedPR = HGPullRequest(
            id: 99, number: 99, title: "Closed one", body: nil, state: .closed, isDraft: false, isMerged: false,
            author: nil, head: "h", base: "b", additions: 0, deletions: 0, changedFiles: 0, commits: 0,
            commentsCount: 0, createdAt: nil, updatedAt: nil, mergedAt: nil, htmlURL: nil
        )

        await store.setPullRequests([openPR], owner: "o", repo: "r", state: .open)
        await store.setPullRequests([closedPR], owner: "o", repo: "r", state: .closed)

        let open = await store.pullRequests(owner: "o", repo: "r", state: .open)
        let closed = await store.pullRequests(owner: "o", repo: "r", state: .closed)
        #expect(open.map(\.number) == [openPR.number])
        #expect(closed.map(\.number) == [closedPR.number])
    }

    @Test("clearAll wipes every cached collection")
    func clearAllWipesEverything() async throws {
        let container = try Self.makeContainer()
        let store = SwiftDataCacheStore(container: container)

        await store.setRepositories(HGRepo.samples)
        await store.setTickets([HGTicket.samples[0]], source: "GitHub")
        await store.setFileTree([HGFileEntry(path: "a", name: "a", sha: "1", size: 1, kind: .file)], owner: "o", repo: "r", branch: "main")

        await store.clearAll()

        #expect(await store.repositories().isEmpty)
        #expect(await store.tickets(source: "GitHub").isEmpty)
        #expect(await store.fileTree(owner: "o", repo: "r", branch: "main").isEmpty)
    }

    @Test("eviction: total payload size is bounded even with a high entry-count cap")
    func evictsOnByteSizeCap() async throws {
        let container = try Self.makeContainer()
        let singleEntryBytes = try JSONEncoder().encode([CachedTicketPayload(HGTicket.samples[0])]).count
        let store = SwiftDataCacheStore(container: container, maxEntries: 1000, maxTotalBytes: singleEntryBytes * 2)

        for index in 1...5 {
            await store.setTickets([HGTicket.samples[0]], source: "source-\(index)")
        }

        var residentCount = 0
        for index in 1...5 {
            if !(await store.tickets(source: "source-\(index)")).isEmpty { residentCount += 1 }
        }
        #expect(residentCount <= 2)
        // The most recently written source must always survive eviction.
        #expect(!(await store.tickets(source: "source-5")).isEmpty)
    }

    @Test("a row with an undecodable payload degrades to an empty collection instead of throwing")
    func corruptPayloadDegradesToEmpty() async throws {
        let container = try Self.makeContainer()
        // Seed a malformed row directly (bypassing `write`, which always encodes valid
        // JSON) to simulate schema drift after an app update or on-disk corruption.
        let seedContext = ModelContext(container)
        seedContext.insert(CachedCollection(key: "repositories", payload: Data("not json".utf8), fetchedAt: Date()))
        try seedContext.save()

        let store = SwiftDataCacheStore(container: container)
        #expect(await store.repositories().isEmpty)
    }

    @Test("reading a collection bumps its fetchedAt, so eviction treats reads as uses too")
    func readBumpsFetchedAtForEviction() async throws {
        let container = try Self.makeContainer()
        let store = SwiftDataCacheStore(container: container, maxEntries: 2, maxTotalBytes: .max)

        await store.setFileTree([HGFileEntry(path: "a", name: "a", sha: "1", size: 1, kind: .file)], owner: "o", repo: "repo1", branch: "main")
        await store.setFileTree([HGFileEntry(path: "b", name: "b", sha: "2", size: 1, kind: .file)], owner: "o", repo: "repo2", branch: "main")

        // Reading repo1 marks it more recently used than repo2, which hasn't been
        // touched since its write — this is the scenario offline browsing depends on:
        // the collection actively being viewed must not look "old" just because it
        // isn't being re-fetched.
        _ = await store.fileTree(owner: "o", repo: "repo1", branch: "main")

        // A third write exceeds maxEntries: 2 — repo2, not repo1, should be evicted.
        await store.setFileTree([HGFileEntry(path: "c", name: "c", sha: "3", size: 1, kind: .file)], owner: "o", repo: "repo3", branch: "main")

        #expect(!(await store.fileTree(owner: "o", repo: "repo1", branch: "main")).isEmpty)
        #expect((await store.fileTree(owner: "o", repo: "repo2", branch: "main")).isEmpty)
    }

    @Test("MemoryCacheStore keeps open/closed pull request and branch file-tree slots distinct")
    func memoryCacheStoreKeysStayDistinct() async {
        let store = MemoryCacheStore()
        let openPR = HGPullRequest.samples[0]

        await store.setPullRequests([openPR], owner: "o", repo: "r", state: .open)
        await store.setPullRequests([], owner: "o", repo: "r", state: .closed)
        #expect(await store.pullRequests(owner: "o", repo: "r", state: .open).map(\.number) == [openPR.number])
        #expect(await store.pullRequests(owner: "o", repo: "r", state: .closed).isEmpty)

        await store.setFileTree([HGFileEntry(path: "a", name: "a", sha: "1", size: 1, kind: .file)], owner: "o", repo: "r", branch: "main")
        await store.setFileTree([], owner: "o", repo: "r", branch: "dev")
        #expect(await store.fileTree(owner: "o", repo: "r", branch: "main").map(\.name) == ["a"])
        #expect(await store.fileTree(owner: "o", repo: "r", branch: "dev").isEmpty)
    }

    @Test("ticketsStaleReason surfaces when an unauthorized source falls back to non-empty cache but the load still counts as loaded")
    func ticketsStaleReasonForAuthFallback() async throws {
        let container = try Self.makeContainer()
        let cache = SwiftDataCacheStore(container: container)
        await cache.setTickets([HGTicket.samples[1]], source: "Linear")

        struct GitHubSource: TicketSource {
            var displayName: String { "GitHub" }
            func tickets() async throws -> [HGTicket] { [HGTicket.samples[0]] }
        }
        struct UnauthorizedLinear: TicketSource {
            var displayName: String { "Linear" }
            func tickets() async throws -> [HGTicket] { throw HTTPError.unauthorized }
        }

        let store = await AppStore(ticketSources: [GitHubSource(), UnauthorizedLinear()], cache: cache)
        await store.loadTickets()

        await MainActor.run {
            #expect(store.ticketsState == .loaded)
            #expect(store.ticketsStaleReason != nil)
        }
    }

    @Test("ticketsStaleReason stays nil when a failure already surfaces as .error, avoiding a contradictory double-signal")
    func ticketsStaleReasonNilOnHardFailure() async throws {
        let container = try Self.makeContainer()
        let cache = SwiftDataCacheStore(container: container)
        await cache.setTickets([HGTicket.samples[0]], source: "GitHub")

        struct FailingSource: TicketSource {
            var displayName: String { "GitHub" }
            func tickets() async throws -> [HGTicket] { throw HTTPError.badStatus(500) }
        }

        let store = await AppStore(ticketSources: [FailingSource()], cache: cache)
        await store.loadTickets()

        await MainActor.run {
            if case .error = store.ticketsState {} else { Issue.record("expected .error, got \(store.ticketsState)") }
            #expect(store.ticketsStaleReason == nil)
        }
    }
}

/// Toggles between serving `HGRepo.samples` and simulating a dead network, to drive
/// AppStore through an online→offline→online cycle without a real network dependency —
/// the same injected-boundary pattern LinearClientTests.swift uses for its transport.
private actor ToggleableRepositorySource: RepositorySource {
    private var isOnline = true

    func setOnline(_ value: Bool) { isOnline = value }

    func currentUser() async throws -> HGUser { throw HTTPError.invalidResponse }
    func repositories() async throws -> [HGRepo] {
        guard isOnline else { throw HTTPError.invalidResponse }
        return HGRepo.samples
    }
    func fileTree(owner: String, repo: String, branch: String?) async throws -> [HGFileEntry] { [] }
    func fileContent(owner: String, repo: String, path: String, ref: String?) async throws -> HGFileContent {
        throw HTTPError.invalidResponse
    }
    func pullRequests(owner: String, repo: String, state: HGPullRequest.State) async throws -> [HGPullRequest] { [] }
    func pullRequest(owner: String, repo: String, number: Int) async throws -> HGPullRequest {
        throw HTTPError.invalidResponse
    }
    func pullRequestFiles(owner: String, repo: String, number: Int) async throws -> [HGFileChange] { [] }
    func commits(owner: String, repo: String, branch: String?) async throws -> [HGCommit] { [] }
    func issues(owner: String, repo: String, state: HGIssue.State) async throws -> [HGIssue] { [] }
    func issue(owner: String, repo: String, number: Int) async throws -> HGIssue { throw HTTPError.invalidResponse }
}
