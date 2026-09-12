// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "XDesktop",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "XDesktop", targets: ["XDesktop"])],
    targets: [
        .target(name: "XCore"),
        .executableTarget(name: "XDesktop", dependencies: ["XCore"], resources: [.process("Resources")]),
        .testTarget(name: "XCoreTests", dependencies: ["XCore"]),
        .testTarget(name: "XDesktopTests", dependencies: ["XDesktop"], resources: [.copy("Fixtures")])
    ]
)
