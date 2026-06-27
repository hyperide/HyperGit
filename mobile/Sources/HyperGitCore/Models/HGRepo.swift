// HGRepo — a repository (GitHub or, later, HyperGit backend).
import Foundation

public struct HGRepo: Identifiable, Hashable, Sendable {
    public let id: Int
    public let name: String
    public let fullName: String
    public let owner: HGUser
    public let description: String?
    public let isPrivate: Bool
    public let defaultBranch: String?
    public let stargazersCount: Int
    public let forksCount: Int
    public let openIssuesCount: Int
    public let updatedAt: Date?
    public let sshURL: URL?
    public let cloneURL: URL?
    public let htmlURL: URL?
    public let language: String?

    /// Stable accessor for owner/name used across API paths.
    public var ownerLogin: String { owner.login }

    public init(
        id: Int,
        name: String,
        fullName: String,
        owner: HGUser,
        description: String?,
        isPrivate: Bool,
        defaultBranch: String?,
        stargazersCount: Int,
        forksCount: Int,
        openIssuesCount: Int,
        updatedAt: Date?,
        sshURL: URL?,
        cloneURL: URL?,
        htmlURL: URL?,
        language: String?
    ) {
        self.id = id
        self.name = name
        self.fullName = fullName
        self.owner = owner
        self.description = description
        self.isPrivate = isPrivate
        self.defaultBranch = defaultBranch
        self.stargazersCount = stargazersCount
        self.forksCount = forksCount
        self.openIssuesCount = openIssuesCount
        self.updatedAt = updatedAt
        self.sshURL = sshURL
        self.cloneURL = cloneURL
        self.htmlURL = htmlURL
        self.language = language
    }
}
