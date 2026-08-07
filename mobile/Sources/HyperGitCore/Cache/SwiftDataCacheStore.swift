// SwiftDataCacheStore — persistent CacheStore over SwiftData/SQLite (issue #4).
// A plain actor wrapping a private ModelContext, rather than @ModelActor or a manual
// ModelActor conformance (modelExecutor = DefaultSerialModelExecutor(modelContext:)):
// both need the custom maxEntries/maxTotalBytes initializer, and manual ModelActor
// conformance would also need `modelContainer`/`modelExecutor` exposed `public` for
// cross-module actor dispatch (HyperGitApp is a separate target) — more unverified
// SwiftData surface than the task's own explicitly-sanctioned "actor wrapping a
// background ModelContext" alternative. A plain actor still serializes every access to
// `ModelContext` correctly (that's what actor isolation guarantees); the difference
// DefaultSerialModelExecutor adds is thread-affinity optimization, not correctness.
import Foundation
import SwiftData

public actor SwiftDataCacheStore {
    private let context: ModelContext
    private let maxEntries: Int
    private let maxTotalBytes: Int
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// Internal, not public: a container built without `CachedCollection` in its schema
    /// (i.e. not via `makeDefault()`) would compile here but fail every fetch/insert at
    /// runtime. `makeDefault()` is the one schema-safe way to construct this for the app;
    /// tests reach this directly (same module) with their own throwaway containers.
    init(container: ModelContainer, maxEntries: Int = 200, maxTotalBytes: Int = 20_000_000) {
        self.context = ModelContext(container)
        self.maxEntries = maxEntries
        self.maxTotalBytes = maxTotalBytes
    }

    // MARK: Generic keyed collection read/write

    private func read<Payload: Decodable>(key: String, as type: [Payload].Type) -> [Payload] {
        var descriptor = FetchDescriptor<CachedCollection>(predicate: #Predicate<CachedCollection> { $0.key == key })
        descriptor.fetchLimit = 1
        guard let row = try? context.fetch(descriptor).first,
              let decoded = try? decoder.decode([Payload].self, from: row.payload) else { return [] }
        // A cache hit is a use, not just a write: bumping `fetchedAt` here is what makes
        // eviction a real LRU rather than an LRW, which matters most exactly when offline
        // (repeated reads, no writes) — a collection actively being browsed must not look
        // "old" just because nothing is re-fetching it. Traded deliberately against the
        // extra save() this adds per read: at this app's scale (a handful of screen
        // navigations, not a request-per-second hot path) that cost is not significant.
        row.fetchedAt = Date()
        try? context.save()
        return decoded
    }

    private func write<Payload: Encodable>(key: String, value: [Payload]) {
        guard let data = try? encoder.encode(value) else { return }
        var descriptor = FetchDescriptor<CachedCollection>(predicate: #Predicate<CachedCollection> { $0.key == key })
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first {
            existing.payload = data
            existing.fetchedAt = Date()
            existing.payloadSize = data.count
        } else {
            context.insert(CachedCollection(key: key, payload: data, fetchedAt: Date()))
        }
        try? context.save()
        evictIfNeeded()
    }

    /// Bounds on-disk growth from browsing many repos/tickets over the app's lifetime:
    /// the least-recently-used collection (by `fetchedAt`, bumped on both read and write)
    /// is dropped once the entry count or total payload size crosses the configured
    /// limit. Always keeps at least the one row most recently touched, even if it alone
    /// exceeds `maxTotalBytes` — a byte cap is a target to trim toward, not a hard limit
    /// that may erase the entry that triggered it. Scans every row's `payloadSize` on
    /// every write (bounded by `maxEntries`, so ~200 rows worst case) rather than
    /// maintaining a separate running-total record — deliberately simple given the
    /// bounded worst case; revisit only if profiling on-device shows it matters.
    private func evictIfNeeded() {
        guard var rows = try? context.fetch(
            FetchDescriptor<CachedCollection>(sortBy: [SortDescriptor(\.fetchedAt, order: .forward)])
        ) else { return }
        var totalBytes = rows.reduce(0) { $0 + $1.payloadSize }
        var didEvict = false
        while rows.count > 1, (rows.count > maxEntries || totalBytes > maxTotalBytes) {
            let oldest = rows.removeFirst()
            totalBytes -= oldest.payloadSize
            context.delete(oldest)
            didEvict = true
        }
        if didEvict { try? context.save() }
    }

    // MARK: Key namespacing

    private func treeKey(owner: String, repo: String, branch: String) -> String { "tree:\(owner)/\(repo):\(branch)" }
    private func prsKey(owner: String, repo: String, state: HGPullRequest.State) -> String {
        "prs:\(owner)/\(repo):\(state.rawValue)"
    }
    private func issuesKey(owner: String, repo: String, state: HGIssue.State) -> String {
        "issues:\(owner)/\(repo):\(state.rawValue)"
    }
    private func ticketsKey(source: String) -> String { "tickets:\(source)" }
}

extension SwiftDataCacheStore: CacheStore {
    public func repositories() async -> [HGRepo] {
        read(key: "repositories", as: [CachedRepoPayload].self).map(\.model)
    }

    public func setRepositories(_ repos: [HGRepo]) async {
        write(key: "repositories", value: repos.map(CachedRepoPayload.init))
    }

    public func fileTree(owner: String, repo: String, branch: String) async -> [HGFileEntry] {
        read(key: treeKey(owner: owner, repo: repo, branch: branch), as: [CachedFileEntryPayload].self).map(\.model)
    }

    public func setFileTree(_ entries: [HGFileEntry], owner: String, repo: String, branch: String) async {
        write(key: treeKey(owner: owner, repo: repo, branch: branch), value: entries.map(CachedFileEntryPayload.init))
    }

    public func pullRequests(owner: String, repo: String, state: HGPullRequest.State) async -> [HGPullRequest] {
        read(key: prsKey(owner: owner, repo: repo, state: state), as: [CachedPullRequestPayload].self).map(\.model)
    }

    public func setPullRequests(_ prs: [HGPullRequest], owner: String, repo: String, state: HGPullRequest.State) async {
        write(key: prsKey(owner: owner, repo: repo, state: state), value: prs.map(CachedPullRequestPayload.init))
    }

    public func issues(owner: String, repo: String, state: HGIssue.State) async -> [HGIssue] {
        read(key: issuesKey(owner: owner, repo: repo, state: state), as: [CachedIssuePayload].self).map(\.model)
    }

    public func setIssues(_ issues: [HGIssue], owner: String, repo: String, state: HGIssue.State) async {
        write(key: issuesKey(owner: owner, repo: repo, state: state), value: issues.map(CachedIssuePayload.init))
    }

    public func tickets(source: String) async -> [HGTicket] {
        read(key: ticketsKey(source: source), as: [CachedTicketPayload].self).map(\.model)
    }

    public func setTickets(_ tickets: [HGTicket], source: String) async {
        write(key: ticketsKey(source: source), value: tickets.map(CachedTicketPayload.init))
    }

    public func clearAll() async {
        guard let rows = try? context.fetch(FetchDescriptor<CachedCollection>()) else { return }
        for row in rows { context.delete(row) }
        try? context.save()
    }
}

public extension SwiftDataCacheStore {
    /// The default on-disk store, shared across app launches, under Application Support.
    static func makeDefault() throws -> SwiftDataCacheStore {
        let schema = Schema([CachedCollection.self])
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let directory = appSupport.appendingPathComponent("HyperGit", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let config = ModelConfiguration(schema: schema, url: directory.appendingPathComponent("cache.sqlite"))
        let container = try ModelContainer(for: schema, configurations: [config])
        return SwiftDataCacheStore(container: container)
    }
}
