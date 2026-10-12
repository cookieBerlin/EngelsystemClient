import Foundation
import SwiftData
import Testing
@testable import EngelsystemClientKit

private final class MemoryStore: APIKeyStore, @unchecked Sendable {
    var keys: [String: String] = [:]
    var failSave = false
    struct Failure: Error {}
    func save(apiKey: String, for reference: String) throws {
        if failSave { throw Failure() }
        keys[reference] = apiKey
    }
    func loadAPIKey(for reference: String) throws -> String { throw Failure() }
    func deleteAPIKey(for reference: String) throws {}
}

@MainActor
private func makeContext() throws -> ModelContext {
    let schema = Schema([Instance.self])
    let container = try ModelContainer(
        for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
    )
    return ModelContext(container)
}

@MainActor
struct DemoSeedingTests {
    private let flag = [DemoSeeding.launchArgument]

    @Test func seedsOnlyWithTheArgumentAndNoInstance() {
        #expect(DemoSeeding.shouldSeed(arguments: flag, existingInstanceCount: 0))
        #expect(!DemoSeeding.shouldSeed(arguments: flag, existingInstanceCount: 1))
        #expect(!DemoSeeding.shouldSeed(arguments: ["-other"], existingInstanceCount: 0))
    }

    @Test func opensSettingsOnlyWhenAsked() {
        #expect(DemoSeeding.shouldOpenSettings(arguments: [DemoSeeding.openSettingsArgument]))
        #expect(!DemoSeeding.shouldOpenSettings(arguments: [DemoSeeding.launchArgument]))
    }

    @Test func insertsADemoInstanceAndItsKey() async throws {
        let context = try makeContext()
        let store = MemoryStore()
        #expect(await DemoSeeding.seedIfRequested(arguments: flag, in: context, store: store))
        let instances = try context.fetch(FetchDescriptor<Instance>())
        #expect(instances.count == 1)
        #expect(instances[0].baseURL == Instance.demoBaseURL)
        #expect(store.keys[instances[0].apiKeyKeychainRef] == "demo")
    }

    @Test func doesNothingWithoutTheArgumentOrWhenAnInstanceExists() async throws {
        let context = try makeContext()
        #expect(await DemoSeeding.seedIfRequested(arguments: [], in: context, store: MemoryStore()) == false)
        #expect(try context.fetch(FetchDescriptor<Instance>()).isEmpty)

        context.insert(Instance(name: "Existing", baseURL: "https://x.test", apiKeyKeychainRef: "r"))
        try context.save()
        #expect(await DemoSeeding.seedIfRequested(arguments: flag, in: context, store: MemoryStore()) == false)
        #expect(try context.fetch(FetchDescriptor<Instance>()).count == 1)
    }

    @Test func aFailingKeyStoreSeedsNothing() async throws {
        let context = try makeContext()
        let store = MemoryStore()
        store.failSave = true
        #expect(await DemoSeeding.seedIfRequested(arguments: flag, in: context, store: store) == false)
        #expect(try context.fetch(FetchDescriptor<Instance>()).isEmpty)
    }

    @Test func resetDeletesAllInstancesOnlyWhenAsked() async throws {
        let context = try makeContext()
        context.insert(Instance(name: "Existing", baseURL: "https://x.test", apiKeyKeychainRef: "r"))
        try context.save()
        #expect(!DemoSeeding.resetIfRequested(arguments: [], in: context))
        #expect(try context.fetch(FetchDescriptor<Instance>()).count == 1)

        #expect(DemoSeeding.shouldReset(arguments: [DemoSeeding.resetArgument]))
        #expect(DemoSeeding.resetIfRequested(arguments: [DemoSeeding.resetArgument], in: context))
        #expect(try context.fetch(FetchDescriptor<Instance>()).isEmpty)
    }

    @Test func resetRunsBeforeSeeding() async throws {
        let context = try makeContext()
        context.insert(Instance(name: "Old", baseURL: "https://x.test", apiKeyKeychainRef: "r"))
        try context.save()
        #expect(await DemoSeeding.seedIfRequested(arguments: [DemoSeeding.resetArgument, DemoSeeding.launchArgument], in: context, store: MemoryStore()))
        let instances = try context.fetch(FetchDescriptor<Instance>())
        #expect(instances.count == 1)
        #expect(instances[0].name == "Demo")
    }
}
