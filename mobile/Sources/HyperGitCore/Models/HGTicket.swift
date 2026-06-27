// HGTicket — unified tracker item across sources (GitHub Issues, Linear).
// Distinct from HGIssue so Linear and GitHub can be rendered in one inbox without
// leaking source-specific shape; clients map their payloads into this.
import Foundation

public struct HGTicket: Identifiable, Hashable, Sendable {
    public enum Source: String, Sendable { case github, linear }

    public let id: String
    public let source: Source
    public let identifier: String
    public let title: String
    public let stateName: String
    public let team: String?
    public let assignee: HGUser?
    public let labels: [String]
    public let url: URL?
    public let updatedAt: Date?

    public init(
        id: String, source: Source, identifier: String, title: String, stateName: String,
        team: String?, assignee: HGUser?, labels: [String], url: URL?, updatedAt: Date?
    ) {
        self.id = id
        self.source = source
        self.identifier = identifier
        self.title = title
        self.stateName = stateName
        self.team = team
        self.assignee = assignee
        self.labels = labels
        self.url = url
        self.updatedAt = updatedAt
    }
}
