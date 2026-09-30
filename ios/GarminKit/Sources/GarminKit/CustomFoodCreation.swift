// CustomFoodCreation.swift
//
// fix-review-findings-2026-09 finding 2: what a custom-food create response
// MEANS. `PUT /nutrition-service/customFood`'s response shape is still an
// unconfirmed guess (`GarminClient.createCustomFood`'s doc comment). Before
// this, a 2xx whose body didn't decode as `FoodSearchResult` threw
// `GarminClientError.decodingFailed`, the create screen showed it as a
// failed create with "Try again" -- and a retry created the same food in
// Garmin a second time. A 2xx means Garmin accepted the write, so it is a
// create, whatever the body looks like:
//
//   - 2xx + a `FoodSearchResult` body -> `.created(result)`;
//   - 2xx + anything else             -> `.createdDetailsPending` (never an
//     error: the food almost certainly exists; the caller must not offer a
//     blind retry);
//   - non-2xx -> thrown exactly as before (`GarminClient.
//     throwIfNotSuccessful`), so nothing was created and a retry is safe.
//
// The request goes through an injected `send` closure so the decision is
// testable without the network or a Keychain token (CustomFoodCreationTests
// feeds it a 201 with an unexpected body). `GarminClient.createCustomFood`
// passes its real signed PUT.
//
// Depended on by: GarminClient.createCustomFood; the app's
// CreateInGarminConfirmView (via FoodLogCore's CustomFoodCreateGate).

import Foundation

/// The result of a custom-food create that Garmin accepted (2xx).
public enum CustomFoodCreateOutcome: Sendable {
    /// Garmin returned the created food.
    case created(FoodSearchResult)
    /// Garmin accepted the create (`statusCode` is 2xx) but its body was not
    /// the expected shape, so the new food's id is unknown here. The food
    /// exists in Garmin: never create it again blindly.
    case createdDetailsPending(statusCode: Int)
}

enum CustomFoodCreation {
    static func create(
        _ body: CustomFoodWriteBody,
        send: (CustomFoodWriteBody) async throws -> (Data, HTTPURLResponse)
    ) async throws -> CustomFoodCreateOutcome {
        let (data, response) = try await send(body)
        // Non-2xx: nothing was created; thrown exactly as before.
        try GarminClient.throwIfNotSuccessful(response, data: data)
        do {
            return .created(try JSONDecoder().decode(FoodSearchResult.self, from: data))
        } catch {
            DiagnosticsLog.log(.warning, category: "GarminClient", "customFood create returned \(response.statusCode) with an unreadable body (\(data.count) bytes); treated as created, details pending: \(String(describing: error).prefix(200))")
            return .createdDetailsPending(statusCode: response.statusCode)
        }
    }
}
