// HGCommit — a git commit (lightweight, for history lists).
import Foundation

public struct HGCommit: Identifiable, Hashable, Sendable {
    public let id = UUID()
    public let sha: String
    public let message: String
    public let authorName: String?
    public let authorLogin: String?
    public let authorAvatarURL: URL?
    public let date: Date?
    public let htmlURL: URL?

    public init(sha: String, message: String, authorName: String?, authorLogin: String?, authorAvatarURL: URL?, date: Date?, htmlURL: URL?) {
        self.sha = sha
        self.message = message
        self.authorName = authorName
        self.authorLogin = authorLogin
        self.authorAvatarURL = authorAvatarURL
        self.date = date
        self.htmlURL = htmlURL
    }

    public var shortSHA: String { String(sha.prefix(7)) }
    public var subject: String { message.split(separator: "\n").first.map(String.init) ?? message }
}
