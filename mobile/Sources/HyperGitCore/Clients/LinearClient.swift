// LinearClient — TicketSource over the Linear GraphQL API (read-only on MVP).
// Supports both Personal API keys and OAuth 2.0 tokens. Two-way sync is an open
// question (SPEC §9). SPEC §2.2.
import Foundation

public typealias LinearTransport = @Sendable (_ body: Data, _ headers: [String: String]) async throws -> Data

public enum LinearClientError: Error, Equatable, Sendable {
    case graphQLErrors([String])
    case paginationLimitExceeded(maxPages: Int, partialTickets: [HGTicket])
}

public struct LinearClient: TicketSource {
    public var displayName: String { "Linear" }

    public let endpoint: URL
    public let tokenProvider: @Sendable () -> String?
    public let oauthAccessTokenProvider: AccessTokenProvider?
    public let session: URLSession
    public let transport: LinearTransport
    public let maxPages: Int
    private let tokenStore: (any TokenStore)?

    public init(
        endpoint: URL = URL(string: "https://api.linear.app/graphql")!,
        tokenProvider: @escaping @Sendable () -> String?,
        oauthAccessTokenProvider: AccessTokenProvider? = nil,
        transport: LinearTransport? = nil,
        session: URLSession = .shared,
        tokenStore: (any TokenStore)? = nil,
        maxPages: Int = Self.defaultMaxPages
    ) {
        self.endpoint = endpoint
        self.tokenProvider = tokenProvider
        self.oauthAccessTokenProvider = oauthAccessTokenProvider
        self.session = session
        self.transport = transport ?? Self.urlSessionTransport(endpoint: endpoint, session: session)
        self.tokenStore = tokenStore
        self.maxPages = maxPages
    }

    public static let pageSize = 50
    public static let defaultMaxPages = 10

    public func tickets() async throws -> [HGTicket] {
        var result: [HGTicket] = []
        var after: String?
        var pages = 0
        var hasNextPage = true

        while hasNextPage, pages < maxPages {
            guard let token = try await authorizationToken() else { throw HTTPError.unauthorized }
            pages += 1
            let data = try await ticketPageData(first: Self.pageSize, after: after, token: token)
            let decoded = try Linear.decode(GraphQLResponse.self, from: data)
            if let errors = decoded.errors, !errors.isEmpty {
                throw LinearClientError.graphQLErrors(errors.map(\.message))
            }
            guard let issues = decoded.data?.issues else {
                throw HTTPError.decoding("Missing Linear issues data")
            }

            result.append(contentsOf: issues.nodes.map { $0.toTicket() })
            hasNextPage = issues.pageInfo.hasNextPage
            if hasNextPage {
                guard let cursor = issues.pageInfo.endCursor, !cursor.isEmpty else {
                    throw HTTPError.decoding("Missing Linear pagination cursor")
                }
                after = cursor
            }
        }

        if hasNextPage {
            throw LinearClientError.paginationLimitExceeded(maxPages: maxPages, partialTickets: result)
        }

        return result
    }

    static let ticketsQuery = """
    query MobileTickets($first: Int!, $after: String) {
      issues(first: $first, after: $after, orderBy: updatedAt) {
        nodes {
          id identifier title state { name }
          team { key name }
          assignee { id name displayName avatarUrl }
          labels(first: 10) { nodes { name } }
          url updatedAt
        }
        pageInfo { hasNextPage endCursor }
      }
    }
    """

    private func authorizationToken() async throws -> String? {
        if let manual = AuthTokenSelection.manualToken(tokenProvider()) {
            return manual
        }
        if let oauthAccessTokenProvider {
            return try await oauthAccessTokenProvider()
        }
        return AuthTokenSelection.accessToken(tokenStore?.oauthTokens(for: .linear))
    }

