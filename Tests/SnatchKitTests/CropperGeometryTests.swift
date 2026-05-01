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

    // MARK: - handleFrames(for:handleSize:)

    func test_handleFrames_returnsAllEightResizeHandles() {
        let r = CGRect(x: 100, y: 100, width: 200, height: 100)
        let frames = CropperGeometry.handleFrames(for: r, handleSize: 12)
        XCTAssertEqual(Set(frames.keys), Set(CropperHandle.resizeCases))
    }

    func test_handleFrames_topLeftHandle_isCenteredOnRectTopLeftCorner() {
        let r = CGRect(x: 100, y: 100, width: 200, height: 100)
        let frames = CropperGeometry.handleFrames(for: r, handleSize: 12)
        // Handle is 12×12 centered on (100,100) → origin (94,94)
        XCTAssertEqual(frames[.topLeft], CGRect(x: 94, y: 94, width: 12, height: 12))
    }

    func test_handleFrames_bottomRightHandle_isCenteredOnRectBottomRightCorner() {
        let r = CGRect(x: 100, y: 100, width: 200, height: 100)
        let frames = CropperGeometry.handleFrames(for: r, handleSize: 12)
        // Bottom-right corner of r is (300, 200) → handle origin (294, 194)
        XCTAssertEqual(frames[.bottomRight], CGRect(x: 294, y: 194, width: 12, height: 12))
    }

    func test_handleFrames_topEdgeHandle_isCenteredOnTopMidpoint() {
        let r = CGRect(x: 100, y: 100, width: 200, height: 100)
        let frames = CropperGeometry.handleFrames(for: r, handleSize: 12)
        // Top midpoint is (200, 100) → handle origin (194, 94)
        XCTAssertEqual(frames[.top], CGRect(x: 194, y: 94, width: 12, height: 12))
    }

    func test_handleFrames_doesNotIncludeBodyCase() {
        let r = CGRect(x: 100, y: 100, width: 200, height: 100)
        let frames = CropperGeometry.handleFrames(for: r, handleSize: 12)
        XCTAssertNil(frames[.body])
    }

    // MARK: - hitTest(point:in:handleSize:)

    func test_hitTest_pointFarOutsideRect_returnsNil() {
        let r = CGRect(x: 100, y: 100, width: 200, height: 100)
        XCTAssertNil(CropperGeometry.hitTest(point: CGPoint(x: 0, y: 0), in: r, handleSize: 12))
    }

    func test_hitTest_pointDeepInsideRect_returnsBody() {
        let r = CGRect(x: 100, y: 100, width: 200, height: 100)
        XCTAssertEqual(
            CropperGeometry.hitTest(point: CGPoint(x: 200, y: 150), in: r, handleSize: 12),
            .body
        )
    }

    func test_hitTest_pointOnTopLeftCorner_returnsTopLeftHandle() {
        let r = CGRect(x: 100, y: 100, width: 200, height: 100)
        XCTAssertEqual(
            CropperGeometry.hitTest(point: CGPoint(x: 100, y: 100), in: r, handleSize: 12),
            .topLeft
        )
    }

    func test_hitTest_pointOnBottomRightCorner_returnsBottomRightHandle() {
        let r = CGRect(x: 100, y: 100, width: 200, height: 100)
        XCTAssertEqual(
            CropperGeometry.hitTest(point: CGPoint(x: 300, y: 200), in: r, handleSize: 12),
            .bottomRight
        )
    }

    func test_hitTest_pointOnRightEdgeMidpoint_returnsRightHandle() {
        let r = CGRect(x: 100, y: 100, width: 200, height: 100)
        // Right midpoint is (300, 150)
        XCTAssertEqual(
            CropperGeometry.hitTest(point: CGPoint(x: 300, y: 150), in: r, handleSize: 12),
            .right
        )
    }

    func test_hitTest_handlesTakePrecedenceOverBody_whenRectIsLargerThanHandle() {
        // Inside the rect AND inside the top-left handle frame. Should resolve
        // to .topLeft (the more specific intent).
        let r = CGRect(x: 100, y: 100, width: 200, height: 100)
        XCTAssertEqual(
            CropperGeometry.hitTest(point: CGPoint(x: 102, y: 102), in: r, handleSize: 12),
            .topLeft
        )
    }
}
