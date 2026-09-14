// GarminClient.swift
//
// The API client. Read routes (`searchFood`, `dailyFoodLog`) are confirmed
// live against the real account as of 2026-09-14 (docs/garmin-routes.json).
// Write routes (`createFoodLogEntry`, `deleteFoodLogEntries`) implement the
// DOCUMENTED-BUT-UNCONFIRMED contract in docs/garmin-food-log-contract.md --
// faithful to the best available inference, but genuinely untested against
// a real write. See CreateFoodLogEntryRequest's doc comment in
// GarminModels.swift for exactly what's uncertain and why.
//
// This type deliberately does not decode or trust the response body of
// `createFoodLogEntry` for anything -- design.md D5 already assumes the
// only trustworthy signal after a write is a fresh read of the day's log
// (Reconciliation.swift), so a wrong guess about the create response shape
// can't silently corrupt anything downstream.

import Foundation

public enum GarminClientError: Error {
    case invalidURL
    case noHTTPResponse
    case unauthorized(body: String?)
    case rateLimited(retryAfterSeconds: Double?)
    case httpError(statusCode: Int, body: String?)
    case decodingFailed(description: String)
}

public struct GarminClient: Sendable {
    private let tokenProvider: TokenProvider
    private let urlSession: URLSession
    private let baseURL: String

    public init(
        tokenProvider: TokenProvider = .shared,
        urlSession: URLSession = .shared,
        baseURL: String = GarminAPI.connectAPI
    ) {
        self.tokenProvider = tokenProvider
        self.urlSession = urlSession
        self.baseURL = baseURL
    }

    private static let decoder = JSONDecoder()
    private static let encoder = JSONEncoder()

    // MARK: - Reads

    /// GET `/nutrition-service/food/search?searchExpression={term}`.
    /// Confirmed live 2026-09-14 -- Czech search terms return real results.
    public func searchFood(term: String) async throws -> FoodSearchResponse {
        let (data, response) = try await get(
            path: "/nutrition-service/food/search",
            query: [URLQueryItem(name: "searchExpression", value: term)]
        )
        try Self.throwIfNotSuccessful(response, data: data)
        do {
            return try Self.decoder.decode(FoodSearchResponse.self, from: data)
        } catch {
            throw GarminClientError.decodingFailed(description: String(describing: error))
        }
    }

    /// GET `/nutrition-service/food/logs/{date}` (`date` is `YYYY-MM-DD`).
    /// Confirmed live 2026-09-14 -- the plural "logs" route; the vault's
    /// singular "log" route 404s and is NOT what this calls.
    ///
    /// Returns `nil` on 404 rather than throwing. Per design.md D7 ("auth
    /// failure is loud; everything else is quiet") and the garmin-auth
    /// spec's "a route is merely unavailable, not an auth failure" scenario,
    /// no logged food for a date is missing DATA, not a broken credential --
    /// callers must not conflate the two the way the vault's own
    /// `getNutritionLog()` historically did (see design.md D7's rationale).
    public func dailyFoodLog(date: String) async throws -> DailyFoodLog? {
        let (data, response) = try await get(path: "/nutrition-service/food/logs/\(date)", query: [])
        if response.statusCode == 404 { return nil }
        try Self.throwIfNotSuccessful(response, data: data)
        do {
            return try Self.decoder.decode(DailyFoodLog.self, from: data)
        } catch {
            throw GarminClientError.decodingFailed(description: String(describing: error))
        }
    }

    /// GET `/nutrition-service/food/search/barCode?barCode={ean}`.
    ///
    /// Added for `add-food-log-core`'s (deprioritized, per that change's
    /// design.md D3) barcode-scanning feature. Route CONFIRMED to exist
    /// 2026-09-14 (a no-param request 400s naming the right parameter), but
    /// the SUCCESS payload shape is UNCONFIRMED -- every real-looking EAN-13
    /// tried so far 404'd ("no product for this barcode", not "route
    /// missing"). Modeled as a single `FoodSearchResult` (the same shape one
    /// entry of `searchFood`'s `results` array uses) since a barcode lookup
    /// is conceptually "find the one food this code identifies" -- if
    /// Garmin's real response turns out to wrap this differently (e.g.
    /// `{ result: {...} }` or a bare `results: [...]` array like the text
    /// search), this decode will fail and surface as
    /// `GarminClientError.decodingFailed`, not silently return the wrong
    /// thing.
    ///
    /// Returns `nil` on 404, matching `dailyFoodLog`'s convention: no
    /// product for this barcode is missing DATA, not a broken credential or
    /// a broken route.
    public func searchFoodByBarcode(ean: String) async throws -> FoodSearchResult? {
        let (data, response) = try await get(
            path: "/nutrition-service/food/search/barCode",
            query: [URLQueryItem(name: "barCode", value: ean)]
        )
        if response.statusCode == 404 { return nil }
        try Self.throwIfNotSuccessful(response, data: data)
        do {
            return try Self.decoder.decode(FoodSearchResult.self, from: data)
        } catch {
            throw GarminClientError.decodingFailed(description: String(describing: error))
        }
    }

