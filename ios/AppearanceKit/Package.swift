// swift-tools-version:5.10
//
// AppearanceKit — the pure logic behind `add-themes-and-layout`
// (openspec/changes/add-themes-and-layout/design.md D1, D3–D5, D7): color
// math (WCAG contrast, OKLab/OKLCH, colour-vision-deficiency simulation),
// theme roles and the built-in theme catalog as data, the persisted
// `AppearanceSettings` and their migration, the palette resolver and the
// custom-accent fitter.
//
// Its own dependency-free package (Foundation only — no SwiftUI, no
// GarminKit/FoodLogCore) so that:
//
//   - every contrast and distinctness rule in D5 is a plain `swift test`
//     in CI (see .github/workflows/build.yml's "Run AppearanceKit unit
//     tests" step), with no simulator — the only way this project can
//     verify a palette without a Mac;
//   - both the app and the widget extension can link it (ios/project.yml)
//     without dragging the domain or networking layers into the widget.
//
// The app target maps `ThemeRole`/`RGBA` values to SwiftUI `Color`s and
// theme ids to localized display names; nothing user-facing lives here.
//
// swift-tools-version pinned to 5.10 for the same reason as the other
// packages: Swift 5 language mode, authored without a local toolchain.

import PackageDescription

let package = Package(
    name: "AppearanceKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "AppearanceKit",
            targets: ["AppearanceKit"]
        )
    ],
    targets: [
        .target(
            name: "AppearanceKit"
        ),
        .testTarget(
            name: "AppearanceKitTests",
            dependencies: ["AppearanceKit"]
        )
    ]
)
