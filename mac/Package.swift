// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AuditViewer",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "AuditViewer",
            path: "Sources"
        ),
    ]
)
