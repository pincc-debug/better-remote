// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BetterRemote",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "BetterRemote", targets: ["RemoteFit"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")],
    targets: [
        .target(name: "RemoteFitCore", resources: [.copy("Resources/device-templates.json"), .copy("Resources/shortcut-presets.json")]),
        .target(name: "NativeDisplay", cSettings: [.unsafeFlags(["-fobjc-arc"])], linkerSettings: [.linkedFramework("CoreGraphics"), .linkedFramework("IOKit")]),
        .executableTarget(name: "RemoteFit", dependencies: ["RemoteFitCore", "NativeDisplay", .product(name: "Sparkle", package: "Sparkle")], linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "RemoteFitCoreTests", dependencies: ["RemoteFitCore"]),
        .testTarget(name: "RemoteFitTests", dependencies: ["RemoteFit", "RemoteFitCore"])
    ],
    swiftLanguageModes: [.v6]
)
