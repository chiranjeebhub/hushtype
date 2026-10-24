// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Hushtype",
    // SpeechAnalyzer, the on-device transcriber, ships with macOS 26.
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Hushtype", targets: ["Hushtype"]),
        .library(name: "HushtypeCore", targets: ["HushtypeCore"]),
    ],
    dependencies: [
        // Auto-updates for builds distributed outside the App Store.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.0"),
    ],
    targets: [
        // Pure pipeline logic: on-device speech-to-text and Claude cleanup. No AppKit.
        .target(name: "HushtypeCore"),
        // The menu bar app: hotkey, recording, overlay, text insertion, settings.
        .executableTarget(
            name: "Hushtype",
            dependencies: ["HushtypeCore", .product(name: "Sparkle", package: "Sparkle")],
            // The app bundle carries Sparkle.framework in Contents/Frameworks.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(
            name: "HushtypeCoreTests",
            dependencies: ["HushtypeCore"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
