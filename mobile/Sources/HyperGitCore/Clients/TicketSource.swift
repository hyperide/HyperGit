// TicketSource — unified tracker feed (GitHub Issues, Linear). Each client maps
// its payload into HGTicket so the inbox can mix sources. SPEC §1.6 / §2.2.
import Foundation

public protocol TicketSource: Sendable {
    var displayName: String { get }
    func tickets() async throws -> [HGTicket]
}
