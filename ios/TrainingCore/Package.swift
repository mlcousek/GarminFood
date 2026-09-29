// swift-tools-version:5.10
//
// TrainingCore -- the training domain of Jirka's Arc
// (openspec/changes/add-training-today-and-plan, design D1). It reads the
// one file the owner's vault publishes for the phone, the projection
// (`projection.v1.json`), tolerantly (design D2/D3), keeps the last good
// copy and says how fresh it is (D5), resolves the training day in the
// plan's time zone (D6), and turns an *effective plan* into pure view
// models for Today and the Plan tab (D7-D10), with every display string
// in English and Czech.
//
// Why a package: the phone never computes what the vault computes, but the
// app still has real logic (tolerant decoding, ISO weeks across year
// boundaries, the training-day boundary, option highlighting, month grids)
// and there is no Mac to test it on. Everything here is plain Foundation,
// so `swift test` on CI's macOS runner is the proof (.github/workflows/
// build.yml, "Run TrainingCore unit tests"). It NEVER imports SwiftUI or
// UIKit; the app's views only draw what the builders return.
//
// Depends on VaultKit (the transport, `ConditionalFileSync`, the hub path)
// and GarminKit (`DiagnosticsLog`). Linked into the app target ONLY
// (ios/project.yml): the widget has no training content.
//
// Localization follows the package convention (add-localization D3):
// English keys, Resources/<lang>.lproj/Localizable.strings(dict), looked up
// through `TrainingText` so the formatters can be tested in both languages.
//
// Pinned to swift-tools 5.10 (Swift 5 language mode) and iOS 17 + macOS 14
// like the other packages: authored without a local toolchain.

import PackageDescription

let package = Package(
    name: "TrainingCore",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "TrainingCore",
            targets: ["TrainingCore"]
        )
    ],
    dependencies: [
        .package(path: "../GarminKit"),
        .package(path: "../VaultKit")
    ],
    targets: [
        .target(
            name: "TrainingCore",
            dependencies: [
                .product(name: "GarminKit", package: "GarminKit"),
                .product(name: "VaultKit", package: "VaultKit")
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "TrainingCoreTests",
            dependencies: ["TrainingCore"],
            // design D13: the contract fixtures are read from disk via
            // #filePath, never compiled or bundled.
            exclude: ["Fixtures"]
        )
    ]
)
