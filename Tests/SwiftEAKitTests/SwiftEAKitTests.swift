import Testing
@testable import SwiftEAKit

@Suite("SwiftEAKit Tests")
struct SwiftEAKitTests {
    @Test("Version is correct")
    func testVersion() {
        #expect(SwiftEAKit.version == "0.1.0")
    }
}
