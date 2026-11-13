// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "AirSign",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "AirSign", targets: ["AirSign"])],
    targets: [
        .target(name: "AirSignCore"),
        .target(name: "AirSignLab", dependencies: ["AirSignCore"]),
        .executableTarget(
            name: "AirSign",
            dependencies: ["AirSignCore", "AirSignLab"],
            swiftSettings: [.define("AIRSIGN_LAB", .when(configuration: .debug))]
        ),
        .target(name: "AirSignTestSupport", dependencies: ["AirSignCore"], path: "Tests/AirSignTestSupport"),
        .testTarget(name: "AirSignCoreTests", dependencies: ["AirSignCore", "AirSignTestSupport"]),
        .testTarget(name: "AirSignLabTests", dependencies: ["AirSignCore", "AirSignLab", "AirSignTestSupport"]),
    ],
    swiftLanguageModes: [.v5]
)
