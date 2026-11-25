// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ChalkScript",
    platforms: [.iOS("27.0"), .macOS("27.0")],
    products: [
        .library(name: "ChalkScript", targets: ["ChalkScript"]),
    ],
    targets: [
        .target(
            name: "ChalkScript",
            // The style file and each explainer's motion file (EXP-19), read with Foundation.
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "ChalkScriptTests",
            dependencies: ["ChalkScript"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
