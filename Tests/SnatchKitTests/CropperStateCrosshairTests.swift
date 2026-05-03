import XCTest
@testable import SnatchKit

final class CropperStateCrosshairTests: XCTestCase {

    private let handleSize: CGFloat = 12

    // MARK: - mode == .idle

    func test_idle_alwaysShows_whenCursorPresent() {
        let s = CropperState(initial: nil)
        XCTAssertTrue(s.shouldShowCrosshair(cursor: CGPoint(x: 50, y: 50), handleSize: handleSize))
    }

    func test_idle_doesNotShow_whenCursorIsNil() {
        let s = CropperState(initial: nil)
        XCTAssertFalse(s.shouldShowCrosshair(cursor: nil, handleSize: handleSize))
    }

    // MARK: - mode == .have(rect)

    func test_have_outsideRect_shows() {
        let rect = CGRect(x: 100, y: 100, width: 200, height: 100)
        let s = CropperState(initial: rect)
        // Cursor far outside the rect's bounds.
        XCTAssertTrue(s.shouldShowCrosshair(cursor: CGPoint(x: 50, y: 50), handleSize: handleSize))
    }

    func test_have_insideRect_doesNotShow() {
        let rect = CGRect(x: 100, y: 100, width: 200, height: 100)
        let s = CropperState(initial: rect)
        // Center of rect — interior, not on any handle.
        XCTAssertFalse(s.shouldShowCrosshair(cursor: CGPoint(x: 200, y: 150), handleSize: handleSize))
    }

    func test_have_overHandle_doesNotShow() {
        let rect = CGRect(x: 100, y: 100, width: 200, height: 100)
        let s = CropperState(initial: rect)
        // Cursor at the topLeft handle's center (which is at rect.minX, rect.minY = (100, 100)).
        let frames = CropperGeometry.handleFrames(for: rect, handleSize: handleSize)
        let topLeftCenter = CGPoint(x: frames[.topLeft]!.midX, y: frames[.topLeft]!.midY)
        XCTAssertFalse(s.shouldShowCrosshair(cursor: topLeftCenter, handleSize: handleSize))
    }

    // MARK: - mode == .dragging / .resizing
    //
    // These modes are not constructable from public init, so we drive them
    // through the public mouse transitions to set up the right state.

    func test_dragging_alwaysShows() {
        // Start idle, mouseDown at (10,10) → state goes to .dragging(anchor:current:).
        var s = CropperState(initial: nil)
        s = s.applyMouseDown(at: CGPoint(x: 10, y: 10), handleSize: handleSize)
        // Predicate should report true regardless of where the cursor currently is.
        XCTAssertTrue(s.shouldShowCrosshair(cursor: CGPoint(x: 10, y: 10), handleSize: handleSize))
        XCTAssertTrue(s.shouldShowCrosshair(cursor: CGPoint(x: 999, y: 999), handleSize: handleSize))
    }

    func test_resizing_neverShows() {
        // Start with a committed rect; mouseDown on a handle drives state into .resizing.
        let rect = CGRect(x: 100, y: 100, width: 200, height: 100)
        let frames = CropperGeometry.handleFrames(for: rect, handleSize: handleSize)
        let bottomRight = CGPoint(x: frames[.bottomRight]!.midX, y: frames[.bottomRight]!.midY)

        var s = CropperState(initial: rect)
        s = s.applyMouseDown(at: bottomRight, handleSize: handleSize)
        // Predicate should report false regardless of where the cursor currently is.
        XCTAssertFalse(s.shouldShowCrosshair(cursor: bottomRight, handleSize: handleSize))
        XCTAssertFalse(s.shouldShowCrosshair(cursor: CGPoint(x: 50, y: 50), handleSize: handleSize))
    }
}
