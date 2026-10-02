// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "PairBackPlan",
    platforms: [.macOS(.v13)],
    products: [.library(name: "PairBackPlan", targets: ["PairBackPlan"])],
    targets: [
        .target(
            name: "PairBackPlan",
            path: "App",
            exclude: [
                "AccessController.swift", "Assets.xcassets", "BridgingHeader.h", "Info.plist",
                "KernelcacheLoader.swift", "MobileGestaltOffset.m", "PairBackApp.swift",
                "PairBackView.swift", "PairingStore.swift"
            ],
            sources: ["PairBackPlan.swift"]
        ),
        .testTarget(name: "PairBackPlanTests", dependencies: ["PairBackPlan"], path: "Tests")
    ]
)
