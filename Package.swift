// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ClipBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ClipBar",
            path: "Sources/ClipBar",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Carbon"),
                .linkedFramework("ImageIO"),
                .linkedFramework("ServiceManagement"),
                .linkedLibrary("sqlite3"),
            ]
        )
    ],
    swiftLanguageVersions: [.v5]
)
