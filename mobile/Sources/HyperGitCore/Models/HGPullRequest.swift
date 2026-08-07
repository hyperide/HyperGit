// HGPullRequest — a pull request and its changed files.
import Foundation

public struct HGPullRequest: Identifiable, Hashable, Sendable {
    public enum State: String, Sendable, CaseIterable { case open, closed, all }

    public let id: Int
    public let number: Int
    public let title: String
    public let body: String?
    public let state: State
    public let isDraft: Bool
    public let isMerged: Bool
    public let author: HGUser?
    public let head: String
    /// Head commit SHA, when the API provided one — needed to look up check
    /// runs by commit rather than by branch name (which can be ambiguous or
    /// absent for a forked-repo PR).
    public let headSHA: String?
    public let base: String
    public let additions: Int
    public let deletions: Int
    public let changedFiles: Int
    public let commits: Int
    public let commentsCount: Int
    public let createdAt: Date?
    public let updatedAt: Date?
    public let mergedAt: Date?
    public let htmlURL: URL?

    public init(
        id: Int, number: Int, title: String, body: String?, state: State, isDraft: Bool, isMerged: Bool,
        author: HGUser?, head: String, headSHA: String? = nil, base: String, additions: Int, deletions: Int,
        changedFiles: Int, commits: Int, commentsCount: Int, createdAt: Date?, updatedAt: Date?,
        mergedAt: Date?, htmlURL: URL?
    ) {
        self.id = id
        self.number = number
        self.title = title
        self.body = body
        self.state = state
        self.isDraft = isDraft
        self.isMerged = isMerged
        self.author = author
        self.head = head
        self.headSHA = headSHA
        self.base = base
        self.additions = additions
        self.deletions = deletions
        self.changedFiles = changedFiles
        self.commits = commits
        self.commentsCount = commentsCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.mergedAt = mergedAt
        self.htmlURL = htmlURL
    }

    public var displayState: String {
        if isMerged { return "merged" }
        if isDraft { return "draft" }
        return state.rawValue
    }

    /// The ref to fetch check runs against — the head commit SHA, or `nil`
    /// when it isn't known. Deliberately does NOT fall back to the head
    /// branch name: for a forked-repo PR that name refers to a branch in the
    /// fork, not this repo, so querying it here would silently return the
    /// wrong (or a 404) result instead of no result. A `nil` checksRef means
    /// "don't fetch checks for this PR", not "fetch by branch name instead".
    public var checksRef: String? { headSHA }
}
