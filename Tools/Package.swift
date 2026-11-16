// swift-tools-version: 6.0

import PackageDescription

// Build-time tools. They replay SAN with FischerCore, which the runtime library does not need.
//   swift run -c release --package-path Tools generate-catalog
//   swift run -c release --package-path Tools measure-catalog ~/Downloads/LumbrasGigabase_OTB_2025.pgn
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
        .executableTarget(name: "measure-catalog", dependencies: ["CatalogTooling"]),
    ],
    swiftLanguageModes: [.v6]
)
