// GitHubClient — RepositorySource + TicketSource over the GitHub REST API v3.
// Depends only on an HTTPTransport (injectable for tests) so decoding is exercised
// in tests without a network. SPEC §2.2/§2.4.
import Foundation

public struct GitHubClient: RepositorySource, TicketSource {
    public let baseURL: URL
    public let transport: HTTPTransport
    public let tokenProvider: @Sendable () -> String?
    private let tokenStore: (any TokenStore)?

    public var displayName: String { "GitHub" }

    public init(
        baseURL: URL = URL(string: "https://api.github.com")!,
        tokenProvider: @escaping @Sendable () -> String?,
        transport: HTTPTransport? = nil,
        session: URLSession = .shared,
        tokenStore: (any TokenStore)? = nil
    ) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        self.tokenStore = tokenStore
        self.transport = transport ?? HTTPClient.transport(
            baseURL: baseURL,
            tokenProvider: { [tokenStore] in
                // Try OAuth token first
                if let store = tokenStore,
                   let oauth = store.oauthTokens(for: .github) {
                    let accessToken = oauth.accessToken
                    if !accessToken.isEmpty {
                        return accessToken
                    }
                }
                // Fallback to PAT
                return tokenProvider()
            },
            defaultHeaders: ["X-GitHub-Api-Version": "2022-11-28",
                             "Accept": "application/vnd.github+json"],
            session: session
        )
    }

    // Convenience init for backward compatibility
    public init(
        baseURL: URL = URL(string: "https://api.github.com")!,
        tokenProvider: @escaping @Sendable () -> String?,
        transport: HTTPTransport? = nil,
        session: URLSession = .shared
    ) {
        self.init(baseURL: baseURL, tokenProvider: tokenProvider, transport: transport, session: session, tokenStore: nil)
    }

    // MARK: RepositorySource

    /// Maximum pages fetched per list call (per_page=100 → up to 1000 items). Guards
    /// against runaway pagination on huge result sets.
    public static let maxPages = 10

    public func currentUser() async throws -> HGUser {
        let (data, _) = try await transport("user", [:])
        return try GitHub.decode(GitHub.UserDTO.self, from: data).toModel()
    }

    public func repositories() async throws -> [HGRepo] {
        try await paged("user/repos?per_page=100&sort=updated&type=all") {
            try GitHub.decode([GitHub.RepoDTO].self, from: $0).map { $0.toModel() }
        }
    }

    public func fileTree(owner: String, repo: String, branch: String?) async throws -> [HGFileEntry] {
        let sha = branch ?? "HEAD"
        let (data, _) = try await transport("repos/\(owner)/\(repo)/git/trees/\(sha)?recursive=1", [:])
        let tree = try GitHub.decode(GitHub.TreeDTO.self, from: data)
        return tree.tree.compactMap { $0.toModel() }
    }

    public func fileContent(owner: String, repo: String, path: String, ref: String?) async throws -> HGFileContent {
        var resource = "repos/\(owner)/\(repo)/contents/\(path)"
        if let ref { resource += "?ref=\(ref)" }
        let (data, _) = try await transport(resource, [:])
        return try GitHub.decode(GitHub.ContentDTO.self, from: data).toModel()
    }

    public func pullRequests(owner: String, repo: String, state: HGPullRequest.State) async throws -> [HGPullRequest] {
        try await paged("repos/\(owner)/\(repo)/pulls?state=\(state.rawValue)&per_page=100&sort=updated") {
            try GitHub.decode([GitHub.PullRequestDTO].self, from: $0).map { $0.toModel() }
        }
    }

    public func pullRequest(owner: String, repo: String, number: Int) async throws -> HGPullRequest {
        let (data, _) = try await transport("repos/\(owner)/\(repo)/pulls/\(number)", [:])
        return try GitHub.decode(GitHub.PullRequestDTO.self, from: data).toModel()
    }

    public func pullRequestFiles(owner: String, repo: String, number: Int) async throws -> [HGFileChange] {
        try await paged("repos/\(owner)/\(repo)/pulls/\(number)/files?per_page=100") {
            try GitHub.decode([GitHub.PRFileDTO].self, from: $0).map { $0.toModel() }
        }
    }

    public func commits(owner: String, repo: String, branch: String?) async throws -> [HGCommit] {
        var resource = "repos/\(owner)/\(repo)/commits?per_page=100"
        if let branch { resource += "&sha=\(branch)" }
        return try await paged(resource) {
            try GitHub.decode([GitHub.CommitDTO].self, from: $0).map { $0.toModel() }
        }
    }

    public func issues(owner: String, repo: String, state: HGIssue.State) async throws -> [HGIssue] {
        try await paged("repos/\(owner)/\(repo)/issues?state=\(state.rawValue)&per_page=100&direction=desc") {
            // The issues endpoint also returns PRs; drop them.
            try GitHub.decode([GitHub.IssueDTO].self, from: $0)
                .filter { $0.pullRequest == nil }
                .map { $0.toModel() }
        }
    }

    public func issue(owner: String, repo: String, number: Int) async throws -> HGIssue {
        let (data, _) = try await transport("repos/\(owner)/\(repo)/issues/\(number)", [:])
        return try GitHub.decode(GitHub.IssueDTO.self, from: data).toModel()
    }

    // MARK: TicketSource (GitHub Issues surfaced as tickets across all repos)

    public func tickets() async throws -> [HGTicket] {
        try await paged("issues?filter=assigned&state=open&per_page=100") {
            try GitHub.decode([GitHub.IssueDTO].self, from: $0).map { $0.toTicket() }
        }
    }

    // MARK: Pagination

    /// Fetch `path` and keep following the `Link: rel="next"` relation, accumulating
    /// decoded items, up to `maxPages` pages.
    private func paged<T>(_ path: String, decode: (Data) throws -> [T]) async throws -> [T] {
        var result: [T] = []
        var nextPath: String? = path
        var pages = 0
        while let current = nextPath {
            pages += 1
            let (data, headers) = try await transport(current, [:])
            result.append(contentsOf: try decode(data))
            nextPath = (pages >= Self.maxPages) ? nil : Self.nextLink(from: headers["link"] ?? "")
        }
        return result
    }

    /// Parse the GitHub `Link` header → the `rel="next"` target as a path relative to
    /// baseURL (path + query), or nil when there is no next page. Pure + testable.
    static func nextLink(from linkHeader: String) -> String? {
        // Format: <https://api.github.com/x?page=2>; rel="next", <…>; rel="last"
        for segment in linkHeader.split(separator: ",") {
            let parts = segment.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 2,
                  let open = parts[0].firstIndex(of: "<"),
                  let close = parts[0].firstIndex(of: ">"),
                  open < close else { continue }
            let url = String(parts[0][parts[0].index(after: open)..<close])
            if parts.dropFirst().contains(where: { $0 == #"rel="next""# }) {
                return relativePath(from: url)
            }
        }
        return nil
    }

    /// Convert an absolute next-URL to a path (path + query) for the transport.
    private static func relativePath(from url: String) -> String {
        guard let comps = URLComponents(string: url), comps.host != nil else {
            return url.hasPrefix("/") ? String(url.dropFirst()) : url
        }
        var rel = comps.path.hasPrefix("/") ? String(comps.path.dropFirst()) : comps.path
        if let query = comps.query { rel += "?\(query)" }
        return rel
    }
}

