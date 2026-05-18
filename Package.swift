// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "TextFlash",
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
            path: "Sources/TextFlash"
        ),
        .testTarget(
            name: "TextFlashTests",
            dependencies: ["TextFlash"],
            path: "Tests/TextFlashTests"
        ),
    ]
)
