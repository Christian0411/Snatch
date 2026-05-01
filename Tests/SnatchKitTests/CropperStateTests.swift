import XCTest
import CoreGraphics
@testable import SnatchKit

final class CropperStateTests: XCTestCase {

    private let handleSize: CGFloat = 12

    // MARK: - Initial state

    func test_initialState_withNoRect_isIdleAndDisplayRectIsNil() {
        let s = CropperState(initial: nil)
        XCTAssertEqual(s.mode, .idle)
        XCTAssertNil(s.displayRect)
    }

    func test_initialState_withRect_isHaveAndDisplayRectMatches() {
        let r = CGRect(x: 100, y: 100, width: 200, height: 100)
        let s = CropperState(initial: r)
        XCTAssertEqual(s.mode, .have(r))
        XCTAssertEqual(s.displayRect, r)
    }

    // MARK: - Idle: any mouse-down starts a fresh drag

    func test_mouseDown_fromIdle_startsDragging() {
        var s = CropperState(initial: nil)
        s = s.applyMouseDown(at: CGPoint(x: 50, y: 60), handleSize: handleSize)
        XCTAssertEqual(s.mode, .dragging(anchor: CGPoint(x: 50, y: 60), current: CGPoint(x: 50, y: 60)))
        XCTAssertEqual(s.displayRect, CGRect(x: 50, y: 60, width: 0, height: 0))
    }

    // MARK: - Have-rect: mouse-down hit-tests handles vs body vs outside

    func test_mouseDown_fromHaveRect_outsideRect_startsFreshDrag() {
        let r = CGRect(x: 100, y: 100, width: 200, height: 100)
        var s = CropperState(initial: r)
        s = s.applyMouseDown(at: CGPoint(x: 0, y: 0), handleSize: handleSize)
        XCTAssertEqual(s.mode, .dragging(anchor: CGPoint(x: 0, y: 0), current: CGPoint(x: 0, y: 0)))
    }

    func test_mouseDown_fromHaveRect_onCornerHandle_startsResizing() {
        let r = CGRect(x: 100, y: 100, width: 200, height: 100)
        var s = CropperState(initial: r)
        s = s.applyMouseDown(at: CGPoint(x: 100, y: 100), handleSize: handleSize)
        XCTAssertEqual(
            s.mode,
            .resizing(
                handle: .topLeft,
                original: r,
                anchor: CGPoint(x: 100, y: 100),
                current: CGPoint(x: 100, y: 100)
            )
        )
    }

    func test_mouseDown_fromHaveRect_insideBody_startsBodyDrag() {
        let r = CGRect(x: 100, y: 100, width: 200, height: 100)
        var s = CropperState(initial: r)
        s = s.applyMouseDown(at: CGPoint(x: 200, y: 150), handleSize: handleSize)
        XCTAssertEqual(
            s.mode,
            .resizing(
                handle: .body,
                original: r,
                anchor: CGPoint(x: 200, y: 150),
                current: CGPoint(x: 200, y: 150)
            )
        )
    }

    // MARK: - Dragging: mouse-dragged updates displayRect, mouse-up commits

    func test_mouseDragged_fromDragging_updatesDisplayRect() {
        var s = CropperState(initial: nil)
        s = s.applyMouseDown(at: CGPoint(x: 50, y: 60), handleSize: handleSize)
        s = s.applyMouseDragged(at: CGPoint(x: 150, y: 120))
        XCTAssertEqual(s.displayRect, CGRect(x: 50, y: 60, width: 100, height: 60))
    }

    func test_mouseUp_fromDragging_commitsToHaveRect() {
        var s = CropperState(initial: nil)
        s = s.applyMouseDown(at: CGPoint(x: 50, y: 60), handleSize: handleSize)
        s = s.applyMouseDragged(at: CGPoint(x: 150, y: 120))
        s = s.applyMouseUp(at: CGPoint(x: 150, y: 120))
        XCTAssertEqual(s.mode, .have(CGRect(x: 50, y: 60, width: 100, height: 60)))
    }

    func test_mouseUp_fromDragging_zeroSizeRect_revertsToIdle() {
        // A click-without-drag should not commit a 0×0 rect.
        var s = CropperState(initial: nil)
        s = s.applyMouseDown(at: CGPoint(x: 50, y: 60), handleSize: handleSize)
        s = s.applyMouseUp(at: CGPoint(x: 50, y: 60))
        XCTAssertEqual(s.mode, .idle)
    }

    // MARK: - Resizing: mouse-dragged updates displayRect, mouse-up commits

    func test_mouseDragged_fromResizing_updatesDisplayRect() {
        let r = CGRect(x: 100, y: 100, width: 200, height: 100)
        var s = CropperState(initial: r)
        s = s.applyMouseDown(at: CGPoint(x: 300, y: 200), handleSize: handleSize) // bottom-right
        s = s.applyMouseDragged(at: CGPoint(x: 350, y: 230))
        XCTAssertEqual(s.displayRect, CGRect(x: 100, y: 100, width: 250, height: 130))
    }

    func test_mouseUp_fromResizing_commitsResizedRect() {
        let r = CGRect(x: 100, y: 100, width: 200, height: 100)
        var s = CropperState(initial: r)
        s = s.applyMouseDown(at: CGPoint(x: 300, y: 200), handleSize: handleSize)
        s = s.applyMouseDragged(at: CGPoint(x: 350, y: 230))
        s = s.applyMouseUp(at: CGPoint(x: 350, y: 230))
        XCTAssertEqual(s.mode, .have(CGRect(x: 100, y: 100, width: 250, height: 130)))
    }

    func test_mouseUp_fromResizing_body_commitsTranslatedRect() {
        let r = CGRect(x: 100, y: 100, width: 200, height: 100)
        var s = CropperState(initial: r)
        s = s.applyMouseDown(at: CGPoint(x: 200, y: 150), handleSize: handleSize)
        s = s.applyMouseDragged(at: CGPoint(x: 220, y: 180))
        s = s.applyMouseUp(at: CGPoint(x: 220, y: 180))
        XCTAssertEqual(s.mode, .have(CGRect(x: 120, y: 130, width: 200, height: 100)))
    }

    // MARK: - Stray events are no-ops

    func test_mouseDragged_fromIdle_isNoOp() {
        var s = CropperState(initial: nil)
        s = s.applyMouseDragged(at: CGPoint(x: 50, y: 60))
        XCTAssertEqual(s.mode, .idle)
    }

    func test_mouseUp_fromHaveRect_isNoOp() {
        let r = CGRect(x: 100, y: 100, width: 200, height: 100)
        var s = CropperState(initial: r)
        s = s.applyMouseUp(at: CGPoint(x: 200, y: 150))
        XCTAssertEqual(s.mode, .have(r))
    }

    // MARK: - Lossy click-outside regression

    func test_haveRect_clickOutsideWithoutDrag_revertsToIdle() {
        // Click outside an existing rect with no drag should discard the rect
        // (the click started a fresh drag that ended with zero extent → .idle).
        // Manual smoke covers this; this test pins the behavior so a future
        // refactor of applyMouseDown/Up can't regress it silently.
        let r = CGRect(x: 100, y: 100, width: 200, height: 100)
        var s = CropperState(initial: r)
        s = s.applyMouseDown(at: CGPoint(x: 0, y: 0), handleSize: handleSize)
        s = s.applyMouseUp(at: CGPoint(x: 0, y: 0))
        XCTAssertEqual(s.mode, .idle)
    }
}
