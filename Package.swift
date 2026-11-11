// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Agentback",
    platforms: [.macOS(.v12), .iOS(.v15)],
    products: [.library(name: "Agentback", targets: ["Agentback"])],
    targets: [
        .target(name: "Agentback"),
        .testTarget(name: "AgentbackTests", dependencies: ["Agentback"]),
    ]
)
