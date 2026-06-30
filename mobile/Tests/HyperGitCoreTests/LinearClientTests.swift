// LinearClient tests cover real GraphQL decoding/mapping and pagination through
// an injected transport. The transport is the only fake boundary; no network.
import Foundation
import Testing
@testable import HyperGitCore

@Suite("LinearClient GraphQL tickets")
struct LinearClientTests {
    @Test("tickets maps Linear GraphQL issues")
    func ticketsMapping() async throws {
        let recorder = LinearRequestRecorder()
        let client = LinearClient(tokenProvider: { "linear-token" }, transport: { body, headers in
            try await recorder.record(body: body, headers: headers)
            return Self.page(
                nodes: [Self.issueNode(id: "issue-1", identifier: "ENG-1", title: "Ship client")],
                hasNextPage: false,
                endCursor: nil
            )
        })

        let tickets = try await client.tickets()

        #expect(tickets.count == 1)
        #expect(tickets[0].id == "linear-issue-1")
        #expect(tickets[0].source == HGTicket.Source.linear)
        #expect(tickets[0].identifier == "ENG-1")
        #expect(tickets[0].title == "Ship client")
        #expect(tickets[0].stateName == "Todo")
        #expect(tickets[0].team == "Engineering")
        #expect(tickets[0].labels == ["mobile"])

        let requests = await recorder.requests
        #expect(requests.count == 1)
        #expect(requests[0].headers["Authorization"] == "Bearer linear-token")
        #expect(requests[0].headers["Content-Type"] == "application/json")
        #expect(requests[0].payload.variables.first == 50)
        #expect(requests[0].payload.variables.after == nil)
    }

