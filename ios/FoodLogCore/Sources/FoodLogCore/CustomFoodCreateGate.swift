// CustomFoodCreateGate.swift
//
// fix-review-findings-2026-09 finding 2: when the "Create in Garmin" button
// may be pressed. The create screen (GarminFood/Catalog/
// MatchConfirmationView.swift, `CreateInGarminConfirmView`) used to re-enable
// its button after ANY failure -- including a 2xx whose body it couldn't
// read, and a 2xx whose food it couldn't turn into a `Food` -- so "try
// again" created a duplicate food in Garmin. The rule, pulled out of the
// view so it is tested:
//
//   - a create is in flight              -> no second create;
//   - Garmin answered 2xx (any body)     -> created; never create again
//     from this screen. With a readable food, the caller continues with it;
//     without one, it shows "created, details pending";
//   - Garmin refused it / it never got an answer (a thrown error) -> retry
//     is allowed, since no 2xx was ever seen.
//
// Pure value type, no SwiftUI. Tests: CustomFoodCreateGateTests.

import Foundation
import GarminKit

public struct CustomFoodCreateGate: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        case ready
        case creating
        /// Garmin created it and returned a usable food.
        case created(Food)
        /// Garmin created it (2xx) but the food couldn't be read back.
        case createdDetailsPending
        /// Refused or unanswered: nothing was created as far as we know.
        case failed
    }

    public private(set) var phase: Phase = .ready

    public init() {}

    /// Only before any create, or after one that did not get a 2xx.
    public var canCreate: Bool {
        switch phase {
        case .ready, .failed: return true
        case .creating, .created, .createdDetailsPending: return false
        }
    }

    /// Starts a create; `false` (and nothing changes) when one may not start.
    public mutating func begin() -> Bool {
        guard canCreate else { return false }
        phase = .creating
        return true
    }

    /// A 2xx from Garmin. Returns the created food when it could be read.
    @discardableResult
    public mutating func finish(_ outcome: CustomFoodCreateOutcome) -> Food? {
        switch outcome {
        case .created(let result):
            if let food = Food(searchResult: result) {
                phase = .created(food)
                return food
            }
            phase = .createdDetailsPending
            return nil
        case .createdDetailsPending:
            phase = .createdDetailsPending
            return nil
        }
    }

    /// The create threw: Garmin refused it or never answered.
    public mutating func fail() {
        guard phase == .creating else { return }
        phase = .failed
    }
}
