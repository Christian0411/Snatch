import XCTest
@testable import SnatchKit

final class RGBAFrameTests: XCTestCase {
    func test_init_storesAllFields() {
        let bytes = Data(repeating: 0xFF, count: 4 * 8 * 8)  // 8x8 RGBA, all white
        let frame = RGBAFrame(bytes: bytes, width: 8, height: 8)

        XCTAssertEqual(frame.bytes.count, 256)
        XCTAssertEqual(frame.width, 8)
        XCTAssertEqual(frame.height, 8)
    }

    func test_byteCount_matchesWidthTimesHeightTimesFour() {
        let frame = RGBAFrame(bytes: Data(repeating: 0, count: 4 * 16 * 9), width: 16, height: 9)
        XCTAssertEqual(frame.bytes.count, frame.width * frame.height * 4)
    }
}
