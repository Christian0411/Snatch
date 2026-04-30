// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Snatch",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SnatchKit", targets: ["SnatchKit"]),
        .executable(name: "snatch-cli", targets: ["SnatchCLI"]),
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
                // Bundle -L and -lgifski together so the linker sees them in order.
                // SPM's `linkedLibrary` is a separate phase and can be too late.
                .unsafeFlags(["-L", "vendor/gifski", "-lgifski"]),
            ]
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
    ]
)
