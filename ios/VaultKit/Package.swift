// swift-tools-version:5.10
//
// VaultKit -- the wire layer between this app and the owner's Obsidian vault,
// a private git repository on GitHub (openspec/changes/add-vault-connection,
// design D1). It knows GitHub's contents API and nothing about training:
// the same boundary GarminKit keeps for food. It holds the fine-grained
// token (Keychain), the path allow-lists every request is checked against,
// the device identity, a conditional fetch that only commits validated
// bytes, a generic durable queue with create-only uploads, and the
// `VaultTransport` seam that a later iCloud bridge can replace.
//
// Depends on GarminKit only, for four shared utilities: `PersistedJSON`
// (load with quarantine, never wipe), `DiagnosticsLog`, `RetryBackoff` and
// `ConnectivityFailure`. Moving those into a small common package is a later
// clean-up, not a prerequisite (the same note add-data-safety made).
//
// No user-facing strings and therefore no resources or
// `defaultLocalization`: outcomes and statuses are typed, and the app maps
// them to localized text (`VaultErrorPresentation`). `DiagnosticsLog` lines
// stay English.
//
// Linked into the app target ONLY (ios/project.yml), never the widget
// extension: the widget shows no data and must never hold the vault token.
//
// Pinned to swift-tools 5.10 (Swift 5 language mode) and iOS 17 + macOS 14
// for the same reasons as GarminKit's manifest: CI runs `swift test` on a
// plain macOS runner, and nobody here can compile locally to check Swift 6's
// strict-concurrency diagnostics.

import PackageDescription

let package = Package(
    name: "VaultKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "VaultKit",
            targets: ["VaultKit"]
        )
    ],
    dependencies: [
        .package(path: "../GarminKit")
    ],
    targets: [
        .target(
            name: "VaultKit",
            dependencies: [
                .product(name: "GarminKit", package: "GarminKit")
            ]
        ),
        .testTarget(
            name: "VaultKitTests",
            dependencies: ["VaultKit"],
            // add-data-safety D2: store fixtures are read from disk via
            // #filePath, not compiled or bundled.
            exclude: ["Fixtures"]
        )
    ]
)
