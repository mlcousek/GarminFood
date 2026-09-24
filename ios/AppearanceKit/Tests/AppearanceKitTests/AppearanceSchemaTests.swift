// Smoke test for the AppearanceKit package skeleton (task 1.1): proves the
// package builds and its test target links in CI.

import XCTest
@testable import AppearanceKit

final class AppearanceSchemaTests: XCTestCase {
    func testCurrentVersionIsOne() {
        XCTAssertEqual(AppearanceSchema.currentVersion, 1)
    }
}
