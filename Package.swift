// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CaffeineModes",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "CaffeineModesCore", targets: ["CaffeineModesCore"]),
        .executable(name: "CaffeineModes", targets: ["CaffeineModesApp"])
    ],
    targets: [
        .target(
            name: "CaffeineModesCore",
            path: "Sources/CaffeineModesCore"
        ),
        .executableTarget(
            name: "CaffeineModesApp",
            dependencies: ["CaffeineModesCore"],
            path: "Sources/CaffeineModesApp"
        ),
        .testTarget(
            name: "CaffeineModesCoreTests",
            dependencies: ["CaffeineModesCore"],
            path: "Tests/CaffeineModesCoreTests"
        )
    ]
)
