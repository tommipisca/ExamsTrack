// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ExamsCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "ExamsCore", targets: ["ExamsCore"]),
    ],
    targets: [
        .target(name: "ExamsCore"),
        .testTarget(name: "ExamsCoreTests", dependencies: ["ExamsCore"]),
    ]
)
