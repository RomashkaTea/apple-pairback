// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "PairBackPlan",
    platforms: [.macOS(.v13)],
    products: [.library(name: "PairBackPlan", targets: ["PairBackPlan"])],
    targets: [
        .target(name: "PairBackPlan", path: "App", sources: ["PairBackPlan.swift"]),
        .testTarget(name: "PairBackPlanTests", dependencies: ["PairBackPlan"], path: "Tests")
    ]
)
