// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "UsageRings",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "UsageRings", targets: ["UsageRings"]),
        .executable(name: "UsageRingsWidget", targets: ["UsageRingsWidget"])
    ],
    targets: [
        .target(name: "UsageCore", resources: [.copy("Resources")]),
        .executableTarget(name: "UsageRings", dependencies: ["UsageCore"]),
        .executableTarget(
            name: "UsageRingsWidget", dependencies: ["UsageCore"],
            swiftSettings: [.unsafeFlags(["-application-extension"])],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-application_extension", "-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"])]
        ),
        .testTarget(name: "UsageRingsTests", dependencies: ["UsageRings", "UsageCore"])
    ]
)
