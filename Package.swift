// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "TextFlash",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "TextFlash",
            targets: ["TextFlash"]
        ),
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "TextFlash",
            path: "Sources/TextFlash",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "TextFlashTests",
            dependencies: ["TextFlash"],
            path: "Tests/TextFlashTests"
        ),
    ]
)
