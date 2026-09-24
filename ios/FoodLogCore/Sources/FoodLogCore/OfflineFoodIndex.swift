// OfflineFoodIndex.swift
//
// The downloadable Czech Open Food Facts index, in memory
// (add-offline-czech-food-index design.md D1/D2). Live OFF search is slow
// and flaky (503s on 2026-09-22), can't work offline, and Garmin's barcode
// lookup misses most Czech EANs. So a weekly CI job
// (tools/build-czech-food-index, .github/workflows/food-index.yml) builds a
// slim gzipped JSON of every Czech OFF product with a name and kcal. The
// app downloads it (OfflineIndexStore) and searches it here, with no network.
//
// This file owns:
//   - the file format: short JSON keys, which must stay in step with
//     tools/build-czech-food-index/transform.mjs;
//   - gzip decoding. Foundation has no gzip API, so the header and trailer
//     are parsed by hand, the raw DEFLATE body goes through
//     `NSData.decompressed(using: .zlib)`, and CRC-32 and size are checked;
//   - the inverted index (D2). Each product's name, alternate name and
//     brand are tokenized ONCE, at load, by `SearchText`: the same
//     normalizer and `CzechLightStemmer` every other source is ranked
//     with. There is deliberately no second normalizer here. Both the
//     folded text and the stem of every word are posted, in one sorted
//     term list, so exact, stem, prefix, stem-prefix and bounded fuzzy
//     (first two letters shared) candidates can all be gathered cheaply;
//   - pre-scoring. The candidates are scored with `SearchRanker`'s own
//     text match on the pre-tokenized names, and only the top 50 are
//     handed to the engine, which ranks them again with everything else.
//     Without this cap a short query would hand thousands of rows to the
//     per-keystroke ranking;
//   - per-keystroke cost bounds. This runs on every keystroke with no
//     debounce, and a short prefix ("p", "po") matches a large share of the
//     ~8k products. So a query needs a word of at least
//     `minimumWordLength` letters (a single letter gets nothing from the
//     index: 50 arbitrary products out of thousands are noise, and remote
//     OFF is gated the same way), a shorter word only looks up its exact
//     posting instead of a whole prefix range (the ranker never
//     prefix-matches it in a multi-word query either), and the gathering and
//     scoring loops stop as soon as the searching task is cancelled by the
//     next keystroke instead of finishing work nobody will see.
// Known gap: the ranker's "typo in the FIRST letter" tier has no candidate
// gathering here. Bounding fuzzy lookup by the first two letters is what
// keeps it cheap.
//
// Pure and synchronous. Used by OfflineCzechIndexSource (search), the
// barcode fallback (`product(code:)`) and OfflineIndexStore (decode and
// verify before install). Tested by OfflineFoodIndexTests.

import Foundation

/// One product of the offline index (design.md D1's record).
public struct OfflineIndexProduct: Codable, Sendable, Equatable {
    public let code: String
    public let name: String
    /// Another name the product is known by (usually English), for matching.
    public let alternateName: String?
    public let brand: String?
    /// Pack size as printed ("250 g"). Informational only.
    public let quantity: String?
    /// Per 100 g.
    public let kcal: Double
    public let carbs: Double?
    public let protein: Double?
    public let fat: Double?
    public let sugar: Double?
    public let fiber: Double?
    /// Grams of salt per 100 g (OFF's `salt_100g`).
    public let salt: Double?

    enum CodingKeys: String, CodingKey {
        case code = "c"
        case name = "n"
        case alternateName = "e"
        case brand = "b"
        case quantity = "q"
        case kcal = "k"
        case carbs = "cb"
        case protein = "p"
        case fat = "f"
        case sugar = "s"
        case fiber = "fi"
        case salt = "sa"
    }

    public init(
        code: String,
        name: String,
        alternateName: String? = nil,
        brand: String? = nil,
        quantity: String? = nil,
        kcal: Double,
        carbs: Double? = nil,
        protein: Double? = nil,
        fat: Double? = nil,
        sugar: Double? = nil,
        fiber: Double? = nil,
        salt: Double? = nil
    ) {
        self.code = code
        self.name = name
        self.alternateName = alternateName
        self.brand = brand
        self.quantity = quantity
        self.kcal = kcal
        self.carbs = carbs
        self.protein = protein
        self.fat = fat
        self.sugar = sugar
        self.fiber = fiber
        self.salt = salt
    }

