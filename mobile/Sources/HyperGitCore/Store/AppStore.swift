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
        } catch {
            // Local-first fallback: show cache when the network fails.
            let cached = await cache.repositories()
            repositories = cached
            reposState = cached.isEmpty ? .error(message(error)) : .loaded
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
        do {
            let tree = try await repoSource.fileTree(owner: repo.ownerLogin, repo: repo.name, branch: branch ?? repo.defaultBranch)
            await cache.setFileTree(tree, owner: repo.ownerLogin, repo: repo.name)
            fileTree = tree
        } catch {
            fileTree = await cache.fileTree(owner: repo.ownerLogin, repo: repo.name)
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
            await cache.setPullRequests(prs, owner: repo.ownerLogin, repo: repo.name)
            pullRequests = prs
            prsState = .loaded
        } catch {
            pullRequests = await cache.pullRequests(owner: repo.ownerLogin, repo: repo.name)
            prsState = pullRequests.isEmpty ? .error(message(error)) : .loaded
        }
    }

    public func loadIssues(state: HGIssue.State = .open) async {
        guard let repo = selectedRepo else { return }
        issuesState = .loading
        do {
            let list = try await repoSource.issues(owner: repo.ownerLogin, repo: repo.name, state: state)
            await cache.setIssues(list, owner: repo.ownerLogin, repo: repo.name)
            issues = list
            issuesState = .loaded
        } catch {
            issues = await cache.issues(owner: repo.ownerLogin, repo: repo.name)
            issuesState = issues.isEmpty ? .error(message(error)) : .loaded
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
        guard !ticketSources.isEmpty else { ticketsState = .loaded; return }
        ticketsState = .loading
        var collected: [HGTicket] = []
        var failures: [String] = []
        var authFailures: [String] = []
        for source in ticketSources {
            do {
                let list = try await source.tickets()
                await cache.setTickets(list, source: source.displayName)
                collected.append(contentsOf: list)
            } catch let partial as any PartialTicketResultsError {
                let list = partial.partialTickets
                let cached = await cache.tickets(source: source.displayName)
                if !list.isEmpty {
                    let merged = mergeTickets(fresh: list, cached: cached)
                    await cache.setTickets(merged, source: source.displayName)
                    collected.append(contentsOf: merged)
                } else {
                    collected.append(contentsOf: cached)
                }
                failures.append(partial.partialTicketsMessage)
            } catch {
                collected.append(contentsOf: await cache.tickets(source: source.displayName))
                if (error as? HTTPError) == .unauthorized {
                    authFailures.append(message(error))
                } else {
                    failures.append(message(error))
                }
            }
        }
        tickets = collected.sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
        if failures.isEmpty, tickets.isEmpty, !authFailures.isEmpty {
            failures = authFailures
        }
        ticketsState = failures.isEmpty ? .loaded : .error(failures.joined(separator: " "))
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
