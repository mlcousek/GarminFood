// swift-tools-version:5.10
//
// GarminKit — OAuth1 signing, token management, browser-based login
// bootstrap, and a durable per-process outbox for syncing food-log entries
// to Garmin Connect's private API.
//
// Deliberately framework-agnostic: no UIKit or SwiftUI import anywhere in
// this package, so both the app target and any extension target (widget,
// Control) can depend on it without pulling in a UI framework they don't
// need for their own logic layer. `AuthenticationServices` is used for
// `ASWebAuthenticationSession` (design.md D2) — that's an authentication
// framework, not a UI toolkit, and it's the one exception, needed by
// GarminAuthSession.swift.
//
// swift-tools-version is pinned to 5.10 (not 6.x) so the package builds in
// Swift 5 language mode by default rather than opting into Swift 6's strict
// concurrency checking. That checking would be valuable to turn on
// eventually, but this package was authored and ported from a Node
// reference without access to a local Swift toolchain to verify concurrency
// diagnostics against (see the final report for that caveat) — starting in
// the stricter mode risked shipping code that only *looks* like it builds.
//
// `.macOS(.v14)` is declared alongside `.iOS(.v17)` purely so `swift build`
// / `swift test` work directly on a plain macOS command line (no iOS
// Simulator destination needed) -- every framework this package imports
// (Foundation, CryptoKit, Security, AuthenticationServices) is available on
// macOS too, and `@Observable`/`Observation` (AuthState.swift) needs macOS
// 14 to match iOS 17's introduction. The app's own real deployment target
// stays iOS 17, set independently in ios/project.yml -- this does not
// change that.

import PackageDescription

let package = Package(
    name: "GarminKit",
    // add-localization (openspec/changes/add-localization/design.md D3,
    // task 3.4): GarminKit's first user-facing string is
    // `PersistedJSONUnreadFileError`'s message, which the app shows as-is.
    // English source strings are the keys; translations live in
    // Sources/GarminKit/Resources/<lang>.lproj/Localizable.strings, looked
    // up with `String(localized:bundle: .module)`. .lproj rather than an
    // .xcstrings catalog because plain `swift test` can't compile catalogs.
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "GarminKit",
            targets: ["GarminKit"]
        )
    ],
    targets: [
        .target(
            name: "GarminKit",
            dependencies: [],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "GarminKitTests",
            dependencies: ["GarminKit"]
        )
    ]
)