    /// The same shape a live Open Food Facts hit has
    /// (`OpenFoodFactsClient.hit(from:)`): the EAN as the id, and one
    /// implicit 100 g serving. Live and offline copies of a product
    /// therefore dedup by identity and take the same Garmin-match route.
    public var food: Food {
        let serving = Serving(
            id: "100g",
            unit: "g",
            numberOfUnits: 100,
            calories: kcal,
            carbs: carbs,
            protein: protein,
            fat: fat,
            fiber: fiber,
            sugar: sugar,
            // salt g -> sodium mg (sodium = salt / 2.5).
            sodium: salt.map { $0 * 400 }
        )
        return Food(id: code, name: name, brandName: brand, source: .openFoodFacts, servings: [serving])
    }

    public var alternateNames: [String] {
        alternateName.map { [$0] } ?? []
    }
}

/// The decoded file: `{ "schema": 1, "products": [...] }`.
public struct OfflineIndexFile: Codable, Sendable {
    /// The only schema this build of the app understands. A newer one is
    /// ignored until the app is updated (design.md D1).
    public static let supportedSchema = 1

    public let schema: Int
    public let products: [OfflineIndexProduct]

    public init(schema: Int = OfflineIndexFile.supportedSchema, products: [OfflineIndexProduct]) {
        self.schema = schema
        self.products = products
    }
}

/// `manifest.json`, published next to the index file.
public struct OfflineIndexManifest: Codable, Sendable, Equatable {
    public let schema: Int
    public let version: String
    public let count: Int
    /// The index file's name, relative to the manifest's URL.
    public let file: String
    /// Hex SHA-256 of the gzipped file, exactly as downloaded.
    public let sha256: String
    public let bytes: Int
    public let builtAt: String?
    public let license: String?

    public init(schema: Int, version: String, count: Int, file: String, sha256: String, bytes: Int, builtAt: String? = nil, license: String? = nil) {
        self.schema = schema
        self.version = version
        self.count = count
        self.file = file
        self.sha256 = sha256
        self.bytes = bytes
        self.builtAt = builtAt
        self.license = license
    }
}

public enum OfflineIndexError: Error, Sendable, Equatable {
    case notGzip
    case corruptGzip(String)
    case unsupportedSchema(Int)
    case decodingFailed(String)
    case checksumMismatch(expected: String, actual: String)
    case invalidManifest(String)
    case httpStatus(Int)
}

extension OfflineIndexError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .notGzip: return "The downloaded index isn't a gzip file."
        case .corruptGzip(let detail): return "The downloaded index is corrupted (\(detail))."
        case .unsupportedSchema(let schema): return "The index uses format \(schema), which needs a newer app."
        case .decodingFailed(let detail): return "The index couldn't be read (\(detail))."
        case .checksumMismatch: return "The downloaded index failed its checksum."
        case .invalidManifest(let detail): return "The index manifest is invalid (\(detail))."
        case .httpStatus(let code): return "The index server answered HTTP \(code)."
        }
    }
}

/// User-facing text for the same errors (add-localization wave 3.2).
/// `description` above deliberately stays English: `OfflineIndexStore`
/// interpolates it into `DiagnosticsLog` messages, which are never
/// localized. The technical `detail` payloads (e.g. "CRC mismatch") are
/// left untranslated inside the parentheses.
extension OfflineIndexError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notGzip:
            return String(localized: "The downloaded index isn't a gzip file.", bundle: .module, comment: "Offline food database update error.")
        case .corruptGzip(let detail):
            return String(localized: "The downloaded index is corrupted (\(detail)).", bundle: .module, comment: "Offline food database update error. %@ is a technical detail in English.")
        case .unsupportedSchema(let schema):
            return String(localized: "The index uses format \(schema), which needs a newer app.", bundle: .module, comment: "Offline food database update error. %lld is the format version number.")
        case .decodingFailed(let detail):
            return String(localized: "The index couldn't be read (\(detail)).", bundle: .module, comment: "Offline food database update error. %@ is a technical detail in English.")
        case .checksumMismatch:
            return String(localized: "The downloaded index failed its checksum.", bundle: .module, comment: "Offline food database update error.")
        case .invalidManifest(let detail):
            return String(localized: "The index manifest is invalid (\(detail)).", bundle: .module, comment: "Offline food database update error. %@ is a technical detail in English.")
        case .httpStatus(let code):
            return String(localized: "The index server answered HTTP \(code).", bundle: .module, comment: "Offline food database update error. %lld is the HTTP status code.")
        }
    }
}

