import XCTest
@testable import SwiftEAKit

final class SwiftEAKitTests: XCTestCase {
    func testVersion() {
        XCTAssertEqual(SwiftEAKit.version, "0.1.0")
    }
}
