// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "QRQTrainer",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "QRQTrainer", targets: ["QRQTrainer"]),
        .library(name: "QRQCore", targets: ["QRQCore"]),
    ],
    dependencies: [
        // The Morse engine shared by the G3AJM apps: alphabet, timing, tone rendering (github.com/welly/cw-kit).
        .package(url: "https://github.com/welly/cw-kit.git", from: "1.0.0"),
    ],
    targets: [
        // Platform-independent logic: callsigns, scoring, sessions, history, and QRQ Trainer's view of CWKit (Morse.swift).
        .target(name: "QRQCore", dependencies: [.product(name: "CWKit", package: "cw-kit")]),
        // The macOS SwiftUI application.
        .executableTarget(name: "QRQTrainer", dependencies: ["QRQCore", .product(name: "CWKit", package: "cw-kit")]),
        // The web version: QRQCore compiled to WebAssembly and called from web/. See scripts/build-web.sh.
        .executableTarget(name: "QRQWeb", dependencies: ["QRQCore", .product(name: "CWKit", package: "cw-kit")]),
        .testTarget(name: "QRQCoreTests", dependencies: ["QRQCore", .product(name: "CWKit", package: "cw-kit")]),
    ]
)
