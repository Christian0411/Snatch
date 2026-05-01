import XCTest
@testable import SnatchKit

final class FixtureTests: XCTestCase {
    func test_redFixture_loadsAs256x256_topLeftIsRed() throws {
        let frame = try PNGLoader.fixture("frame-red")
        XCTAssertEqual(frame.width, 256)
        XCTAssertEqual(frame.height, 256)
        // First pixel: R, G, B, A
        XCTAssertEqual(frame.bytes[0], 255)  // R
        XCTAssertEqual(frame.bytes[1], 0)    // G
        XCTAssertEqual(frame.bytes[2], 0)    // B
    }

    func test_fixture_throwsWhenBasenameMissing() {
        XCTAssertThrowsError(try PNGLoader.fixture("does-not-exist")) { error in
            guard case PNGLoaderError.fixtureNotFound(let name) = error else {
                XCTFail("Expected .fixtureNotFound, got \(error)")
                return
            }
            XCTAssertEqual(name, "does-not-exist")
        }
    }
}
