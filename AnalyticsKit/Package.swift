// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AnalyticsKit",
    platforms: [
        .iOS("26.0"),
        .macOS("15.0"), // enables `swift test` on macOS; the library is UI-free
    ],
    products: [
        .library(name: "AnalyticsKit", targets: ["AnalyticsKit"])
    ],
    targets: [
        .target(name: "AnalyticsKit"),
        .testTarget(name: "AnalyticsKitTests", dependencies: ["AnalyticsKit"]),
    ]
)
