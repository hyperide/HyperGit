// HGFile — file-tree entries and file content blobs.
import Foundation

public struct HGFileEntry: Identifiable, Hashable, Sendable {
    public enum Kind: String, Sendable { case file = "blob", dir = "tree", symlink = "symlink", submodule = "commit" }
    public let id = UUID()
    public let path: String
    public let name: String
    public let sha: String
    public let size: Int?
    public let kind: Kind

    public init(path: String, name: String, sha: String, size: Int?, kind: Kind) {
        self.path = path
        self.name = name
        self.sha = sha
        self.size = size
        self.kind = kind
    }

    public var ext: String? { (name as NSString).pathExtension.nilIfEmpty?.lowercased() }
}

public struct HGFileContent: Hashable, Sendable {
    public let path: String
    public let sha: String
    public let size: Int
    public let encoding: Encoding
    public let raw: Data

    public enum Encoding: String, Sendable { case base64, utf8 = "utf-8", none }

    public init(path: String, sha: String, size: Int, encoding: Encoding, raw: Data) {
        self.path = path
        self.sha = sha
        self.size = size
        self.encoding = encoding
        self.raw = raw
    }

    public var text: String? {
        switch encoding {
        case .base64: return String(data: raw, encoding: .utf8) ?? raw.base64DecodedString()
        case .utf8, .none: return String(data: raw, encoding: .utf8)
        }
    }
}

private extension Data {
    func base64DecodedString() -> String? {
        guard let decoded = Data(base64Encoded: self) else { return nil }
        return String(data: decoded, encoding: .utf8)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
