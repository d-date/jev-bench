// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "jevbench",
  platforms: [.macOS(.v26)],
  dependencies: [
    .package(
      url: "https://github.com/d-date/swift-jev.git",
      revision: "2c7ac472365ed3d7002ee2bdd1ac679024f12d3e"
    )
  ],
  targets: [
    .executableTarget(
      name: "jevbench",
      dependencies: [.product(name: "Jev", package: "swift-jev")]
    )
  ]
)