// MARK: - The index

public struct OfflineFoodIndex: Sendable {
    /// D2: at most this many pre-scored candidates per query.
    public static let maximumCandidates = 50

    /// A query needs a word at least this long before the index answers,
    /// and only a term at least this long is expanded to every term it
    /// prefixes. Matches `SearchRanker.tierWeight`'s minimum prefix length
    /// for a multi-word query, so candidate gathering stays complete for
    /// every query the index answers.
    public static let minimumWordLength = 2

    /// How many rows are scored between two cancellation checks.
    private static let cancellationCheckInterval = 256

    public let products: [OfflineIndexProduct]
    private let entries: [Entry]
    private let rowByCode: [String: Int]
    private let postings: [String: [Int]]
    private let sortedTerms: [String]

    private struct Entry: Sendable {
        /// `SearchText.fold(name)`, for the tie-break `SearchRanker.isRankedBefore` uses.
        let foldedName: String
        let nameTokens: [SearchToken]
        let alternateTokens: [SearchToken]
        let brandTokens: [SearchToken]
    }

    private struct ScoredRow {
        let row: Int
        let relevance: Double
    }

    public init(products: [OfflineIndexProduct]) {
        var entries: [Entry] = []
        entries.reserveCapacity(products.count)
        var rowByCode: [String: Int] = [:]
        var postings: [String: [Int]] = [:]

        for (row, product) in products.enumerated() {
            let entry = Entry(
                foldedName: SearchText.fold(product.name),
                nameTokens: SearchText.tokenize(product.name),
                alternateTokens: SearchText.tokenize(product.alternateName ?? ""),
                brandTokens: SearchText.tokenize(product.brand ?? "").filter { !$0.isQuantity }
            )
            entries.append(entry)
            if rowByCode[product.code] == nil {
                rowByCode[product.code] = row
            }
            var terms = Set<String>()
            for token in entry.nameTokens + entry.alternateTokens + entry.brandTokens where !token.isQuantity {
                terms.insert(token.text)
                terms.insert(token.stem)
            }
            // Rows are visited in ascending order, so every posting list
            // stays sorted and duplicate-free.
            for term in terms {
                postings[term, default: []].append(row)
            }
        }

        self.products = products
        self.entries = entries
        self.rowByCode = rowByCode
        self.postings = postings
        self.sortedTerms = postings.keys.sorted()
    }

    public var count: Int { products.count }

    /// gunzip -> JSON -> schema check -> index. Throws `OfflineIndexError`.
    public static func decode(gzipData: Data) throws -> OfflineFoodIndex {
        let json = try GzipInflate.inflate(gzipData)
        struct SchemaProbe: Decodable { let schema: Int }
        let probe: SchemaProbe
        do {
            probe = try JSONDecoder().decode(SchemaProbe.self, from: json)
        } catch {
            throw OfflineIndexError.decodingFailed(String(describing: error))
        }
        guard probe.schema == OfflineIndexFile.supportedSchema else {
            throw OfflineIndexError.unsupportedSchema(probe.schema)
        }
        let file: OfflineIndexFile
        do {
            file = try JSONDecoder().decode(OfflineIndexFile.self, from: json)
        } catch {
            throw OfflineIndexError.decodingFailed(String(describing: error))
        }
        return OfflineFoodIndex(products: file.products)
    }

    // MARK: Barcode lookup (design.md D4)

