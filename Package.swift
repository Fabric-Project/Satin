// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Satin",
    platforms: [.macOS(.v15), .iOS(.v18), .visionOS(.v2)],
    products: [
        .library(
            name: "Satin",
            targets: ["Satin", "SatinCore"]
        ),

        .library(
            name: "SatinCore",
            targets: ["SatinCore"]
        ),

        .library(
            name: "Satin Dynamic",
            type: .dynamic,
            targets: ["Satin", "SatinCore"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "SatinCore",
            path: "Sources/SatinCore",
            publicHeadersPath: "include",
            cSettings: [.headerSearchPath("include")],
            cxxSettings: [.headerSearchPath("include")]
        ),
        .target(
            name: "Satin",
            dependencies: ["SatinCore"],
            path: "Sources/Satin",
            resources: [.copy("Pipelines"), .copy("Textures")]
        ),
        .testTarget(
            name: "SatinCoreTests",
            dependencies: ["Satin", "SatinCore"]
        ),
        .testTarget(
            name: "SatinTests",
            dependencies: ["Satin"],
            resources: [.process("Resources")]
        ),
    ],
    swiftLanguageModes: [.v5],
    cxxLanguageStandard: .cxx17
)
