// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "DaylogBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "DaylogBar",
            path: "Sources/DaylogBar",
            linkerSettings: [.linkedFramework("Carbon")]
        )
    ]
)
