// TicketSource — unified tracker feed (GitHub Issues, Linear). Each client maps
// its payload into HGTicket so the inbox can mix sources. SPEC §1.6 / §2.2.
import Foundation

public protocol TicketSource: Sendable {
    var displayName: String { get }
    func tickets() async throws -> [HGTicket]
}

/// Canned ticket feed for previews, tests and demo mode.
public struct PreviewTicketSource: TicketSource {
    public var displayName: String { "Preview" }
    public let items: [HGTicket]
    public init(items: [HGTicket] = HGTicket.samples) { self.items = items }
    public func tickets() async throws -> [HGTicket] { items }
}
