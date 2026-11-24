// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ScrivnerCore",
    platforms: [.iOS("26.0"), .macOS("15.0")],
    products: [.library(name: "ScrivnerCore", targets: ["ScrivnerCore"])],
    targets: [
        .target(name: "ScrivnerCore"),
        .testTarget(name: "ScrivnerCoreTests", dependencies: ["ScrivnerCore"]),
    ],
    swiftLanguageModes: [.v6]
)
