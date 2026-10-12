import Testing

/// Parent of every suite that uses `StubbedNetwork`: they all share process-wide state (the
/// generator's request builder factory and the stub routes), so they must never run in
/// parallel with each other. `.serialized` applies to the nested suites too.
@Suite(.serialized)
struct StubbedNetworkTests {}
