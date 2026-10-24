// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Hushtype",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Hushtype", targets: ["Hushtype"]),
        .library(name: "HushtypeCore", targets: ["HushtypeCore"]),
    ],
    targets: [
        // Pure pipeline logic: audio encoding, speech-to-text engines, cleanup. No AppKit.
        .target(name: "HushtypeCore"),
        // The menu bar app: hotkey, recording, overlay, text insertion, settings.
        .executableTarget(
            name: "Hushtype",
            dependencies: ["HushtypeCore"]
        ),
        .testTarget(
            name: "HushtypeCoreTests",
            dependencies: ["HushtypeCore"]
        ),
    ]
)
