import XCTest
import CoreGraphics
@testable import SnatchKit

final class CropperGeometryTests: XCTestCase {

    // MARK: - rect(from:to:)

    func test_rect_topLeftToBottomRight_buildsPositiveExtentRect() {
        let r = CropperGeometry.rect(
            from: CGPoint(x: 10, y: 20),
            to:   CGPoint(x: 110, y: 80)
        )
        XCTAssertEqual(r, CGRect(x: 10, y: 20, width: 100, height: 60))
    }

    func test_rect_bottomRightToTopLeft_normalizesToPositiveExtent() {
        let r = CropperGeometry.rect(
            from: CGPoint(x: 110, y: 80),
            to:   CGPoint(x: 10, y: 20)
        )
        XCTAssertEqual(r, CGRect(x: 10, y: 20, width: 100, height: 60))
    }

    func test_rect_zeroDelta_returnsZeroSizeRect() {
        let r = CropperGeometry.rect(
            from: CGPoint(x: 50, y: 50),
            to:   CGPoint(x: 50, y: 50)
        )
        XCTAssertEqual(r, CGRect(x: 50, y: 50, width: 0, height: 0))
    }

    func test_rect_negativeCoordinates_workNormally() {
        // Multi-display setups can put a region into negative territory.
        let r = CropperGeometry.rect(
            from: CGPoint(x: -100, y: -50),
            to:   CGPoint(x: 0, y: 0)
        )
        XCTAssertEqual(r, CGRect(x: -100, y: -50, width: 100, height: 50))
    }
}
