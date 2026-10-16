import Foundation

/// Runs the syncs of freshly activated instances one after the other: switching on
/// two instances in a row must not start two full syncs at once. An instance already waiting is
/// not queued twice.
@MainActor
public final class InstanceSyncQueue {
    private var pending: [(instance: Instance, perform: (Instance) async -> Void)] = []
    private var worker: Task<Void, Never>?

    public init() {}

    public func enqueue(_ instance: Instance, perform: @escaping (Instance) async -> Void) {
        guard !pending.contains(where: { $0.instance.id == instance.id }) else { return }
        pending.append((instance, perform))
        guard worker == nil else { return }
        worker = Task { @MainActor in
            while !pending.isEmpty {
                let next = pending.removeFirst()
                await next.perform(next.instance)
            }
            worker = nil
        }
    }

    /// Returns once everything queued so far has run (used by tests).
    public func waitUntilIdle() async {
        await worker?.value
    }
}