    /// The product for a scanned or typed barcode. Tries the code as given,
    /// then the UPC-A variants (`BarcodeNormalization`, plus a zero-padded
    /// form of a 12-digit code, since OFF stores UPC-A both ways).
    public func product(code: String) -> OfflineIndexProduct? {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var candidates = BarcodeNormalization.candidates(forScanned: trimmed)
        if trimmed.count == 12 {
            candidates.append("0" + trimmed)
        }
        for candidate in candidates {
            if let row = rowByCode[candidate] {
                return products[row]
            }
        }
        return nil
    }

    // MARK: Search (design.md D2)

    /// The best `limit` products for `query`, as unscored candidates for the
    /// engine's ranking. Empty for a query with no word of at least
    /// `minimumWordLength` letters (a single letter, or only pack sizes),
    /// and empty when the calling task is cancelled part-way (the caller
    /// checks for cancellation itself; see OfflineCzechIndexSource).
    public func candidates(
        for query: SearchQuery,
        limit: Int = OfflineFoodIndex.maximumCandidates,
        weights: SearchWeights = .standard
    ) -> [SearchCandidate] {
        let words = query.wordTokens
        guard limit > 0, words.contains(where: { $0.text.count >= OfflineFoodIndex.minimumWordLength }) else { return [] }

        var rows = Set<Int>()
        for token in words {
            if Task.isCancelled { return [] }
            rows.formUnion(rowsMatching(token))
        }

        var scored: [ScoredRow] = []
        scored.reserveCapacity(rows.count)
        var visited = 0
        for row in rows {
            if visited % OfflineFoodIndex.cancellationCheckInterval == 0, Task.isCancelled { return [] }
            visited += 1
            if let relevance = relevance(of: entries[row], for: query, weights: weights) {
                scored.append(ScoredRow(row: row, relevance: relevance))
            }
        }
        if Task.isCancelled { return [] }
        // Same order as SearchRanker.isRankedBefore (score, then folded
        // name, then id), so the cap cuts where the final ranking would.
        scored.sort { lhs, rhs in
            if lhs.relevance != rhs.relevance { return lhs.relevance > rhs.relevance }
            let lhsName = entries[lhs.row].foldedName
            let rhsName = entries[rhs.row].foldedName
            if lhsName != rhsName { return lhsName < rhsName }
            return products[lhs.row].code < products[rhs.row].code
        }
        return scored.prefix(limit).map { item in
            let product = products[item.row]
            return SearchCandidate(food: product.food, origin: .offlineIndex, alternateNames: product.alternateNames)
        }
    }

    /// `SearchRanker.evaluate`'s text part (name, or alternate name at the
    /// alias factor), on the tokens computed at load. `nil` below the threshold.
    private func relevance(of entry: Entry, for query: SearchQuery, weights: SearchWeights) -> Double? {
        var best: Double?
        let primary = SearchRanker.textMatch(queryTokens: query.tokens, nameTokens: entry.nameTokens, brandTokens: entry.brandTokens, weights: weights)
        if primary.text >= weights.textThreshold {
            best = SearchRanker.relevance(primary, weights: weights)
        }
        if !entry.alternateTokens.isEmpty {
            let alias = SearchRanker.textMatch(queryTokens: query.tokens, nameTokens: entry.alternateTokens, brandTokens: entry.brandTokens, weights: weights)
            if alias.text >= weights.textThreshold {
                let aliasRelevance = SearchRanker.relevance(alias, weights: weights) * weights.aliasFactor
                best = max(best ?? 0, aliasRelevance)
            }
        }
        return best
    }

