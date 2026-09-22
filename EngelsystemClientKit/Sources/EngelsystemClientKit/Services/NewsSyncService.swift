import Foundation
import SwiftData

/// The result of a `NewsSyncService.sync` call — `items` is every synced post
/// (matching `sync`'s previous plain-array return shape), `insertedItems` is the
/// subset that didn't already exist in `CachedNews` before this sync. Split out
/// specifically so callers can tell "genuinely new" apart from "already knew about
/// it, just refreshed its fields" (added 2026-09-22, for the new-news notification
/// feature — see `NewsNotifier`).
public struct NewsSyncResult {
    public let items: [CachedNews]
    public let insertedItems: [CachedNews]
}

/// Fetches news for an instance and upserts them into `CachedNews`. See
/// `ShiftSyncService` for why this takes an already-resolved `EventCredential`.
@MainActor
public struct NewsSyncService {
    private let apiClient: APIClient

    public init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }

    @discardableResult
    public func sync(instance: Instance, credential: EventCredential, in modelContext: ModelContext) async throws -> NewsSyncResult {
        let news = try await apiClient.fetchNews(credential)
        return try upsert(news, instanceID: instance.id, in: modelContext)
    }

    private func upsert(_ newsItems: [News], instanceID: UUID, in modelContext: ModelContext) throws -> NewsSyncResult {
        var items: [CachedNews] = []
        var insertedItems: [CachedNews] = []
        for item in newsItems {
            let uid = CachedNews.uid(instanceID: instanceID, serverID: item.id)
            var descriptor = FetchDescriptor<CachedNews>(predicate: #Predicate { $0.uid == uid })
            descriptor.fetchLimit = 1

            if let existing = try modelContext.fetch(descriptor).first {
                existing.apply(item)
                items.append(existing)
            } else {
                let cached = CachedNews(news: item, instanceID: instanceID)
                modelContext.insert(cached)
                items.append(cached)
                insertedItems.append(cached)
            }
        }
        return NewsSyncResult(items: items, insertedItems: insertedItems)
    }
}
