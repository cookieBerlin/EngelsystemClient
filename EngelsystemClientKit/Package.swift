// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "EngelsystemClientKit",
    platforms: [
        .iOS(.v26),
        .watchOS(.v26)
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
            path: "Tests/EngelsystemClientKitTests"
        )
    ]
)
