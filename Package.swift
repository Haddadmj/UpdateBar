// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "UpdateBar",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "UpdateBar",
            path: "Sources/UpdateBar",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "UpdateBarTests",
            dependencies: ["UpdateBar"],
            path: "Tests/UpdateBarTests"
        )
    ]
)
