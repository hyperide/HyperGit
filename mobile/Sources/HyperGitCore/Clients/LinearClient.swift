// LinearClient — TicketSource over the Linear GraphQL API (read-only on MVP).
// Supports both Personal API keys and OAuth 2.0 tokens. Two-way sync is an open
// question (SPEC §9). SPEC §2.2.
import Foundation

public struct LinearClient: TicketSource {
    public var displayName: String { "Linear" }

    public let endpoint: URL
    public let tokenProvider: @Sendable () -> String?
    public let session: URLSession
    private let tokenStore: (any TokenStore)?

    public init(
        endpoint: URL = URL(string: "https://api.linear.app/graphql")!,
        tokenProvider: @escaping @Sendable () -> String?,
        session: URLSession = .shared,
        tokenStore: (any TokenStore)? = nil
    ) {
        self.endpoint = endpoint
        self.tokenProvider = tokenProvider
        self.session = session
        self.tokenStore = tokenStore
    }

    public func tickets() async throws -> [HGTicket] {
        // Try OAuth token first, fallback to API key
        let token: String?
        if let store = tokenStore,
           let oauth = store.oauthTokens(for: .linear) {
            let accessToken = oauth.accessToken
            if !accessToken.isEmpty {
                token = accessToken
            } else {
                token = tokenProvider()
            }
        } else {
            token = tokenProvider()
        }

        guard let token else { throw HTTPError.unauthorized }

        let payload = try JSONSerialization.data(withJSONObject: [
            "query": Self.ticketsQuery,
            "variables": ["first": 50] as [String: Any],
        ])
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("HyperGitMobile/0.1", forHTTPHeaderField: "User-Agent")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = payload

        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await session.data(for: req) }
        catch { throw HTTPError.invalidResponse }

        guard let http = resp as? HTTPURLResponse else { throw HTTPError.invalidResponse }
        switch http.statusCode {
        case 200..<300: break
        case 401: throw HTTPError.unauthorized
        case 403: throw HTTPError.forbidden
        default: throw HTTPError.badStatus(http.statusCode)
        }

        let decoded = try Linear.decoder.decode(GraphQLResponse.self, from: data)
        return decoded.data.issues.nodes.map { $0.toTicket() }
    }

    static let ticketsQuery = """
    query MobileTickets($first: Int!) {
      issues(first: $first, orderBy: updatedAt) {
        nodes {
          id identifier title state { name }
          team { key name }
          assignee { id name displayName avatarUrl }
          labels(first: 10) { nodes { name } }
          url updatedAt
        }
      }
    }
    """

    // MARK: - GraphQL response shapes

    struct GraphQLResponse: Decodable { let data: DataRoot }
    struct DataRoot: Decodable { let issues: IssuesConnection }
    struct IssuesConnection: Decodable { let nodes: [IssueNode] }
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