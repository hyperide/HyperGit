// HGUser — a user/owner shared across sources (GitHub owner, PR/issue author, assignee).
import Foundation

public struct HGUser: Identifiable, Hashable, Sendable {
    public let id: Int
    public let login: String
    public let name: String?
    public let avatarURL: URL?
    public let htmlURL: URL?

    public init(id: Int, login: String, name: String?, avatarURL: URL?, htmlURL: URL?) {
        self.id = id
        self.login = login
        self.name = name
        self.avatarURL = avatarURL
        self.htmlURL = htmlURL
    }

    public var displayName: String { name?.nilIfEmpty ?? login }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
