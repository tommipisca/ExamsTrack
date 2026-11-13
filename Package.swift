// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ExamsTrack",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        // Prodotto principale: l'app.
        .library(name: "ExamsTrack", targets: ["ExamsTrack"]),
        // Estensione widget, collegata in xtool.yml sotto `extensions`.
        .library(name: "ExamsTrackWidget", targets: ["ExamsTrackWidget"]),
    ],
    dependencies: [
        .package(path: "ExamsCore"),
    ],
    targets: [
        .target(
            name: "ExamsTrack",
            dependencies: [.product(name: "ExamsCore", package: "ExamsCore")]
        ),
        .target(
            name: "ExamsTrackWidget",
            dependencies: [.product(name: "ExamsCore", package: "ExamsCore")],
            // Swift 6.4: il linker usa -e _NSExtensionMain e -dead_strip e scarta _main
            // (e con lui tutto il codice del widget). Lo teniamo esplicitamente.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-u", "-Xlinker", "_main"])]
        ),
    ]
)