    /// Every row that one query word could match at some ranker tier.
    private func rowsMatching(_ token: SearchToken) -> Set<Int> {
        var rows = Set<Int>()
        // Exact, same stem, prefix of the word being typed, and stem prefix.
        // A term shorter than `minimumWordLength` can only match exactly
        // (the ranker's prefix tier needs 2 letters in a multi-word query,
        // its stem-prefix tier 3), so it skips the prefix range, which for
        // one letter is a large share of the whole index.
        for prefix in Set([token.text, token.stem]) where !prefix.isEmpty {
            if prefix.count >= OfflineFoodIndex.minimumWordLength {
                for term in termsWithPrefix(prefix) {
                    rows.formUnion(postings[term] ?? [])
                }
            } else {
                rows.formUnion(postings[prefix] ?? [])
            }
        }
        // Fuzzy, bounded to terms sharing the first two letters, with the
        // ranker's own edit budget (1 edit from 4 letters, 2 from 8).
        let length = token.text.count
        let maxEdits = length >= 8 ? 2 : (length >= 4 ? 1 : 0)
        if maxEdits > 0 {
            for term in termsWithPrefix(String(token.text.prefix(2))) where abs(term.count - length) <= maxEdits {
                if EditDistance.damerauLevenshtein(token.text, term, maxDistance: maxEdits) != nil {
                    rows.formUnion(postings[term] ?? [])
                }
            }
        }
        return rows
    }

    /// The contiguous run of `sortedTerms` starting with `prefix` (binary search).
    private func termsWithPrefix(_ prefix: String) -> ArraySlice<String> {
        var low = 0
        var high = sortedTerms.count
        while low < high {
            let mid = (low + high) / 2
            if sortedTerms[mid] < prefix {
                low = mid + 1
            } else {
                high = mid
            }
        }
        var end = low
        while end < sortedTerms.count, sortedTerms[end].hasPrefix(prefix) {
            end += 1
        }
        return sortedTerms[low..<end]
    }
}

// MARK: - gzip

/// Minimal single-member gzip (RFC 1952) decoder: parse the header, inflate
/// the raw DEFLATE body with Foundation, verify CRC-32 and size.
enum GzipInflate {
    static func inflate(_ data: Data) throws -> Data {
        let bytes = [UInt8](data)
        guard bytes.count >= 18, bytes[0] == 0x1f, bytes[1] == 0x8b, bytes[2] == 8 else {
            throw OfflineIndexError.notGzip
        }
        let flags = bytes[3]
        var offset = 10
        if flags & 0x04 != 0 { // FEXTRA
            guard offset + 2 <= bytes.count else { throw OfflineIndexError.corruptGzip("truncated header") }
            offset += 2 + (Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8))
        }
        if flags & 0x08 != 0 { // FNAME
            offset = try skipZeroTerminated(bytes, from: offset)
        }
        if flags & 0x10 != 0 { // FCOMMENT
            offset = try skipZeroTerminated(bytes, from: offset)
        }
        if flags & 0x02 != 0 { // FHCRC
            offset += 2
        }
        let trailerStart = bytes.count - 8
        guard offset < trailerStart else { throw OfflineIndexError.corruptGzip("truncated header") }

        let body = Data(bytes[offset..<trailerStart])
        let inflated: Data
        do {
            inflated = try (body as NSData).decompressed(using: .zlib) as Data
        } catch {
            throw OfflineIndexError.corruptGzip("inflate failed")
        }
        let expectedCRC = readUInt32LE(bytes, at: trailerStart)
        let expectedSize = readUInt32LE(bytes, at: trailerStart + 4)
        guard UInt32(truncatingIfNeeded: inflated.count) == expectedSize else {
            throw OfflineIndexError.corruptGzip("size mismatch")
        }
        guard GzipCRC32.checksum(inflated) == expectedCRC else {
            throw OfflineIndexError.corruptGzip("CRC mismatch")
        }
        return inflated
    }

    private static func skipZeroTerminated(_ bytes: [UInt8], from start: Int) throws -> Int {
        var index = start
        while index < bytes.count, bytes[index] != 0 {
            index += 1
        }
        guard index < bytes.count else { throw OfflineIndexError.corruptGzip("truncated header") }
        return index + 1
    }

    private static func readUInt32LE(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }
}

/// CRC-32 (IEEE 802.3, reflected, as gzip uses it).
enum GzipCRC32 {
    static let table: [UInt32] = (0..<256).map { value -> UInt32 in
        var crc = UInt32(value)
        for _ in 0..<8 {
            crc = (crc & 1) != 0 ? (0xEDB8_8320 ^ (crc >> 1)) : (crc >> 1)
        }
        return crc
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            for byte in buffer {
                crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
            }
        }
        return crc ^ 0xFFFF_FFFF
    }
}
