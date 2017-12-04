// swift-tools-version:4.0

import PackageDescription

let package = Package(
    name: "orvibo-udp-hap",
    products: [
        .executable(name: "orvibo-udp-hap", targets: ["orvibo-udp-hap"])
    ],
    dependencies: [
        .package(url: "https://github.com/bouke/HAP.git", .branch("master")),
    ],
    targets: [
        .target(name: "orvibo-udp-hap", dependencies: ["HAP"]),
    ],
    swiftLanguageVersions: [4]
)
