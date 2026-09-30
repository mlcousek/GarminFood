// CustomFoodCreationTests.swift
//
// fix-review-findings-2026-09 finding 2: a 2xx custom-food create whose
// body isn't a `FoodSearchResult` used to throw `decodingFailed`, which the
// create screen showed as a failed create with "Try again" -- a retry then
// made a second copy of the food in Garmin. Drives `CustomFoodCreation`
// through an injected transport (no network, no Keychain token) and pins
// that a 2xx is always a create, and only a non-2xx is an error.

import XCTest
@testable import GarminKit

final class CustomFoodCreationTests: XCTestCase {
    private let body = CustomFoodWriteBody.make(
        foodName: "Synthetic yoghurt",
        servingUnit: "g",
        numberOfUnits: 100,
        calories: 60,
        protein: nil,
        carbs: nil,
        fat: nil
    )

    private func response(_ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://example.invalid/nutrition-service/customFood")!,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        )!
    }

    func testA201WithAnUnexpectedBodyIsACreateWithDetailsPendingNotAnError() async throws {
        var sends = 0
        let outcome = try await CustomFoodCreation.create(body) { _ in
            sends += 1
            return (Data(#"{"status":"accepted","somethingElse":[1,2,3]}"#.utf8), self.response(201))
        }

        guard case .createdDetailsPending(let status) = outcome else {
            return XCTFail("a 2xx must never read as a failed create, got \(outcome)")
        }
        XCTAssertEqual(status, 201)
        XCTAssertEqual(sends, 1, "exactly one write, no automatic retry")
    }

    func testA200WithAnEmptyBodyIsAlsoACreateWithDetailsPending() async throws {
        let outcome = try await CustomFoodCreation.create(body) { _ in (Data(), self.response(200)) }

        guard case .createdDetailsPending = outcome else {
            return XCTFail("expected createdDetailsPending, got \(outcome)")
        }
    }

    func testA201WithAFoodSearchResultBodyIsCreatedWithTheNewId() async throws {
        let json = #"{"foodMetaData":{"foodId":"synthetic-777","foodName":"Synthetic yoghurt"},"nutritionContents":[]}"#
        let outcome = try await CustomFoodCreation.create(body) { _ in (Data(json.utf8), self.response(201)) }

        guard case .created(let result) = outcome else {
            return XCTFail("expected created, got \(outcome)")
        }
        XCTAssertEqual(result.foodMetaData.foodId, "synthetic-777")
    }

    func testANon2xxStillThrowsSoARetryIsSafe() async {
        do {
            _ = try await CustomFoodCreation.create(body) { _ in (Data(#"{"message":"bad request"}"#.utf8), self.response(400)) }
            XCTFail("a 400 created nothing and must surface as an error")
        } catch GarminClientError.httpError(let status, _) {
            XCTAssertEqual(status, 400)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }
}
