// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AI-usage-menubar",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "AI-usage-menubar",
            exclude: ["Info.plist"]
            // Info.plist cannot be declared as a top-level resource in SwiftPM.
            // Removing the resource declaration allows `swift run` to build.
        )
    ]
)
