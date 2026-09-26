// swift-tools-version:5.10
//
// FoodLogCore — the domain layer for `add-food-log-core`: catalog search
// adaptation, local usage-history ranking, serving-default memory, custom
// foods, meal-type-from-time-of-day defaulting, barcode normalisation, and
// the confirm-and-log orchestration. Deliberately its own local package
// (mirroring GarminKit's own Package.swift, same rationale) rather than
// code living inside the GarminFood app target, so that:
//
//   - It stays framework-agnostic (no SwiftUI/UIKit import anywhere here —
//     see openspec/config.yaml's "clear module boundaries: UI / domain
//     logic / GarminKit networking kept separate" principle). The app
//     target is the only place SwiftUI views live.
//   - It is testable with a plain `swift test`, no simulator or Xcode
//     project needed, exactly like GarminKit — see
//     .github/workflows/build.yml's existing "Run GarminKit unit tests"
//     step; this package gets its own equivalent step.
//   - `add-gamification` (a parallel effort) can depend on this package for
//     read-only access to `UsageHistoryStore`'s on-disk format without
//     pulling in any UI code.
//
// Depends on GarminKit (local path) for `MealType`, `Outbox`,
// `FoodSearchResult`/`FoodSearchResponse`, and `GarminClient` conformances —
// this package adapts GarminKit's wire-format DTOs into domain models
// (`Food`/`Serving`), it does not duplicate networking or auth logic.
//
// swift-tools-version pinned to 5.10 for the same reason as GarminKit's
// Package.swift: Swift 5 language mode by default, not Swift 6's strict
// concurrency checking, authored without a local Swift toolchain to verify
// concurrency diagnostics against.

import PackageDescription

let package = Package(
    name: "FoodLogCore",
    // add-localization (openspec/changes/add-localization/design.md D3):
    // English source strings are the keys; translations live in
    // Sources/FoodLogCore/Resources/<lang>.lproj/Localizable.strings(dict),
    // looked up with `String(localized:bundle: .module)`. Deliberately NOT a
    // .xcstrings catalog: plain `swift test` (how CI tests this package)
    // does not compile catalogs -- only Xcode does -- so Czech would be
    // untestable here, while .lproj files behave the same in both.
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "FoodLogCore",
            targets: ["FoodLogCore"]
        )
    ],
    dependencies: [
        .package(path: "../GarminKit")
    ],
    targets: [
        .target(
            name: "FoodLogCore",
            dependencies: [
                .product(name: "GarminKit", package: "GarminKit")
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "FoodLogCoreTests",
            dependencies: ["FoodLogCore"],
            // add-data-safety D2: store fixtures are read from disk via
            // #filePath, not compiled or bundled.
            exclude: ["Fixtures"]
        )
    ]
)
