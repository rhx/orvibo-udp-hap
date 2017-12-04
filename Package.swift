// swift-tools-version:4.0

import PackageDescription

let package = Package(
    name: "orvibo-udp-hap",
    products: [
        .executable(name: "orvibo-udp-hap", targets: ["orvibo-udp-hap"])
    ],
    dependencies: [
        .package(url: "https://github.com/bouke/HAP.git", .branch("master")),
        .package(url: "https://github.com/rhx/Channel.git", .branch("master")),
    ],
    targets: [
        .target(name: "orvibo-udp-hap", dependencies: ["HAP", "Channel"]),
    ],
    swiftLanguageVersions: [4]
)
