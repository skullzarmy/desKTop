// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "desKTop",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "desKTopCore",
            targets: ["desKTopCore"]
        ),
        .executable(
            name: "desKTopCLI",
            targets: ["desKTopCLI"]
        ),
        .executable(
            name: "desKTopTests",
            targets: ["desKTopTests"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "desKTopCore",
            path: "Sources/desKTopCore"
        ),
        .executableTarget(
            name: "desKTopCLI",
            dependencies: ["desKTopCore"],
            path: "Sources/desKTopCLI"
        ),
        .executableTarget(
            name: "desKTopTests",
            dependencies: ["desKTopCore"],
            path: "Tests/desKTopTests"
        )
    ]
)
