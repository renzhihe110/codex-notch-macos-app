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
        .executableTarget(name: "CodexNotch", linkerSettings: [.linkedLibrary("sqlite3")])
    ]
)
