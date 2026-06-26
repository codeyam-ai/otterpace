// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AppCore",
    platforms: [.iOS(.v17), .macOS(.v12)],
    products: [
        .library(name: "AppCore", targets: ["AppCore"]),
    ],
    targets: [
        .target(
            name: "AppCore",
            path: "Sources/AppCore"
        ),
        .testTarget(
            name: "AppCoreTests",
            dependencies: ["AppCore"],
            path: "Tests/AppCoreTests"
        ),
        // macOS-only dev tool: rasterizes `AppIconArtwork` to the 1024×1024
        // marketing PNG. Not part of the shipping app (the iOS target depends on
        // the AppCore library product, not this target). Run: swift run GenerateAppIcon
        .executableTarget(
            name: "GenerateAppIcon",
            dependencies: ["AppCore"],
            path: "Scripts/GenerateAppIcon"
        ),
    ]
)
