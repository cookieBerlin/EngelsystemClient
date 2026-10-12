import Testing

/// Parent of every suite that uses `StubbedNetwork` (from `EngelsystemClientKit`'s Debug-only test
/// support): they share process-wide state, so they must never run in parallel with each other.
@Suite(.serialized)
struct StubbedNetworkTests {}
