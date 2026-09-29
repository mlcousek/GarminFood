// TestSupport.swift
//
// Shared helpers for TrainingCore's tests: the mirrored contract fixtures
// (read from disk via #filePath, never bundled -- Package.swift excludes
// Fixtures/), app-authored edge fixtures made as small mutations of the
// vault's example (design D13: so they stay synthetic and follow the
// contract when it is re-mirrored), an in-memory `VaultTransport`, and temp
// directories.
//
// Nothing here is real data: the fixtures come from the vault's synthetic
// 2030/31 season.

import Foundation
import XCTest
import VaultKit
@testable import TrainingCore

enum Fixtures {
    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // Support
        .deletingLastPathComponent() // TrainingCoreTests
        .appendingPathComponent("Fixtures/Contract/vault", isDirectory: true)

    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: directory.appendingPathComponent(name))
    }

    static func example() throws -> Data { try data("projection.v1.example.json") }
    static func minimal() throws -> Data { try data("projection.v1.minimal.json") }

    /// The example decoded (fails the test if it doesn't decode).
    static func exampleProjection(file: StaticString = #filePath, line: UInt = #line) throws -> DecodedProjection {
        switch ProjectionDecoder.decode(try example()) {
        case .success(let decoded): return decoded
        case .failure(let rejection):
            XCTFail("example did not decode: \(rejection)", file: file, line: line)
            throw rejection
        }
    }

    static func exampleSnapshot(freshness: TrainingFreshness = TrainingFreshness()) throws -> TrainingSnapshot {
        TrainingSnapshot(projection: try exampleProjection().projection, freshness: freshness)
    }

    /// The example as a JSON object, changed by `change`, re-serialised: an
    /// app-authored edge fixture.
    static func mutatedExample(_ change: (inout [String: Any]) throws -> Void) throws -> Data {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: try example()) as? [String: Any])
        try change(&object)
        return try JSONSerialization.data(withJSONObject: object)
    }

    /// `plan.weeks[week].days[day]` of a mutable example object.
    static func mutateDay(_ object: inout [String: Any], week: Int, day: Int, _ change: (inout [String: Any]) -> Void) throws {
        var plan = try XCTUnwrap(object["plan"] as? [String: Any])
        var weeks = try XCTUnwrap(plan["weeks"] as? [[String: Any]])
        var days = try XCTUnwrap(weeks[week]["days"] as? [[String: Any]])
        change(&days[day])
        weeks[week]["days"] = days
        plan["weeks"] = weeks
        object["plan"] = plan
    }

    /// The example with the 2030-10-18 run's option token removed: done,
    /// option unknown (an anonymous run on a G/A day, contract point 3).
    static func exampleWithAnonymousFridayRun() throws -> Data {
        try mutatedExample { object in
            try mutateSession(&object, week: 1, day: 4, session: 0) { session in
                guard var done = session["done"] as? [String: Any] else { return }
                done["option"] = NSNull()
                done["source"] = NSNull()
                session["done"] = done
            }
        }
    }

    /// The date of session `id` in the example's plan. Goldens that depend
    /// on where the vault put a session (the race session was moved by a
    /// plan command, which the vault is about to refuse for races) read it
    /// from here instead of spelling it.
    static func exampleDate(ofSession id: String) throws -> LocalDate {
        let plan = try XCTUnwrap(try exampleProjection().projection.plan)
        for week in plan.weeks {
            for day in week.days where day.sessions.contains(where: { $0.id == id }) {
                return day.date
            }
        }
        XCTFail("no session \(id) in the example")
        throw ProjectionRejection.invalid(reason: "test")
    }

    static func mutateSession(_ object: inout [String: Any], week: Int, day: Int, session: Int, _ change: @escaping (inout [String: Any]) -> Void) throws {
        try mutateDay(&object, week: week, day: day) { dayObject in
            guard var sessions = dayObject["sessions"] as? [[String: Any]] else { return }
            change(&sessions[session])
            dayObject["sessions"] = sessions
        }
    }
}

/// Dates of the vault's synthetic season.
enum D {
    static func date(_ string: String) -> LocalDate {
        guard let date = LocalDate(string) else { fatalError("bad test date \(string)") }
        return date
    }

    static func week(_ string: String) -> ISOWeek {
        guard let week = ISOWeek(string) else { fatalError("bad test week \(string)") }
        return week
    }

    /// The example's `asOf`: Wednesday of 2030-W43.
    static let asOf = date("2030-10-23")
}

/// A `VaultTransport` that answers from a queue of canned fetch results.
final class InMemoryTransport: VaultTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [VaultFetchResult] = []
    private(set) var fetchCount = 0

    func enqueue(_ outcome: VaultFetchOutcome) {
        lock.lock()
        responses.append(VaultFetchResult(outcome))
        lock.unlock()
    }

    func fetch(_ path: HubPath, ifNoneMatch: String?) async -> VaultFetchResult {
        next()
    }

    /// Synchronous, so the lock is never taken in an async context.
    private func next() -> VaultFetchResult {
        lock.lock()
        defer { lock.unlock() }
        fetchCount += 1
        guard !responses.isEmpty else { return VaultFetchResult(.failed(.offline)) }
        return responses.removeFirst()
    }

    func createOnly(_ file: SealedFile) async -> VaultWriteResult {
        VaultWriteResult(.failed(.offline))
    }

    func probe() async -> VaultProbeResult {
        VaultProbeResult(repository: .success, projection: .notFound, tokenExpiresAt: nil)
    }
}

extension XCTestCase {
    func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("trainingcore-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }
}
