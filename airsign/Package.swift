// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "AirSign",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "AirSign", targets: ["AirSign"])],
    targets: [
        .target(name: "AirSignCore"),
        .executableTarget(
            name: "AirSign",
            dependencies: ["AirSignCore"],
            swiftSettings: [.define("AIRSIGN_LAB", .when(configuration: .debug))]
        ),
        .testTarget(name: "AirSignCoreTests", dependencies: ["AirSignCore"]),
    ],
    swiftLanguageModes: [.v5]
)
