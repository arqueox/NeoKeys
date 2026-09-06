// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NeoKeys",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "NeoKeys",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("ServiceManagement")
            ]
        )
    ]
)
