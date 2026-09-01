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
            path: "Sources/EngelsystemClientKit"
        ),
        .testTarget(
            name: "EngelsystemClientKitTests",
            dependencies: ["EngelsystemClientKit"],
            path: "Tests/EngelsystemClientKitTests"
        )
    ]
)
