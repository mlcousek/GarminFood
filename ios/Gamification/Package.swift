// swift-tools-version:5.10
//
// Gamification — `add-gamification`'s streak/XP/challenge engine: pure
// functions and small JSON-file-backed stores computing consecutive-day
// streaks, XP/levels, and rotating challenge progress, entirely from local
// data (FoodLogCore's usage history plus a locally cached snapshot of
// Garmin nutrition goals -- see GoalStatus.swift's header for why that
// snapshot exists and who populates it).
//
// Deliberately framework-agnostic: no UIKit or SwiftUI import anywhere in
// this package, matching GarminKit's and FoodLogCore's own rationale (both
// package headers) -- the app target (and, in principle, any future
// extension target) can depend on this for logic without pulling in a UI
// framework, and everything here is testable with a plain `swift test`, no
// simulator needed.
//
// Depends on FoodLogCore (local path) for `UsageEvent` -- this package
// reads that type directly rather than re-parsing usage-history.json's
// documented JSON shape itself, so there is exactly one place that shape is
// defined (FoodLogCore/Sources/FoodLogCore/UsageHistory.swift's header).
// Deliberately does NOT depend on GarminKit: goal-hitting mechanics consume
// a small local `DailyGoalStatus` snapshot this package defines itself
// (see GoalStatus.swift), which the app layer populates from
// `GarminClient.dailyFoodLog(date:)` -- keeping this package's dependency
// footprint to exactly the one package it genuinely needs types from, per
// this phase's brief.
//
// swift-tools-version pinned to 5.10 for the same reason as GarminKit's and
// FoodLogCore's Package.swift: Swift 5 language mode by default, not Swift
// 6's strict concurrency checking, authored without a local Swift toolchain
// to verify concurrency diagnostics against (see the final report for that
// caveat -- no `swift` binary was available in this environment either).

import PackageDescription

let package = Package(
    name: "Gamification",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "Gamification",
            targets: ["Gamification"]
        )
    ],
    dependencies: [
        .package(path: "../FoodLogCore")
    ],
    targets: [
        .target(
            name: "Gamification",
            dependencies: [
                .product(name: "FoodLogCore", package: "FoodLogCore")
            ]
        ),
        .testTarget(
            name: "GamificationTests",
            dependencies: ["Gamification"]
        )
    ]
)
