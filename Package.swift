// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "XDesktop",
    // macOS 27 and later only, as Blit, Rune and Cue are: the newest APIs, no compatibility code.
    platforms: [.macOS("27.0")],
    products: [.executable(name: "XDesktop", targets: ["XDesktop"])],
    // Sparkle updates published builds from x.banast.as, as Blit, Rune and Cue are updated from theirs.
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")],
    targets: [
        .target(name: "XCore"),
        .executableTarget(
            name: "XDesktop",
            dependencies: ["XCore", .product(name: "Sparkle", package: "Sparkle")],
            resources: [.process("Resources")],
            // The app bundle carries Sparkle.framework in Contents/Frameworks (scripts/build-app.sh).
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "XCoreTests", dependencies: ["XCore"]),
        .testTarget(name: "XDesktopTests", dependencies: ["XDesktop"], resources: [.copy("Fixtures")])
    ]
)
