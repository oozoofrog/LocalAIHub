// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LocalAIHub",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AIHubCore", targets: ["AIHubCore"]),
        .executable(name: "ai", targets: ["AIHubCLI"]),
        .executable(name: "AIHubApp", targets: ["AIHubApp"]),
    ],
    targets: [
        .target(name: "AIHubCore", resources: [.copy("Installer")]),
        .executableTarget(name: "AIHubCLI", dependencies: ["AIHubCore"]),
        .executableTarget(name: "AIHubApp", dependencies: ["AIHubCore"]),
    ]
)
