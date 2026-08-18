// CachePayloads round-trip tests — pure Codable mapping, no SwiftData involved, so
// these exercise the part of the persistence layer that's most likely to drift from
// the HG* domain models (a renamed/reordered field silently breaks the mapping).
import Foundation
import Testing
@testable import HyperGitCore

@Suite("CachePayloads")
struct CachePayloadsTests {
    @Test("HGRepo round-trips through CachedRepoPayload JSON")
    func repoRoundTrip() throws {
        let repo = HGRepo.samples[0]
        let data = try JSONEncoder().encode(CachedRepoPayload(repo))
        let decoded = try JSONDecoder().decode(CachedRepoPayload.self, from: data).model
        #expect(decoded == repo)
    }

    @Test("HGFileEntry round-trips and falls back to .file for an unknown kind")
    func fileEntryRoundTrip() throws {
        let entry = HGFileEntry(path: "src/a.swift", name: "a.swift", sha: "abc123", size: 42, kind: .dir)
        let data = try JSONEncoder().encode(CachedFileEntryPayload(entry))
        let decoded = try JSONDecoder().decode(CachedFileEntryPayload.self, from: data).model
        #expect(decoded.path == entry.path)
        #expect(decoded.kind == .dir)

        var payload = try JSONDecoder().decode(CachedFileEntryPayload.self, from: data)
        payload = CachedFileEntryPayload(path: payload.path, name: payload.name, sha: payload.sha, size: payload.size, kind: "bogus")
        #expect(payload.model.kind == .file)
    }

    @Test("HGPullRequest round-trips with a nil author")
    func pullRequestRoundTrip() throws {
        let pr = HGPullRequest.samples[0]
        let data = try JSONEncoder().encode(CachedPullRequestPayload(pr))
        let decoded = try JSONDecoder().decode(CachedPullRequestPayload.self, from: data).model
        #expect(decoded == pr)

        let noAuthor = HGPullRequest(
            id: 1, number: 1, title: "t", body: nil, state: .closed, isDraft: false, isMerged: true,
            author: nil, head: "h", base: "b", additions: 1, deletions: 2, changedFiles: 3, commits: 4,
            commentsCount: 5, createdAt: nil, updatedAt: nil, mergedAt: nil, htmlURL: nil
        )
        let data2 = try JSONEncoder().encode(CachedPullRequestPayload(noAuthor))
        let decoded2 = try JSONDecoder().decode(CachedPullRequestPayload.self, from: data2).model
        #expect(decoded2 == noAuthor)
    }

    @Test("HGIssue round-trips with assignees and labels")
    func issueRoundTrip() throws {
        let issue = HGIssue(
            id: 9, number: 9, title: "Bug", body: "steps", state: .open,
            author: HGUser(id: 1, login: "a", name: nil, avatarURL: nil, htmlURL: nil),
            assignees: [HGUser(id: 2, login: "b", name: "B", avatarURL: nil, htmlURL: nil)],
            labels: [HGLabel(id: 1, name: "bug", color: "ff0000")],
            commentsCount: 3, createdAt: Date(timeIntervalSince1970: 10), updatedAt: Date(timeIntervalSince1970: 20),
            htmlURL: URL(string: "https://example.com/issues/9")
        )
        let data = try JSONEncoder().encode(CachedIssuePayload(issue))
        let decoded = try JSONDecoder().decode(CachedIssuePayload.self, from: data).model
        #expect(decoded == issue)
    }

    @Test("HGTicket round-trips and falls back to .github for an unknown source")
    func ticketRoundTrip() throws {
        let ticket = HGTicket.samples[1]
        let data = try JSONEncoder().encode(CachedTicketPayload(ticket))
        let decoded = try JSONDecoder().decode(CachedTicketPayload.self, from: data).model
        #expect(decoded == ticket)

        var payload = CachedTicketPayload(ticket)
        payload = CachedTicketPayload(
            id: payload.id, source: "bogus", identifier: payload.identifier, title: payload.title,
            stateName: payload.stateName, team: payload.team, assignee: payload.assignee,
            labels: payload.labels, url: payload.url, updatedAt: payload.updatedAt
        )
        #expect(payload.model.source == .github)
    }
}