    @Test("tickets throws GraphQL errors")
    func ticketsGraphQLErrors() async throws {
        let client = LinearClient(tokenProvider: { "linear-token" }, transport: { _, _ in
            Data(#"{"errors":[{"message":"Linear query failed"}]}"#.utf8)
        })

        var caught: Error?
        do { _ = try await client.tickets() } catch { caught = error }

        #expect((caught as? LinearClientError) == .graphQLErrors(["Linear query failed"]))
    }

    @Test("tickets follows Linear pageInfo cursor pagination")
    func ticketsPagination() async throws {
        let recorder = LinearRequestRecorder()
        let client = LinearClient(tokenProvider: { "linear-token" }, transport: { body, headers in
            try await recorder.record(body: body, headers: headers)
            let payload = try LinearRequestPayload.decode(from: body)
            if payload.variables.after == "cursor-1" {
                return Self.page(
                    nodes: [Self.issueNode(id: "issue-2", identifier: "ENG-2", title: "Second page")],
                    hasNextPage: false,
                    endCursor: nil
                )
            }
            return Self.page(
                nodes: [Self.issueNode(id: "issue-1", identifier: "ENG-1", title: "First page")],
                hasNextPage: true,
                endCursor: "cursor-1"
            )
        })

        let tickets = try await client.tickets()

        #expect(tickets.map { $0.identifier } == ["ENG-1", "ENG-2"])

        let requests = await recorder.requests
        #expect(requests.count == 2)
        #expect(requests[0].payload.variables.after == nil)
        #expect(requests[1].payload.variables.after == "cursor-1")
    }

    @Test("manual API key takes precedence over stored OAuth token")
    func manualTokenPrecedence() async throws {
        let tokenStore = InMemoryTokenStore()
        try tokenStore.setOAuthTokens(
            OAuthTokens(
                accessToken: "expired-oauth-token",
                refreshToken: "refresh-token",
                expiresAt: Date(timeIntervalSince1970: 0)
            ),
            for: .linear
        )

        let recorder = LinearRequestRecorder()
        let client = LinearClient(
            tokenProvider: { "manual-token" },
            oauthAccessTokenProvider: { "refreshed-oauth-token" },
            transport: { body, headers in
                try await recorder.record(body: body, headers: headers)
                return Self.page(
                    nodes: [Self.issueNode(id: "issue-1", identifier: "ENG-1", title: "Manual token")],
                    hasNextPage: false,
                    endCursor: nil
                )
            },
            tokenStore: tokenStore
        )

        _ = try await client.tickets()

        let requests = await recorder.requests
        #expect(requests[0].headers["Authorization"] == "Bearer manual-token")
    }

    @Test("expired OAuth token uses async refresh provider")
    func expiredOAuthUsesRefreshProvider() async throws {
        let tokenStore = InMemoryTokenStore()
        try tokenStore.setOAuthTokens(
            OAuthTokens(
                accessToken: "expired-oauth-token",
                refreshToken: "refresh-token",
                expiresAt: Date(timeIntervalSince1970: 0)
            ),
            for: .linear
        )

        let recorder = LinearRequestRecorder()
        let client = LinearClient(
            tokenProvider: { nil },
            oauthAccessTokenProvider: { "refreshed-oauth-token" },
            transport: { body, headers in
                try await recorder.record(body: body, headers: headers)
                return Self.page(
                    nodes: [Self.issueNode(id: "issue-1", identifier: "ENG-1", title: "Refreshed")],
                    hasNextPage: false,
                    endCursor: nil
                )
            },
            tokenStore: tokenStore
        )

        _ = try await client.tickets()

        let requests = await recorder.requests
        #expect(requests[0].headers["Authorization"] == "Bearer refreshed-oauth-token")
    }

    @Test("token provider is evaluated for each Linear page")
    func tokenProviderEvaluatedPerPage() async throws {
        let tokenSequence = TokenSequence(["first-token", "second-token"])
        let recorder = LinearRequestRecorder()
        let client = LinearClient(tokenProvider: { tokenSequence.next() }, transport: { body, headers in
            try await recorder.record(body: body, headers: headers)
            let payload = try LinearRequestPayload.decode(from: body)
            if payload.variables.after == "cursor-1" {
                return Self.page(
                    nodes: [Self.issueNode(id: "issue-2", identifier: "ENG-2", title: "Second page")],
                    hasNextPage: false,
                    endCursor: nil
                )
            }
            return Self.page(
                nodes: [Self.issueNode(id: "issue-1", identifier: "ENG-1", title: "First page")],
                hasNextPage: true,
                endCursor: "cursor-1"
            )
        })

        _ = try await client.tickets()

        let requests = await recorder.requests
        #expect(requests.map { $0.headers["Authorization"] } == ["Bearer first-token", "Bearer second-token"])
    }

    @Test("tickets reports pagination limit instead of truncating")
    func paginationLimitExceeded() async throws {
        let client = LinearClient(tokenProvider: { "linear-token" }, transport: { _, _ in
            Self.page(
                nodes: [Self.issueNode(id: "issue-1", identifier: "ENG-1", title: "Loop")],
                hasNextPage: true,
                endCursor: "cursor-1"
            )
        }, maxPages: 1)

        var caught: Error?
        do { _ = try await client.tickets() } catch { caught = error }

        guard case .paginationLimitExceeded(maxPages: 1, partialTickets: let tickets) = caught as? LinearClientError else {
            Issue.record("Expected pagination limit error")
            return
        }
        #expect(tickets.map(\.identifier) == ["ENG-1"])
    }

    private static func page(nodes: [String], hasNextPage: Bool, endCursor: String?) -> Data {
        let cursorValue = endCursor.map { #""\#($0)""# } ?? "null"
        return Data(#"""
        {
          "data": {
            "issues": {
              "nodes": [\#(nodes.joined(separator: ","))],
              "pageInfo": {
                "hasNextPage": \#(hasNextPage),
                "endCursor": \#(cursorValue)
              }
            }
          }
        }
        """#.utf8)
    }

    private static func issueNode(id: String, identifier: String, title: String) -> String {
        #"""
        {
          "id": "\#(id)",
          "identifier": "\#(identifier)",
          "title": "\#(title)",
          "state": { "name": "Todo" },
          "team": { "key": "ENG", "name": "Engineering" },
          "assignee": null,
          "labels": { "nodes": [{ "name": "mobile" }] },
          "url": "https://linear.app/hypergit/issue/\#(identifier)",
          "updatedAt": "2024-01-02T03:04:05Z"
        }
        """#
    }
}

private actor LinearRequestRecorder {
    private(set) var requests: [RecordedLinearRequest] = []

    func record(body: Data, headers: [String: String]) throws {
        let payload = try LinearRequestPayload.decode(from: body)
        requests.append(RecordedLinearRequest(payload: payload, headers: headers))
    }
}

private struct RecordedLinearRequest: Sendable {
    let payload: LinearRequestPayload
    let headers: [String: String]
}

private struct LinearRequestPayload: Decodable, Sendable {
    let query: String
    let variables: Variables

    static func decode(from data: Data) throws -> Self {
        try JSONDecoder().decode(Self.self, from: data)
    }

    struct Variables: Decodable, Sendable {
        let first: Int
        let after: String?
    }
}

private final class TokenSequence: @unchecked Sendable {
    private let lock = NSLock()
    private let tokens: [String]
    private var index = 0

    init(_ tokens: [String]) {
        self.tokens = tokens
    }

    func next() -> String {
        lock.lock()
        defer { lock.unlock() }
        let token = tokens[min(index, tokens.count - 1)]
        index += 1
        return token
    }
}
