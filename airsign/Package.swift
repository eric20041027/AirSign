// swift-tools-version:6.0
import PackageDescription

let strictConcurrency: SwiftSetting = .enableUpcomingFeature("StrictConcurrency")

let package = Package(
    name: "AirSign",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "AirSign", targets: ["AirSign"])],
    targets: [
        .target(name: "AirSignCore", swiftSettings: [strictConcurrency]),
        .target(name: "AirSignLab", dependencies: ["AirSignCore"], swiftSettings: [strictConcurrency]),
        .executableTarget(
            name: "AirSign",
            dependencies: ["AirSignCore", "AirSignLab"],
            swiftSettings: [strictConcurrency, .define("AIRSIGN_LAB", .when(configuration: .debug))]
        ),
        .target(name: "AirSignTestSupport", dependencies: ["AirSignCore"], path: "Tests/AirSignTestSupport", swiftSettings: [strictConcurrency]),
        .testTarget(name: "AirSignCoreTests", dependencies: ["AirSignCore", "AirSignTestSupport"], swiftSettings: [strictConcurrency]),
        .testTarget(name: "AirSignLabTests", dependencies: ["AirSignCore", "AirSignLab", "AirSignTestSupport"], swiftSettings: [strictConcurrency]),
    ],
    swiftLanguageModes: [.v5]
)
