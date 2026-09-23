// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "QuickLookCore",
    platforms: [.macOS("15.0")],
    products: [
        .library(name: "QuickLookCore", targets: ["QuickLookCore"])
    ],
    targets: [
        .target(
            name: "QuickLookCore",
            path: "Sources/Core",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(
            name: "QuickLookCoreTests",
            dependencies: ["QuickLookCore"],
            path: "Tests/CoreTests",
            exclude: ["Fixtures"]
        ),
    ]
)
