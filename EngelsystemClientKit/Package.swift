// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "EngelsystemClientKit",
    platforms: [
        .iOS(.v26),
        .watchOS(.v26),
        // Not a shipping target — lets `swift test` run directly on the host Mac
        // instead of requiring a booted iOS/watchOS simulator for every test run.
        // SwiftData's @Model needs macOS 14; everything else in this package
        // (Foundation/Security/URLSession-based) already runs fine on macOS.
        .macOS(.v14)
    ],
    products: [
        .library(name: "EngelsystemClientKit", targets: ["EngelsystemClientKit"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "EngelsystemClientKit",
            path: "Sources/EngelsystemClientKit",
            // The generated OpenAPI client (Generated/) uses swift5 codegen templates
            // that aren't Swift 6 concurrency-safe (nonisolated global mutable state).
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "EngelsystemClientKitTests",
            dependencies: ["EngelsystemClientKit"],
            path: "Tests/EngelsystemClientKitTests",
            // Tests swap the generated client's global `requestBuilderFactory` (see
            // StubbedNetwork.swift), which Swift 6 mode rejects as unsafe shared state.
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
