// swift-tools-version: 6.2
import PackageDescription

// ชื่อ package/product ต้องตรงกับ fixName(npm package name)
// "agent-plugin" -> "AgentPlugin"
// หมายเหตุ: ใช้ tools-version 6.2 เพราะต้องการ .iOS(.v26)
// แต่คงภาษา Swift 5 (swiftLanguageModes) เพื่อไม่ให้ strict concurrency เป็น error
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
    ],
    swiftLanguageModes: [.v5]
)
