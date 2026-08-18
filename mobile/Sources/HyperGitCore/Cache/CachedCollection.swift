// CachedCollection — the single SwiftData row type backing SwiftDataCacheStore.
// One row per cached collection (the repo list, one repo's file tree, one repo's PR
// list, one repo's issue list, one ticket source's list) rather than one row per
// HGRepo/HGIssue/etc. — this keeps the schema to a single model type and turns LRU
// eviction into a plain sort over `fetchedAt` instead of a multi-table cascade delete.
import Foundation
import SwiftData

@Model
final class CachedCollection {
    @Attribute(.unique) var key: String
    var payload: Data
    var fetchedAt: Date
    var payloadSize: Int

    init(key: String, payload: Data, fetchedAt: Date) {
        self.key = key
        self.payload = payload
        self.fetchedAt = fetchedAt
        self.payloadSize = payload.count
    }
}
