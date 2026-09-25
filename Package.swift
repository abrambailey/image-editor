// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ImageEditor",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "ImageEditor", targets: ["ImageEditor"])],
    targets: [
        .executableTarget(name: "ImageEditor")
    ]
)
