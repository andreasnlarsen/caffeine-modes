// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CaffeineModes",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "CaffeineModesCore", targets: ["CaffeineModesCore"]),
        .library(name: "CaffeineModesAppSupport", targets: ["CaffeineModesAppSupport"]),
        .executable(name: "CaffeineModes", targets: ["CaffeineModesApp"])
    ],
    targets: [
        .target(
            name: "CaffeineModesCore",
            path: "Sources/CaffeineModesCore"
        ),
        .target(
            name: "CaffeineModesAppSupport",
            dependencies: ["CaffeineModesCore"],
            path: "Sources/CaffeineModesAppSupport"
        ),
        .executableTarget(
            name: "CaffeineModesApp",
            dependencies: ["CaffeineModesCore", "CaffeineModesAppSupport"],
            path: "Sources/CaffeineModesApp"
        ),
        .testTarget(
            name: "CaffeineModesCoreTests",
            dependencies: ["CaffeineModesCore", "CaffeineModesAppSupport"],
            path: "Tests/CaffeineModesCoreTests"
        )
    ]
)
