// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ChalkScript",
    platforms: [.iOS("27.0"), .macOS("27.0")],
    products: [
        .library(name: "ChalkScript", targets: ["ChalkScript"]),
        .library(name: "ChalkScriptExplainers", targets: ["ChalkScriptExplainers"]),
        .library(name: "ChalkScriptMCP", targets: ["ChalkScriptMCP"]),
        .executable(name: "chalkscript-mcp", targets: ["chalkscript-mcp"]),
        .executable(name: "chalkscript-render", targets: ["chalkscript-render"]),
    ],
    targets: [
        .target(
            name: "ChalkScript",
            // The style file (EXP-19), read with Foundation.
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "ChalkScriptExplainers",
            dependencies: ["ChalkScript"],
            // The explainers' motion files (EXP-19), read with Foundation.
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // The MCP helper's protocol and the studio app's end of its socket, for macOS only: the
        // sources compile to nothing elsewhere. It depends on neither target above, because the
        // helper forwards each call to the studio and reads no document itself.
        .target(
            name: "ChalkScriptMCP",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "chalkscript-mcp",
            dependencies: ["ChalkScriptMCP"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Renders a document's still pictures to PNG files from a terminal, for macOS only.
        .executableTarget(
            name: "chalkscript-render",
            dependencies: ["ChalkScript"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "ChalkScriptTests",
            dependencies: ["ChalkScript"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "ChalkScriptExplainersTests",
            dependencies: ["ChalkScriptExplainers", "ChalkScript"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "ChalkScriptMCPTests",
            // The executable is a dependency so that it is built before the tests launch it.
            dependencies: ["ChalkScriptMCP", "chalkscript-mcp"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
