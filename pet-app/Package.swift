// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ErDanPet",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "ErDanPet", path: "Sources/ErDanPet")
    ]
)
