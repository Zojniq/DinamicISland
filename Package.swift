// swift-tools-version:5.9
//
//  MacIsland — Dynamic Island for macOS.
//  Open this file directly in Xcode (File ▸ Open…) to get a full IDE project,
//  or build from the terminal with `swift build -c release` / `Scripts/bundle.sh`.
//
import PackageDescription

let package = Package(
    name: "MacIsland",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "MacIsland",
            path: "Sources/MacIsland"
        )
    ]
)
