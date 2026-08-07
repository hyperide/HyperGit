// CachePayloads — Codable mirrors of the HG* domain structs, used to (de)serialize
// cached collections to JSON before they're stored in a SwiftDataCacheStore row.
// The HG* types themselves aren't Codable (they're the network-decoding target, not
// the persistence target), so this is a small, explicit translation layer instead of
// retrofitting Codable onto the domain models.
import Foundation

struct CachedUserPayload: Codable, Sendable {
    let id: Int
    let login: String
    let name: String?
    let avatarURL: URL?
    let htmlURL: URL?
}

extension CachedUserPayload {
    init(_ user: HGUser) {
        id = user.id
        login = user.login
        name = user.name
        avatarURL = user.avatarURL
        htmlURL = user.htmlURL
    }

    var model: HGUser {
        HGUser(id: id, login: login, name: name, avatarURL: avatarURL, htmlURL: htmlURL)
    }
}

struct CachedLabelPayload: Codable, Sendable {
    let id: Int
    let name: String
    let color: String
}

extension CachedLabelPayload {
    init(_ label: HGLabel) {
        id = label.id
        name = label.name
        color = label.color
    }

    var model: HGLabel { HGLabel(id: id, name: name, color: color) }
}

struct CachedRepoPayload: Codable, Sendable {
    let id: Int
    let name: String
    let fullName: String
    let owner: CachedUserPayload
    let description: String?
    let isPrivate: Bool
    let defaultBranch: String?
    let stargazersCount: Int
    let forksCount: Int
    let openIssuesCount: Int
    let updatedAt: Date?
    let sshURL: URL?
    let cloneURL: URL?
    let htmlURL: URL?
    let language: String?
}

extension CachedRepoPayload {
    init(_ repo: HGRepo) {
        id = repo.id
        name = repo.name
        fullName = repo.fullName
        owner = CachedUserPayload(repo.owner)
        description = repo.description
        isPrivate = repo.isPrivate
        defaultBranch = repo.defaultBranch
        stargazersCount = repo.stargazersCount
        forksCount = repo.forksCount
        openIssuesCount = repo.openIssuesCount
        updatedAt = repo.updatedAt
        sshURL = repo.sshURL
        cloneURL = repo.cloneURL
        htmlURL = repo.htmlURL
        language = repo.language
    }

    var model: HGRepo {
        HGRepo(
            id: id, name: name, fullName: fullName, owner: owner.model, description: description,
            isPrivate: isPrivate, defaultBranch: defaultBranch, stargazersCount: stargazersCount,
            forksCount: forksCount, openIssuesCount: openIssuesCount, updatedAt: updatedAt,
            sshURL: sshURL, cloneURL: cloneURL, htmlURL: htmlURL, language: language
        )
    }
}

struct CachedFileEntryPayload: Codable, Sendable {
    let path: String
    let name: String
    let sha: String
    let size: Int?
    let kind: String
}

extension CachedFileEntryPayload {
    init(_ entry: HGFileEntry) {
        path = entry.path
        name = entry.name
        sha = entry.sha
        size = entry.size
        kind = entry.kind.rawValue
    }

    var model: HGFileEntry {
        HGFileEntry(path: path, name: name, sha: sha, size: size, kind: HGFileEntry.Kind(rawValue: kind) ?? .file)
    }
}

struct CachedPullRequestPayload: Codable, Sendable {
    let id: Int
    let number: Int
    let title: String
    let body: String?
    let state: String
    let isDraft: Bool
    let isMerged: Bool
    let author: CachedUserPayload?
    let head: String
    let base: String
    let additions: Int
    let deletions: Int
    let changedFiles: Int
    let commits: Int
    let commentsCount: Int
    let createdAt: Date?
    let updatedAt: Date?
    let mergedAt: Date?
    let htmlURL: URL?
}

extension CachedPullRequestPayload {
    init(_ pr: HGPullRequest) {
        id = pr.id
        number = pr.number
        title = pr.title
        body = pr.body
        state = pr.state.rawValue
        isDraft = pr.isDraft
        isMerged = pr.isMerged
        author = pr.author.map(CachedUserPayload.init)
        head = pr.head
        base = pr.base
        additions = pr.additions
        deletions = pr.deletions
        changedFiles = pr.changedFiles
        commits = pr.commits
        commentsCount = pr.commentsCount
        createdAt = pr.createdAt
        updatedAt = pr.updatedAt
        mergedAt = pr.mergedAt
        htmlURL = pr.htmlURL
    }

    var model: HGPullRequest {
        HGPullRequest(
            id: id, number: number, title: title, body: body,
            state: HGPullRequest.State(rawValue: state) ?? .open,
            isDraft: isDraft, isMerged: isMerged, author: author?.model,
            head: head, base: base, additions: additions, deletions: deletions,
            changedFiles: changedFiles, commits: commits, commentsCount: commentsCount,
            createdAt: createdAt, updatedAt: updatedAt, mergedAt: mergedAt, htmlURL: htmlURL
        )
    }
}

struct CachedIssuePayload: Codable, Sendable {
    let id: Int
    let number: Int
    let title: String
    let body: String?
    let state: String
    let author: CachedUserPayload?
    let assignees: [CachedUserPayload]
    let labels: [CachedLabelPayload]
    let commentsCount: Int
    let createdAt: Date?
    let updatedAt: Date?
    let htmlURL: URL?
}

extension CachedIssuePayload {
    init(_ issue: HGIssue) {
        id = issue.id
        number = issue.number
        title = issue.title
        body = issue.body
        state = issue.state.rawValue
        author = issue.author.map(CachedUserPayload.init)
        assignees = issue.assignees.map(CachedUserPayload.init)
        labels = issue.labels.map(CachedLabelPayload.init)
        commentsCount = issue.commentsCount
        createdAt = issue.createdAt
        updatedAt = issue.updatedAt
        htmlURL = issue.htmlURL
    }

    var model: HGIssue {
        HGIssue(
            id: id, number: number, title: title, body: body,
            state: HGIssue.State(rawValue: state) ?? .open,
            author: author?.model, assignees: assignees.map(\.model), labels: labels.map(\.model),
            commentsCount: commentsCount, createdAt: createdAt, updatedAt: updatedAt, htmlURL: htmlURL
        )
    }
}

struct CachedTicketPayload: Codable, Sendable {
    let id: String
    let source: String
    let identifier: String
    let title: String
    let stateName: String
    let team: String?
    let assignee: CachedUserPayload?
    let labels: [String]
    let url: URL?
    let updatedAt: Date?
}

extension CachedTicketPayload {
    init(_ ticket: HGTicket) {
        id = ticket.id
        source = ticket.source.rawValue
        identifier = ticket.identifier
        title = ticket.title
        stateName = ticket.stateName
        team = ticket.team
        assignee = ticket.assignee.map(CachedUserPayload.init)
        labels = ticket.labels
        url = ticket.url
        updatedAt = ticket.updatedAt
    }

    var model: HGTicket {
        HGTicket(
            id: id, source: HGTicket.Source(rawValue: source) ?? .github, identifier: identifier,
            title: title, stateName: stateName, team: team, assignee: assignee?.model,
            labels: labels, url: url, updatedAt: updatedAt
        )
    }
}
