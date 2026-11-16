// swift-tools-version: 6.0

import PackageDescription

// Build-time tools. They replay SAN with FischerCore, which the runtime library does not need.
//   swift run -c release --package-path Tools generate-catalog
//   swift run -c release --package-path Tools measure-catalog path/to/base.pgn [report.md]
let package = Package(
    name: "ChessOpeningsCatalogTools",
    platforms: [
        .macOS(.v15),
    ],
    dependencies: [
        .package(path: ".."),
        .package(url: "https://github.com/NSStudent/fischer-core.git", branch: "feature/0.4.0"),
    ],
    targets: [
        .target(
            name: "CatalogTooling",
            dependencies: [
                .product(name: "ChessOpeningsCatalog", package: "ChessOpeningsCatalog"),
                .product(name: "FischerCore", package: "fischer-core"),
            ]
        ),
        .executableTarget(name: "generate-catalog", dependencies: ["CatalogTooling"]),
        .executableTarget(
            name: "bench-catalog",
            dependencies: [.product(name: "ChessOpeningsCatalog", package: "ChessOpeningsCatalog")]
        ),
        // Top-level measurement script: Swift 5 mode keeps it free of main-actor plumbing.
        .executableTarget(name: "measure-catalog", dependencies: ["CatalogTooling"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ],
    swiftLanguageModes: [.v6]
)
