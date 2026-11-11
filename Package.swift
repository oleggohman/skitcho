// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "Skitcho",
  platforms: [.macOS(.v15)],
  products: [
    .executable(name: "Skitcho", targets: ["Skitcho"])
  ],
  dependencies: [
    .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")
  ],
  targets: [
    .target(name: "SkitchoCore"),
    .target(name: "SkitchoUI", dependencies: ["SkitchoCore"]),
    .executableTarget(
      name: "Skitcho",
      dependencies: [
        "SkitchoCore",
        "SkitchoUI",
        .product(name: "Sparkle", package: "Sparkle"),
      ]
    ),
    .testTarget(name: "SkitchoCoreTests", dependencies: ["SkitchoCore"]),
    .testTarget(name: "SkitchoUITests", dependencies: ["SkitchoUI", "SkitchoCore"]),
    .testTarget(name: "SkitchoAppTests", dependencies: ["Skitcho"]),
  ]
)
