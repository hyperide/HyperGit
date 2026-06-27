// HGDiff — unified diff representation for PRs/files (line-level now; semantic
// diff via tree-sitter is a Phase-2 enhancement, SPEC §2.2).
import Foundation

public struct HGFileChange: Identifiable, Hashable, Sendable {
    public enum Status: String, Sendable { case added, removed, modified, renamed, copied, changed = "changed" }

    public let id = UUID()
    public let path: String
    public let previousPath: String?
    public let status: Status
    public let additions: Int
    public let deletions: Int
    public let patch: String?

    public init(path: String, previousPath: String?, status: Status, additions: Int, deletions: Int, patch: String?) {
        self.path = path
        self.previousPath = previousPath
        self.status = status
        self.additions = additions
        self.deletions = deletions
        self.patch = patch
    }
}
