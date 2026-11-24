// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SpikeKit",
    platforms: [.iOS("26.0"), .macOS("15.0")],
    products: [.library(name: "SpikeKit", targets: ["SpikeKit"])],
    targets: [
        .target(name: "SpikeKit"),
        .testTarget(name: "SpikeKitTests", dependencies: ["SpikeKit"]),
    ],
    swiftLanguageModes: [.v5]
)
