// swift-tools-version: 6.0

import PackageDescription

// The runtime library has no dependencies: callers pass the Polyglot keys they already compute.
// The data generator and the measurements live in Tools/, a separate package that depends on FischerCore.
let package = Package(
    name: "ChessOpeningsCatalog",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "ChessOpeningsCatalog", targets: ["ChessOpeningsCatalog"]),
    ],
    targets: [
        .target(
            name: "ChessOpeningsCatalog",
            resources: [
                .copy("Resources/openings.bin"),
            ]
        ),
        .testTarget(
            name: "ChessOpeningsCatalogTests",
            dependencies: ["ChessOpeningsCatalog"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