// MARK: - GitHub DTO + decoding

enum GitHub {
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try decoder.decode(T.self, from: data) }
        catch { throw HTTPError.decoding(String(describing: error)) }
    }

    struct UserDTO: Decodable {
        let id: Int
        let login: String
        let name: String?
        let avatarUrl: String?
        let htmlUrl: String?
        enum CodingKeys: String, CodingKey {
            case id, login, name
            case avatarUrl = "avatar_url"
            case htmlUrl = "html_url"
        }
        func toModel() -> HGUser {
            HGUser(id: id, login: login, name: name,
                   avatarURL: avatarUrl.flatMap(URL.init(string:)),
                   htmlURL: htmlUrl.flatMap(URL.init(string:)))
        }
    }

    struct RepoDTO: Decodable {
        let id: Int
        let name: String
        let fullName: String
        let owner: UserDTO
        let description: String?
        let isPrivate: Bool
        let defaultBranch: String?
        let stargazersCount: Int
        let forksCount: Int
        let openIssuesCount: Int
        let updatedAt: Date?
        let sshUrl: String?
        let cloneUrl: String?
        let htmlUrl: String?
        let language: String?
        enum CodingKeys: String, CodingKey {
            case id, name, description, owner, language
            case fullName = "full_name"
            case isPrivate = "private"
            case defaultBranch = "default_branch"
            case stargazersCount = "stargazers_count"
            case forksCount = "forks_count"
            case openIssuesCount = "open_issues_count"
            case updatedAt = "updated_at"
            case sshUrl = "ssh_url"
            case cloneUrl = "clone_url"
            case htmlUrl = "html_url"
        }
        func toModel() -> HGRepo {
            HGRepo(id: id, name: name, fullName: fullName, owner: owner.toModel(),
                   description: description, isPrivate: isPrivate, defaultBranch: defaultBranch,
                   stargazersCount: stargazersCount, forksCount: forksCount,
                   openIssuesCount: openIssuesCount, updatedAt: updatedAt,
                   sshURL: sshUrl.flatMap(URL.init(string:)),
                   cloneURL: cloneUrl.flatMap(URL.init(string:)),
                   htmlURL: htmlUrl.flatMap(URL.init(string:)), language: language)
        }
    }

    struct TreeEntryDTO: Decodable {
        let path: String
        let type: String            // "blob" | "tree" | "commit"
        let sha: String
        let size: Int?
        func toModel() -> HGFileEntry? {
            guard let kind = HGFileEntry.Kind(rawValue: type) else { return nil }
            let name = (path as NSString).lastPathComponent
            return HGFileEntry(path: path, name: name, sha: sha, size: size, kind: kind)
        }
    }
    struct TreeDTO: Decodable { let tree: [TreeEntryDTO]; let truncated: Bool? }

    struct ContentDTO: Decodable {
        let path: String
        let sha: String
        let size: Int
        let encoding: String?       // "base64" expected for text
        let content: String?
        func toModel() throws -> HGFileContent {
            let encoded = (content ?? "").replacingOccurrences(of: "\n", with: "")
            // GitHub returns text files base64-encoded; decode now so .text yields the
            // real source rather than the base64 string.
            if (encoding ?? "").lowercased() == "base64",
               let decoded = Data(base64Encoded: encoded) {
                return HGFileContent(path: path, sha: sha, size: size, encoding: .utf8, raw: decoded)
            }
            let enc = HGFileContent.Encoding(rawValue: (encoding ?? "none").lowercased()) ?? .none
            return HGFileContent(path: path, sha: sha, size: size, encoding: enc, raw: Data(encoded.utf8))
        }
    }

    struct PullRequestDTO: Decodable {
        let id: Int
        let number: Int
        let title: String
        let body: String?
        let state: String
        let draft: Bool?
        let merged: Bool?
        let user: UserDTO?
        let head: RefDTO?
        let base: RefDTO?
        let additions: Int?
        let deletions: Int?
        let changedFiles: Int?
        let commits: Int?
        let comments: Int?
        let createdAt: Date?
        let updatedAt: Date?
        let mergedAt: Date?
        let htmlUrl: String?
        enum CodingKeys: String, CodingKey {
            case id, number, title, body, state, draft, merged, user, head, base, additions, deletions, commits
            case changedFiles = "changed_files"
            case comments
            case createdAt = "created_at"
            case updatedAt = "updated_at"
            case mergedAt = "merged_at"
            case htmlUrl = "html_url"
        }
        struct RefDTO: Decodable { let ref: String? }
        func toModel() -> HGPullRequest {
            HGPullRequest(id: id, number: number, title: title, body: body,
                          state: HGPullRequest.State(rawValue: state) ?? .open,
                          isDraft: draft ?? false, isMerged: merged ?? false,
                          author: user?.toModel(), head: head?.ref ?? "", base: base?.ref ?? "",
                          additions: additions ?? 0, deletions: deletions ?? 0,
                          changedFiles: changedFiles ?? 0, commits: commits ?? 0,
                          commentsCount: comments ?? 0, createdAt: createdAt, updatedAt: updatedAt,
                          mergedAt: mergedAt, htmlURL: htmlUrl.flatMap(URL.init(string:)))
        }
    }

    struct PRFileDTO: Decodable {
        let filename: String
        let previousFilename: String?
        let status: String
        let additions: Int
        let deletions: Int
        let patch: String?
        enum CodingKeys: String, CodingKey {
            case filename, status, additions, deletions, patch
            case previousFilename = "previous_filename"
        }
        func toModel() -> HGFileChange {
            HGFileChange(path: filename, previousPath: previousFilename,
                         status: HGFileChange.Status(rawValue: status) ?? .modified,
                         additions: additions, deletions: deletions, patch: patch)
        }
    }

    struct CommitDTO: Decodable {
        let sha: String
        let commit: CommitInner
        let author: UserDTO?
        let htmlUrl: String?
        enum CodingKeys: String, CodingKey { case sha, commit, author
            case htmlUrl = "html_url" }
        struct CommitInner: Decodable {
            let message: String
            let author: CommitAuthor
        }
        struct CommitAuthor: Decodable { let name: String?; let date: Date? }
        func toModel() -> HGCommit {
            HGCommit(sha: sha, message: commit.message,
                     authorName: commit.author.name, authorLogin: author?.login,
                     authorAvatarURL: author?.avatarUrl.flatMap(URL.init(string:)),
                     date: commit.author.date,
                     htmlURL: htmlUrl.flatMap(URL.init(string:)))
        }
    }

    struct LabelDTO: Decodable { let id: Int; let name: String; let color: String }

    struct IssueDTO: Decodable {
        let id: Int
        let number: Int
        let title: String
        let body: String?
        let state: String
        let user: UserDTO?
        let assignees: [UserDTO]?
        let labels: [LabelDTO]?
        let comments: Int?
        let createdAt: Date?
        let updatedAt: Date?
        let htmlUrl: String?
        let pullRequest: PRMarker?
        enum CodingKeys: String, CodingKey {
            case id, number, title, body, state, user, assignees, labels, comments
            case createdAt = "created_at"
            case updatedAt = "updated_at"
            case htmlUrl = "html_url"
            case pullRequest = "pull_request"
        }
        struct PRMarker: Decodable { let url: String? }
        func toModel() -> HGIssue {
            HGIssue(id: id, number: number, title: title, body: body,
                    state: HGIssue.State(rawValue: state) ?? .open,
                    author: user?.toModel(),
                    assignees: (assignees ?? []).map { $0.toModel() },
                    labels: (labels ?? []).map { HGLabel(id: $0.id, name: $0.name, color: $0.color) },
                    commentsCount: comments ?? 0, createdAt: createdAt, updatedAt: updatedAt,
                    htmlURL: htmlUrl.flatMap(URL.init(string:)))
        }
        func toTicket() -> HGTicket {
            HGTicket(id: "github-\(id)", source: .github,
                     identifier: "#\(number)", title: title,
                     stateName: state, team: nil, assignee: user?.toModel(),
                     labels: (labels ?? []).map(\.name),
                     url: htmlUrl.flatMap(URL.init(string:)), updatedAt: updatedAt)
        }
    }
}
