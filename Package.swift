// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RechnungsponyKit",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "RechnungsponyKit", targets: ["RechnungsponyKit"])
    ],
    targets: [
        .target(name: "RechnungsponyKit"),
        .testTarget(name: "RechnungsponyKitTests", dependencies: ["RechnungsponyKit"])
    ]
)
