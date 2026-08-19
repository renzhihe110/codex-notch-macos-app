// swift-tools-version: 5.9

import PackageDescription

// 定义独立的 macOS 可执行应用包。
let package = Package(
    name: "CodexNotch",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "CodexNotch", targets: ["CodexNotch"])
    ],
    targets: [
        .executableTarget(
            name: "CodexNotch",
            // 将内置 Trump v2 宠物包放进 SwiftPM 资源 bundle，运行时无需访问用户目录或网络。
            resources: [.process("Resources")],
            linkerSettings: [.linkedLibrary("sqlite3")]
        )
    ]
)
