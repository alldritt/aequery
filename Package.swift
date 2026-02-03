// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "aequery",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "aequery", targets: ["aequery"]),
        .library(name: "AEQueryLib", targets: ["AEQueryLib"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "aequery",
            dependencies: [
                "AEQueryLib",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .target(
            name: "AEQueryLib",
            dependencies: []
        ),
        .testTarget(
            name: "AEQueryLibTests",
            dependencies: ["AEQueryLib"]
        ),
    ]
)