    // MARK: - Writes (documented, not yet confirmed by a real write)

    /// POST `/nutrition-service/food/logs`.
    ///
    /// IMPORTANT: nothing in this package invokes this automatically. Task
    /// 11.4 -- the first real write, against a deliberately distinctive
    /// test food on a date the owner can inspect and delete by hand -- is a
    /// human-supervised, one-off action, not something this client, the
    /// Outbox, or any test triggers on its own.
    @discardableResult
    public func createFoodLogEntry(_ entry: CreateFoodLogEntryRequest) async throws -> HTTPURLResponse {
        let (data, response) = try await post(path: "/nutrition-service/food/logs", body: entry)
        try Self.throwIfNotSuccessful(response, data: data)
        return response
    }

    /// DELETE `/nutrition-service/food/logs`, body `{ "logIds": [...] }`.
    /// `logIds` are the hex `logId` values from a read entry, not `foodId`s.
    /// Used by Reconciliation.swift to remove a detected duplicate.
    @discardableResult
    public func deleteFoodLogEntries(logIds: [String]) async throws -> HTTPURLResponse {
        let (data, response) = try await delete(
            path: "/nutrition-service/food/logs",
            body: DeleteFoodLogEntriesRequest(logIds: logIds)
        )
        try Self.throwIfNotSuccessful(response, data: data)
        return response
    }

    // MARK: - Request plumbing

    private func authorizedRequest(method: String, path: String, query: [URLQueryItem] = []) async throws -> URLRequest {
        guard var components = URLComponents(string: baseURL + path) else {
            throw GarminClientError.invalidURL
        }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw GarminClientError.invalidURL }

        // Propagates GarminAuthError.notSignedIn / .longLivedTokenExpired /
        // .exchangeFailed straight through to the caller -- GarminClient
        // does not catch or reinterpret token errors, so AuthState.report(_:)
        // downstream sees the real underlying error.
        let token = try await tokenProvider.accessToken()

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(GarminUserAgent.value, forHTTPHeaderField: "User-Agent")
        return request
    }

    private func get(path: String, query: [URLQueryItem]) async throws -> (Data, HTTPURLResponse) {
        let request = try await authorizedRequest(method: "GET", path: path, query: query)
        return try await send(request)
    }

    private func post(path: String, body: some Encodable) async throws -> (Data, HTTPURLResponse) {
        var request = try await authorizedRequest(method: "POST", path: path)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Self.encoder.encode(body)
        return try await send(request)
    }

    private func delete(path: String, body: some Encodable) async throws -> (Data, HTTPURLResponse) {
        var request = try await authorizedRequest(method: "DELETE", path: path)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Self.encoder.encode(body)
        return try await send(request)
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GarminClientError.noHTTPResponse
        }
        return (data, http)
    }

    private static func throwIfNotSuccessful(_ response: HTTPURLResponse, data: Data) throws {
        if (200..<300).contains(response.statusCode) { return }
        let body = String(data: data, encoding: .utf8)
        switch response.statusCode {
        case 401:
            throw GarminClientError.unauthorized(body: body)
        case 429:
            let retryAfter = response.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
            throw GarminClientError.rateLimited(retryAfterSeconds: retryAfter)
        default:
            throw GarminClientError.httpError(statusCode: response.statusCode, body: body)
        }
    }
}

// MARK: - Outbox.swift / Reconciliation.swift protocol conformance
//
// Structural conformance: `GarminClient`'s existing method signatures
// already match `FoodLogDelivering` and `FoodLogReconciling` exactly, so
// this is declared here purely to make the relationship explicit and
// discoverable, not because any method bodies are needed.

extension GarminClient: FoodLogDelivering {}
extension GarminClient: FoodLogReconciling {}
