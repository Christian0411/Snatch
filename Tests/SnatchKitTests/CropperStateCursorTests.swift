import XCTest
import CoreGraphics
@testable import SnatchKit

final class CropperStateCursorTests: XCTestCase {

    private let handleSize: CGFloat = 12

    // MARK: - mode == .idle

    func test_idle_withCursorPresent_isCrosshair() {
        let s = CropperState(initial: nil)
        XCTAssertEqual(
            s.desiredCursor(at: CGPoint(x: 50, y: 50), handleSize: handleSize, isOverRecordButton: false),
            .crosshair
        )
    }

    func test_idle_withCursorNil_isArrow() {
        let s = CropperState(initial: nil)
        XCTAssertEqual(
            s.desiredCursor(at: nil, handleSize: handleSize, isOverRecordButton: false),
            .arrow
        )
    }

    // MARK: - mode == .dragging

    func test_dragging_isCrosshair_anywhere() {
        // Drive into .dragging via mouseDown from .idle.
        var s = CropperState(initial: nil)
        s = s.applyMouseDown(at: CGPoint(x: 10, y: 10), handleSize: handleSize)
        XCTAssertEqual(
            s.desiredCursor(at: CGPoint(x: 10, y: 10), handleSize: handleSize, isOverRecordButton: false),
            .crosshair
        )
        XCTAssertEqual(
            s.desiredCursor(at: CGPoint(x: 999, y: 999), handleSize: handleSize, isOverRecordButton: false),
            .crosshair
        )
    }
}
