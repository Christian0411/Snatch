import XCTest
import CoreGraphics
@testable import SnatchKit

final class SCStreamWrapperHelperTests: XCTestCase {

    func test_outputSize_retina_doublesOnHighDpi() {
        let (w, h) = SCStreamWrapper.outputSize(
            for: CGRect(x: 0, y: 0, width: 320, height: 240),
            scale: .retina,
            displayScale: 2.0
        )
        XCTAssertEqual(w, 640)
        XCTAssertEqual(h, 480)
    }

    func test_outputSize_retina_passthroughOnNonRetina() {
        let (w, h) = SCStreamWrapper.outputSize(
            for: CGRect(x: 0, y: 0, width: 320, height: 240),
            scale: .retina,
            displayScale: 1.0
        )
        XCTAssertEqual(w, 320)
        XCTAssertEqual(h, 240)
    }

    func test_outputSize_standard_logicalPixels() {
        let (w, h) = SCStreamWrapper.outputSize(
            for: CGRect(x: 0, y: 0, width: 400, height: 300),
            scale: .standard,
            displayScale: 2.0
        )
        XCTAssertEqual(w, 400)
        XCTAssertEqual(h, 300)
    }

    func test_outputSize_compact_halfLogical() {
        let (w, h) = SCStreamWrapper.outputSize(
            for: CGRect(x: 0, y: 0, width: 400, height: 300),
            scale: .compact,
            displayScale: 2.0
        )
        XCTAssertEqual(w, 200)
        XCTAssertEqual(h, 150)
    }

    func test_outputSize_neverReturnsZero() {
        let (w, h) = SCStreamWrapper.outputSize(
            for: CGRect(x: 0, y: 0, width: 0.4, height: 0.4),
            scale: .compact,
            displayScale: 1.0
        )
        XCTAssertGreaterThanOrEqual(w, 1)
        XCTAssertGreaterThanOrEqual(h, 1)
    }
}
