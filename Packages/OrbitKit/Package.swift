// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OrbitKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        // One product so each Xcode target only links "OrbitKit".
        .library(name: "OrbitKit", targets: ["OrbitEngine", "OrbitData", "OrbitUI"]),
    ],
    targets: [
        .target(name: "OrbitEngine"),
        .target(name: "OrbitData", dependencies: ["OrbitEngine"]),
        .target(name: "OrbitUI", resources: [.copy("Resources/Fonts")]),
        .testTarget(name: "OrbitEngineTests", dependencies: ["OrbitEngine"]),
        .testTarget(name: "OrbitDataTests", dependencies: ["OrbitData"]),
    ]
)
