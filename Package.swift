// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Snatch",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SnatchKit",    targets: ["SnatchKit"]),
        .library(name: "SnatchAppKit", targets: ["SnatchAppKit"]),
        .executable(name: "snatch-cli",         targets: ["SnatchCLI"]),
        .executable(name: "snatch-record-cli",  targets: ["SnatchRecordCLI"]),
        .executable(name: "snatch-session-cli", targets: ["SnatchSessionCLI"]),
    ],
    targets: [
        .systemLibrary(
            name: "CGifski",
            path: "vendor/gifski"
        ),
        .target(
            name: "SnatchKit",
            dependencies: ["CGifski"],
            path: "Sources/SnatchKit",
            linkerSettings: [
                .unsafeFlags(["-L", "vendor/gifski", "-lgifski"]),
            ]
        ),
        .target(
            name: "SnatchAppKit",
            dependencies: ["SnatchKit"],
            path: "Sources/SnatchAppKit"
        ),
        .testTarget(
            name: "SnatchKitTests",
            dependencies: ["SnatchKit"],
            path: "Tests/SnatchKitTests",
            resources: [.copy("Fixtures")]
        ),
        .executableTarget(
            name: "SnatchCLI",
            dependencies: ["SnatchKit"],
            path: "Sources/SnatchCLI"
        ),
        .executableTarget(
            name: "SnatchRecordCLI",
            dependencies: ["SnatchKit"],
            path: "Sources/SnatchRecordCLI"
        ),
        .executableTarget(
            name: "SnatchSessionCLI",
            dependencies: ["SnatchKit", "SnatchAppKit"],
            path: "Sources/SnatchSessionCLI"
        ),
    ]
)
