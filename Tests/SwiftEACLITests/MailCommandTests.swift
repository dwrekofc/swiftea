import XCTest
@testable import SwiftEACLI
@testable import SwiftEAKit

final class MailCommandTests: XCTestCase {

    func testMailSyncOptionsDefaults() {
        let options = MailSyncOptions()
        XCTAssertFalse(options.metadataOnly)
        XCTAssertNil(options.mailboxFilter)
        XCTAssertTrue(options.inboxOnlyBodyParsing)
        XCTAssertGreaterThanOrEqual(options.parallelWorkers, 1)
    }

    func testMailSyncOptionsCustomParallel() {
        let options = MailSyncOptions(parallelWorkers: 8)
        XCTAssertEqual(options.parallelWorkers, 8)
    }
}
