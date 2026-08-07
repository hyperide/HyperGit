// AppStore — @MainActor observable UI store. Orchestrates RepositorySource +
// TicketSource(s) over CacheStore with a load/refresh cycle. Local-first: writes
// fetched results to the cache before surfacing, so the UI survives offline.
// SPEC §2.3.
import Foundation

@frozen
public enum LoadState: Sendable, Equatable {
    case idle
    case loading
    case loaded
    case error(String)
}

public protocol PartialTicketResultsError: Error {
    var partialTickets: [HGTicket] { get }
    var partialTicketsMessage: String { get }
}

@MainActor
@Observable
public final class AppStore {
    public var repositories: [HGRepo] = []
    public var selectedRepo: HGRepo?
    public var fileTree: [HGFileEntry] = []
    public var openFile: HGFileContent?
    public var pullRequests: [HGPullRequest] = []
    public var issues: [HGIssue] = []
    public var commits: [HGCommit] = []
    public var tickets: [HGTicket] = []

    public var reposState: LoadState = .idle
    public var prsState: LoadState = .idle
    public var issuesState: LoadState = .idle
    public var ticketsState: LoadState = .idle

    /// Non-nil while the corresponding list is showing cache fallback data rather than
    /// a fresh fetch (i.e. the last network attempt failed but the cache had something
    /// to show). Kept separate from `LoadState` — which already collapses to `.loaded`
    /// on a successful cache fallback — so the UI can render a distinct "stale" banner
    /// without conflating "no data" (`.error`) with "old data" (`.loaded` + stale reason).
    public var reposStaleReason: String?
    public var prsStaleReason: String?
    public var issuesStaleReason: String?
    public var ticketsStaleReason: String?

    public let repoSource: RepositorySource
    public let ticketSources: [TicketSource]
    public let cache: CacheStore

    public init(
        repoSource: RepositorySource = PreviewRepositorySource(),
        ticketSources: [TicketSource] = [],
        cache: CacheStore = MemoryCacheStore()
    ) {
        self.repoSource = repoSource
        self.ticketSources = ticketSources
        self.cache = cache
    }

    // MARK: Repositories

    public func loadRepositories() async {
        reposState = .loading
        do {
            let fetched = try await repoSource.repositories()
            await cache.setRepositories(fetched)
            repositories = fetched
            reposState = .loaded
            reposStaleReason = nil
        } catch {
            // Local-first fallback: show cache when the network fails.
            let cached = await cache.repositories()
            repositories = cached
            reposState = cached.isEmpty ? .error(message(error)) : .loaded
            reposStaleReason = cached.isEmpty ? nil : message(error)
        }
    }

    // MARK: Repo detail

    public func select(_ repo: HGRepo) {
        selectedRepo = repo
        fileTree = []
        pullRequests = []
        issues = []
        commits = []
    }

    public func loadFileTree(branch: String? = nil) async {
        guard let repo = selectedRepo else { return }
        // "HEAD" is a cache-key sentinel for "no explicit branch and no known default" —
        // distinct from any real branch name, so it can't collide with one.
        let resolvedBranch = branch ?? repo.defaultBranch ?? "HEAD"
        do {
            let tree = try await repoSource.fileTree(owner: repo.ownerLogin, repo: repo.name, branch: branch ?? repo.defaultBranch)
            await cache.setFileTree(tree, owner: repo.ownerLogin, repo: repo.name, branch: resolvedBranch)
            fileTree = tree
        } catch {
            fileTree = await cache.fileTree(owner: repo.ownerLogin, repo: repo.name, branch: resolvedBranch)
        }
    }

    public func loadFile(path: String, ref: String? = nil) async {
        guard let repo = selectedRepo else { return }
        do {
            openFile = try await repoSource.fileContent(owner: repo.ownerLogin, repo: repo.name, path: path, ref: ref)
        } catch {
            openFile = nil
        }
    }

    public func loadPullRequests(state: HGPullRequest.State = .open) async {
        guard let repo = selectedRepo else { return }
        prsState = .loading
        do {
            let prs = try await repoSource.pullRequests(owner: repo.ownerLogin, repo: repo.name, state: state)
            await cache.setPullRequests(prs, owner: repo.ownerLogin, repo: repo.name, state: state)
            pullRequests = prs
            prsState = .loaded
            prsStaleReason = nil
        } catch {
            pullRequests = await cache.pullRequests(owner: repo.ownerLogin, repo: repo.name, state: state)
            prsState = pullRequests.isEmpty ? .error(message(error)) : .loaded
            prsStaleReason = pullRequests.isEmpty ? nil : message(error)
        }
    }

    public func loadIssues(state: HGIssue.State = .open) async {
        guard let repo = selectedRepo else { return }
        issuesState = .loading
        do {
            let list = try await repoSource.issues(owner: repo.ownerLogin, repo: repo.name, state: state)
            await cache.setIssues(list, owner: repo.ownerLogin, repo: repo.name, state: state)
            issues = list
            issuesState = .loaded
            issuesStaleReason = nil
        } catch {
            issues = await cache.issues(owner: repo.ownerLogin, repo: repo.name, state: state)
            issuesState = issues.isEmpty ? .error(message(error)) : .loaded
            issuesStaleReason = issues.isEmpty ? nil : message(error)
        }
    }

