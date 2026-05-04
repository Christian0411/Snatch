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

    // MARK: - mode == .have(rect)

    private func haveState() -> CropperState {
        CropperState(initial: CGRect(x: 50, y: 50, width: 100, height: 100))
    }

    func test_have_overTopLeft_isResizeNWSE() {
        XCTAssertEqual(
            haveState().desiredCursor(at: CGPoint(x: 50, y: 50), handleSize: handleSize, isOverRecordButton: false),
            .resizeNWSE
        )
    }

    func test_have_overBottomRight_isResizeNWSE() {
        XCTAssertEqual(
            haveState().desiredCursor(at: CGPoint(x: 150, y: 150), handleSize: handleSize, isOverRecordButton: false),
            .resizeNWSE
        )
    }

    func test_have_overTopRight_isResizeNESW() {
        XCTAssertEqual(
            haveState().desiredCursor(at: CGPoint(x: 150, y: 50), handleSize: handleSize, isOverRecordButton: false),
            .resizeNESW
        )
    }

    func test_have_overBottomLeft_isResizeNESW() {
        XCTAssertEqual(
            haveState().desiredCursor(at: CGPoint(x: 50, y: 150), handleSize: handleSize, isOverRecordButton: false),
            .resizeNESW
        )
    }

    func test_have_overTopEdge_isResizeVertical() {
        XCTAssertEqual(
            haveState().desiredCursor(at: CGPoint(x: 100, y: 50), handleSize: handleSize, isOverRecordButton: false),
            .resizeVertical
        )
    }

    func test_have_overBottomEdge_isResizeVertical() {
        XCTAssertEqual(
            haveState().desiredCursor(at: CGPoint(x: 100, y: 150), handleSize: handleSize, isOverRecordButton: false),
            .resizeVertical
        )
    }

    func test_have_overLeftEdge_isResizeHorizontal() {
        XCTAssertEqual(
            haveState().desiredCursor(at: CGPoint(x: 50, y: 100), handleSize: handleSize, isOverRecordButton: false),
            .resizeHorizontal
        )
    }

    func test_have_overRightEdge_isResizeHorizontal() {
        XCTAssertEqual(
            haveState().desiredCursor(at: CGPoint(x: 150, y: 100), handleSize: handleSize, isOverRecordButton: false),
            .resizeHorizontal
        )
    }

    func test_have_insideBody_isGrab() {
        XCTAssertEqual(
            haveState().desiredCursor(at: CGPoint(x: 100, y: 100), handleSize: handleSize, isOverRecordButton: false),
            .grab
        )
    }

    func test_have_outsideRect_isCrosshair() {
        XCTAssertEqual(
            haveState().desiredCursor(at: CGPoint(x: 10, y: 10), handleSize: handleSize, isOverRecordButton: false),
            .crosshair
        )
    }

    func test_have_cursorNil_isArrow() {
        XCTAssertEqual(
            haveState().desiredCursor(at: nil, handleSize: handleSize, isOverRecordButton: false),
            .arrow
        )
    }

    // MARK: - Record-button override

    func test_have_overRecordButton_overridesGrab() {
        // Cursor would otherwise resolve to .grab inside the rect's body.
        XCTAssertEqual(
            haveState().desiredCursor(at: CGPoint(x: 100, y: 100), handleSize: handleSize, isOverRecordButton: true),
            .arrow
        )
    }

    func test_idle_overRecordButton_isArrow() {
        // Record button is hidden in .idle, but the override still applies if true is passed.
        let s = CropperState(initial: nil)
        XCTAssertEqual(
            s.desiredCursor(at: CGPoint(x: 100, y: 100), handleSize: handleSize, isOverRecordButton: true),
            .arrow
        )
    }

    // MARK: - mode == .resizing (gesture lock)

    func test_resizing_body_isGrabbing_anywhere() {
        // Start with a committed rect; mouseDown inside the body drives state into .resizing(.body).
        let rect = CGRect(x: 50, y: 50, width: 100, height: 100)
        var s = CropperState(initial: rect)
        s = s.applyMouseDown(at: CGPoint(x: 100, y: 100), handleSize: handleSize)
        XCTAssertEqual(
            s.desiredCursor(at: CGPoint(x: 100, y: 100), handleSize: handleSize, isOverRecordButton: false),
            .grabbing
        )
        // Cursor wandered far off the rect — still grabbing.
        XCTAssertEqual(
            s.desiredCursor(at: CGPoint(x: 999, y: 999), handleSize: handleSize, isOverRecordButton: false),
            .grabbing
        )
    }

    func test_resizing_topLeft_isResizeNWSE_anywhere() {
        let rect = CGRect(x: 50, y: 50, width: 100, height: 100)
        var s = CropperState(initial: rect)
        s = s.applyMouseDown(at: CGPoint(x: 50, y: 50), handleSize: handleSize)
        XCTAssertEqual(
            s.desiredCursor(at: CGPoint(x: 50, y: 50), handleSize: handleSize, isOverRecordButton: false),
            .resizeNWSE
        )
        // Cursor drifts off the handle — gesture cursor stays locked.
        XCTAssertEqual(
            s.desiredCursor(at: CGPoint(x: 200, y: 200), handleSize: handleSize, isOverRecordButton: false),
            .resizeNWSE
        )
    }

    func test_resizing_leftEdge_isResizeHorizontal_anywhere() {
        let rect = CGRect(x: 50, y: 50, width: 100, height: 100)
        var s = CropperState(initial: rect)
        s = s.applyMouseDown(at: CGPoint(x: 50, y: 100), handleSize: handleSize)
        XCTAssertEqual(
            s.desiredCursor(at: CGPoint(x: 50, y: 100), handleSize: handleSize, isOverRecordButton: false),
            .resizeHorizontal
        )
        XCTAssertEqual(
            s.desiredCursor(at: CGPoint(x: 999, y: 999), handleSize: handleSize, isOverRecordButton: false),
            .resizeHorizontal
        )
    }
}
