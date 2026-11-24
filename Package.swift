// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "swift-cli-output",
    platforms: [.macOS(.v13)],
    products: [.library(name: "CLIOutput", targets: ["CLIOutput"])],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.8.0"),
    ],
    targets: [
        .target(name: "CLIOutput", dependencies: [.product(name: "ArgumentParser", package: "swift-argument-parser")]),
        .testTarget(name: "CLIOutputTests", dependencies: ["CLIOutput"]),
    ]
)
