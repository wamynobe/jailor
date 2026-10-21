// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Jailor",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Jailor", targets: ["Jailor"])
    ],
    targets: [
        .executableTarget(
            name: "Jailor",
            path: "Sources/Jailor",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "JailorTests",
            dependencies: ["Jailor"],
            path: "Tests/JailorTests",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
