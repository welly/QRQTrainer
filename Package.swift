// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "QRQTrainer",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "QRQTrainer", targets: ["QRQTrainer"]),
        .library(name: "QRQCore", targets: ["QRQCore"]),
    ],
    targets: [
        // Platform-independent logic: Morse timing, audio synthesis, callsigns, scoring, history.
        .target(name: "QRQCore"),
        // The macOS SwiftUI application.
        .executableTarget(name: "QRQTrainer", dependencies: ["QRQCore"]),
        // The web version: QRQCore compiled to WebAssembly and called from web/. See scripts/build-web.sh.
        .executableTarget(name: "QRQWeb", dependencies: ["QRQCore"]),
        .testTarget(name: "QRQCoreTests", dependencies: ["QRQCore"]),
    ]
)
