import Foundation
import SwiftData

/// Fetches news for an instance and upserts them into `CachedNews`. See
/// `ShiftSyncService` for why this takes an already-resolved `EventCredential`.
@MainActor
public struct NewsSyncService {
    private let apiClient: APIClient

    public init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }

    @discardableResult
    public func sync(instance: Instance, credential: EventCredential, in modelContext: ModelContext) async throws -> [CachedNews] {
        let news = try await apiClient.fetchNews(credential)
        return try upsert(news, instanceID: instance.id, instance: instance, in: modelContext)
    }

    @discardableResult
    private func upsert(_ newsItems: [News], instanceID: UUID, instance: Instance, in modelContext: ModelContext) throws -> [CachedNews] {
        var result: [CachedNews] = []
        for item in newsItems {
            let uid = CachedNews.uid(instanceID: instanceID, serverID: item.id)
            var descriptor = FetchDescriptor<CachedNews>(predicate: #Predicate { $0.uid == uid })
            descriptor.fetchLimit = 1

            if let existing = try modelContext.fetch(descriptor).first {
                existing.apply(item)
                existing.instance = instance
                result.append(existing)
            } else {
                let cached = CachedNews(news: item, instanceID: instanceID)
                cached.instance = instance
                modelContext.insert(cached)
                result.append(cached)
            }
        }
        return result
    }
}
