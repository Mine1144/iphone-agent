// swift-tools-version: 5.9
import PackageDescription

// ชื่อ package/product ต้องตรงกับ fixName(npm package name)
// "agent-plugin" -> "AgentPlugin"
let package = Package(
    name: "AgentPlugin",
    platforms: [.iOS(.v26)],
    products: [
        .library(
            name: "AgentPlugin",
            targets: ["AgentPlugin"])
    ],
    dependencies: [
        .package(url: "https://github.com/ionic-team/capacitor-swift-pm.git", exact: "8.5.3")
    ],
    targets: [
        .target(
            name: "AgentPlugin",
            dependencies: [
                .product(name: "Capacitor", package: "capacitor-swift-pm")
            ],
            path: "ios")
    ]
)