    public func loadCommits(branch: String? = nil) async {
        guard let repo = selectedRepo else { return }
        do {
            commits = try await repoSource.commits(owner: repo.ownerLogin, repo: repo.name, branch: branch ?? repo.defaultBranch)
        } catch {
            commits = []
        }
    }

    // MARK: Unified tickets (Linear + GitHub)

    public func loadTickets() async {
        guard !ticketSources.isEmpty else { ticketsState = .loaded; ticketsStaleReason = nil; return }
        ticketsState = .loading
        var collected: [HGTicket] = []
        var failures: [String] = []
        var authFailures: [String] = []
        var usedStaleFallback = false
        for source in ticketSources {
            let outcome = await fetchTickets(from: source)
            collected.append(contentsOf: outcome.tickets)
            usedStaleFallback = usedStaleFallback || outcome.usedCachedFallback
            if let failureMessage = outcome.failureMessage {
                if outcome.isAuthFailure { authFailures.append(failureMessage) } else { failures.append(failureMessage) }
            }
        }
        tickets = collected.sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
        if failures.isEmpty, tickets.isEmpty, !authFailures.isEmpty {
            failures = authFailures
        }
        ticketsState = failures.isEmpty ? .loaded : .error(failures.joined(separator: " "))
        // Only surface staleness when the state itself still reads as a clean success —
        // `.error` (a partial-pagination page or a hard failure) already communicates
        // degradation, so `.loaded` + a stale reason at the same time would be a
        // contradictory double-signal for the same underlying event.
        ticketsStaleReason = (ticketsState == .loaded && usedStaleFallback)
            ? "Some tickets may be from an earlier sync."
            : nil
    }

    private struct TicketSourceOutcome {
        let tickets: [HGTicket]
        let usedCachedFallback: Bool
        let failureMessage: String?
        let isAuthFailure: Bool
    }

    private func fetchTickets(from source: TicketSource) async -> TicketSourceOutcome {
        do {
            let list = try await source.tickets()
            await cache.setTickets(list, source: source.displayName)
            return TicketSourceOutcome(tickets: list, usedCachedFallback: false, failureMessage: nil, isAuthFailure: false)
        } catch let partial as any PartialTicketResultsError {
            let list = partial.partialTickets
            let cached = await cache.tickets(source: source.displayName)
            let result = list.isEmpty ? cached : mergeTickets(fresh: list, cached: cached)
            if !list.isEmpty { await cache.setTickets(result, source: source.displayName) }
            // Doesn't currently affect `ticketsStaleReason` (this branch always sets
            // `failureMessage`, which forces `.error` and gates the reason off) — labeled
            // accurately anyway so it doesn't silently mislead if that gating ever changes.
            return TicketSourceOutcome(
                tickets: result, usedCachedFallback: !cached.isEmpty,
                failureMessage: partial.partialTicketsMessage, isAuthFailure: false
            )
        } catch {
            let cached = await cache.tickets(source: source.displayName)
            return TicketSourceOutcome(
                tickets: cached, usedCachedFallback: !cached.isEmpty,
                failureMessage: message(error), isAuthFailure: (error as? HTTPError) == .unauthorized
            )
        }
    }

    // MARK: Helpers

    private func message(_ error: Error) -> String {
        if let http = error as? HTTPError { return http.humanDescription }
        return error.localizedDescription
    }

    private func mergeTickets(fresh: [HGTicket], cached: [HGTicket]) -> [HGTicket] {
        let freshIDs = Set(fresh.map(\.id))
        return fresh + cached.filter { !freshIDs.contains($0.id) }
    }
}

extension LinearClientError: PartialTicketResultsError {
    public var partialTickets: [HGTicket] {
        switch self {
        case .paginationLimitExceeded(maxPages: _, partialTickets: let partialTickets):
            return partialTickets
        case .graphQLErrors:
            return []
        }
    }

    public var partialTicketsMessage: String {
        switch self {
        case .paginationLimitExceeded(maxPages: let maxPages, partialTickets: let partialTickets):
            return "Loaded \(partialTickets.count) Linear tickets from the first \(maxPages) pages."
        case .graphQLErrors(let messages):
            return messages.joined(separator: " ")
        }
    }
}

extension HTTPError {
    var humanDescription: String {
        switch self {
        case .invalidURL: return "Bad request URL."
        case .invalidResponse: return "No network response."
        case .unauthorized: return "Token missing or invalid."
        case .forbidden: return "Access forbidden."
        case .notFound: return "Not found."
        case .rateLimited(let after): return "Rate limited\(after.map { " (retry in \($0)s)" } ?? "")."
        case .badStatus(let code): return "Server error \(code)."
        case .decoding(let detail): return "Could not parse response (\(detail))."
        }
    }
}