    private func ticketPageData(first: Int, after: String?, token: String) async throws -> Data {
        var variables: [String: Any] = ["first": first]
        if let after { variables["after"] = after }
        let payload = try JSONSerialization.data(withJSONObject: [
            "query": Self.ticketsQuery,
            "variables": variables,
        ])
        return try await transport(payload, [
            "Content-Type": "application/json",
            "User-Agent": "HyperGitMobile/0.1",
            "Authorization": "Bearer \(token)",
        ])
    }

    private static func urlSessionTransport(endpoint: URL, session: URLSession) -> LinearTransport {
        { body, headers in
            var req = URLRequest(url: endpoint)
            req.httpMethod = "POST"
            req.httpBody = body
            for (key, value) in headers { req.setValue(value, forHTTPHeaderField: key) }

            let (data, resp): (Data, URLResponse)
            do { (data, resp) = try await session.data(for: req) }
            catch { throw HTTPError.invalidResponse }

            guard let http = resp as? HTTPURLResponse else { throw HTTPError.invalidResponse }
            switch http.statusCode {
            case 200..<300: return data
            case 401: throw HTTPError.unauthorized
            case 403: throw HTTPError.forbidden
            default: throw HTTPError.badStatus(http.statusCode)
            }
        }
    }

    // MARK: - GraphQL response shapes

    struct GraphQLResponse: Decodable {
        let data: DataRoot?
        let errors: [GraphQLError]?
    }
    struct GraphQLError: Decodable { let message: String }
    struct DataRoot: Decodable { let issues: IssuesConnection }
    struct IssuesConnection: Decodable {
        let nodes: [IssueNode]
        let pageInfo: PageInfo
    }
    struct PageInfo: Decodable {
        let hasNextPage: Bool
        let endCursor: String?
    }
    struct IssueNode: Decodable {
        let id: String
        let identifier: String
        let title: String
        let state: StateNode
        let team: TeamNode?
        let assignee: AssigneeNode?
        let labels: LabelsConnection
        let url: String?
        let updatedAt: String?
        struct StateNode: Decodable { let name: String }
        struct TeamNode: Decodable { let key: String; let name: String }
        struct AssigneeNode: Decodable {
            let id: String; let name: String?; let displayName: String?
            let avatarUrl: String?
        }
        struct LabelsConnection: Decodable { let nodes: [LabelNode] }
        struct LabelNode: Decodable { let name: String }

        func toTicket() -> HGTicket {
            let assignee = self.assignee.map {
                HGUser(id: abs($0.id.djb2),
                       login: $0.displayName ?? $0.name ?? "unknown",
                       name: $0.displayName, avatarURL: nil, htmlURL: nil)
            }
            return HGTicket(id: "linear-\(id)", source: .linear, identifier: identifier,
                            title: title, stateName: state.name, team: team?.name,
                            assignee: assignee, labels: labels.nodes.map(\.name),
                            url: url.flatMap(URL.init(string:)),
                            updatedAt: updatedAt.flatMap(Linear.parseDate))
        }
    }
}

enum Linear {
    static let decoder: JSONDecoder = JSONDecoder()

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try decoder.decode(T.self, from: data) }
        catch { throw HTTPError.decoding(String(describing: error)) }
    }

    /// Parse Linear's ISO8601 timestamps, tolerating optional fractional seconds.
    static func parseDate(_ s: String) -> Date? {
        let formats = ["yyyy-MM-dd'T'HH:mm:ss.SSS'Z'",
                       "yyyy-MM-dd'T'HH:mm:ss'Z'",
                       "yyyy-MM-dd'T'HH:mm:ssZ"]
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        for fmt in formats { f.dateFormat = fmt; if let d = f.date(from: s) { return d } }
        return nil
    }
}

private extension String {
    /// Stable, non-cryptographic 32-bit hash for deriving an Int id from a UUID string.
    var djb2: Int {
        var hash: UInt64 = 5381
        for byte in utf8 { hash = (hash &<< 5) &+ hash &+ UInt64(byte) }
        return Int(truncatingIfNeeded: hash)
    }
}
