// HGLabel + HGIssue — issue/tracker item (GitHub Issues; Linear maps to HGTicket).
import Foundation

public struct HGLabel: Identifiable, Hashable, Sendable {
    public let id: Int
    public let name: String
    public let color: String
    public init(id: Int, name: String, color: String) {
        self.id = id
        self.name = name
        self.color = color
    }
}

public struct HGIssue: Identifiable, Hashable, Sendable {
    public enum State: String, Sendable, CaseIterable { case open, closed, all }

    public let id: Int
    public let number: Int
    public let title: String
    public let body: String?
    public let state: State
    public let author: HGUser?
    public let assignees: [HGUser]
    public let labels: [HGLabel]
    public let commentsCount: Int
    public let createdAt: Date?
    public let updatedAt: Date?
    public let htmlURL: URL?

    public init(
        id: Int, number: Int, title: String, body: String?, state: State,
        author: HGUser?, assignees: [HGUser], labels: [HGLabel], commentsCount: Int,
        createdAt: Date?, updatedAt: Date?, htmlURL: URL?
    ) {
        self.id = id
        self.number = number
        self.title = title
        self.body = body
        self.state = state
        self.author = author
        self.assignees = assignees
        self.labels = labels
        self.commentsCount = commentsCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.htmlURL = htmlURL
    }
}
