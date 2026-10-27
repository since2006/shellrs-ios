// swift-tools-version: 6.0
// The ShellRS core: the Rust library shell-rs builds for iOS and the Swift
// interface UniFFI generates for it. scripts/build-core.sh puts both here.
import PackageDescription

let package = Package(
    name: "ShellRSCore",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "ShellRSCore", targets: ["ShellRSCore"])
    ],
    targets: [
        .binaryTarget(name: "ShellRSCoreFFI", path: "ShellRSCore.xcframework"),
        .target(
            name: "ShellRSCore",
            dependencies: ["ShellRSCoreFFI"],
            linkerSettings: [
                // Certificates (sync over HTTPS) and the system's proxy
                // settings, which the core's HTTP client reads.
                .linkedFramework("Security"),
                .linkedFramework("SystemConfiguration"),
            ]
        ),
    ]
)
