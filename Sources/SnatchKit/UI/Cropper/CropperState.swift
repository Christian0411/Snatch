import Foundation
import CoreGraphics

/// The cursor the cropper should show, given the current `CropperState.mode`,
/// the cursor's location, and whether it's over the floating Record button.
/// Computed by `CropperState.desiredCursor(...)`. The AppKit-side
/// `CropperView` maps each case to a concrete `NSCursor`.
public enum CropperCursor: Equatable, Sendable {
    case crosshair
    case arrow
    case resizeNWSE
    case resizeNESW
    case resizeVertical
    case resizeHorizontal
    case grab
    case grabbing
}

/// Drag/resize state for the cropper view, expressed as a value type so it
/// can be unit-tested in isolation from AppKit. The view owns one instance,
/// rebinds it on each mouse / key event, and reads `displayRect` to drive
/// drawing.
///
/// The four modes:
/// - `.idle`         — no rectangle yet; any mouse-down starts a fresh drag.
/// - `.have(rect)`   — committed rectangle; mouse-down hit-tests handles.
/// - `.dragging(…)`  — user is drawing a fresh rect from scratch.
/// - `.resizing(…)`  — user is resizing or moving an existing rect.
public struct CropperState: Equatable, Sendable {

    public enum Mode: Equatable, Sendable {
        case idle
        case have(CGRect)
        case dragging(anchor: CGPoint, current: CGPoint)
        case resizing(handle: CropperHandle, original: CGRect, anchor: CGPoint, current: CGPoint)
    }

    public private(set) var mode: Mode

    /// Initial state. `initial` is the persisted region from `RegionStore`,
    /// or nil on first launch.
    public init(initial: CGRect?) {
        if let r = initial {
            self.mode = .have(r)
        } else {
            self.mode = .idle
        }
    }

    /// The rectangle the view should draw right now. Nil while `.idle`.
    public var displayRect: CGRect? {
        switch mode {
        case .idle:
            return nil
        case .have(let r):
            return r
        case .dragging(let anchor, let current):
            return CropperGeometry.rect(from: anchor, to: current)
        case .resizing(let handle, let original, let anchor, let current):
            let delta = CGSize(width: current.x - anchor.x, height: current.y - anchor.y)
            return CropperGeometry.resize(original, handle: handle, dragDelta: delta)
        }
    }

    /// The committed rectangle, if any (i.e., when not mid-drag).
    public var committedRect: CGRect? {
        if case .have(let r) = mode { return r }
        return nil
    }

    // MARK: - Crosshair visibility

    /// Convenience wrapper around `desiredCursor(...)` that returns `true`
    /// only when the cursor should be the white "+" crosshair (i.e. when a
    /// click would start a fresh drag, or the user is currently drawing
    /// one). Canonical cursor logic lives in `desiredCursor` —
    /// `shouldShowCrosshair` is retained for callers that only care about
    /// the binary "is this a crosshair situation?" question.
    ///
    /// - `cursor` is in view-local coordinates (top-left origin, since the
    ///   cropper view is flipped). Pass `nil` to indicate "the cursor is
    ///   outside the cropper view" (e.g. the user moved to another display).
    /// - `handleSize` is the same `CGFloat` constant the view uses for hit
    ///   testing (currently `CropperView.handleSize = 12`).
    public func shouldShowCrosshair(cursor: CGPoint?, handleSize: CGFloat) -> Bool {
        desiredCursor(at: cursor, handleSize: handleSize, isOverRecordButton: false) == .crosshair
    }

    // MARK: - Cursor affordance

    /// The cursor the view should display right now, given the current mode,
    /// the cursor's view-local position, and whether the cursor is over the
    /// floating Record button. Pure: no AppKit dependency.
    ///
    /// - `cursor` is in view-local coordinates (top-left origin, since the
    ///   cropper view is flipped). Pass `nil` to indicate "the cursor is
    ///   outside the cropper view."
    /// - `handleSize` is the same `CGFloat` constant the view uses for hit
    ///   testing (currently `CropperView.handleSize = 12`).
    /// - `isOverRecordButton` short-circuits to `.arrow` when true, regardless
    ///   of mode or location. The Record button is owned by the view, so the
    ///   hit-test is performed there and passed in here.
    public func desiredCursor(
        at cursor: CGPoint?,
        handleSize: CGFloat,
        isOverRecordButton: Bool
    ) -> CropperCursor {
        if isOverRecordButton { return .arrow }
        guard let p = cursor else { return .arrow }
        switch mode {
        case .idle, .dragging:
            return .crosshair
        case .resizing(let handle, _, _, _):
            return Self.cursorFor(handle: handle, gestureActive: true)
        case .have(let r):
            guard let h = CropperGeometry.hitTest(point: p, in: r, handleSize: handleSize) else {
                return .crosshair
            }
            return Self.cursorFor(handle: h, gestureActive: false)
        }
    }

    /// Maps a hit-tested handle to its directional cursor. `gestureActive`
    /// distinguishes hover (`.body` → `.grab`) from an in-progress body-move
    /// (`.body` → `.grabbing`); for the 8 resize handles the result is the
    /// same in both cases.
    private static func cursorFor(handle: CropperHandle, gestureActive: Bool) -> CropperCursor {
        switch handle {
        case .topLeft, .bottomRight: return .resizeNWSE
        case .topRight, .bottomLeft: return .resizeNESW
        case .top, .bottom:          return .resizeVertical
        case .left, .right:          return .resizeHorizontal
        case .body:                  return gestureActive ? .grabbing : .grab
        }
    }

    // MARK: - Transitions

    public func applyMouseDown(at point: CGPoint, handleSize: CGFloat) -> CropperState {
        switch mode {
        case .idle:
            return Self(mode: .dragging(anchor: point, current: point))
        case .have(let r):
            if let h = CropperGeometry.hitTest(point: point, in: r, handleSize: handleSize) {
                return Self(mode: .resizing(handle: h, original: r, anchor: point, current: point))
            } else {
                return Self(mode: .dragging(anchor: point, current: point))
            }
        case .dragging, .resizing:
            return self // already mid-gesture; ignore stray downs
        }
    }

    public func applyMouseDragged(at point: CGPoint) -> CropperState {
        switch mode {
        case .dragging(let anchor, _):
            return Self(mode: .dragging(anchor: anchor, current: point))
        case .resizing(let h, let original, let anchor, _):
            return Self(mode: .resizing(handle: h, original: original, anchor: anchor, current: point))
        case .idle, .have:
            return self // no gesture in progress
        }
    }

    public func applyMouseUp(at point: CGPoint) -> CropperState {
        switch mode {
        case .dragging(let anchor, _):
            let r = CropperGeometry.rect(from: anchor, to: point)
            // Reject zero-size commits so a click-without-drag doesn't
            // produce a degenerate region.
            if r.width == 0 && r.height == 0 {
                return Self(mode: .idle)
            }
            return Self(mode: .have(r))
        case .resizing(let h, let original, let anchor, _):
            let delta = CGSize(width: point.x - anchor.x, height: point.y - anchor.y)
            let r = CropperGeometry.resize(original, handle: h, dragDelta: delta)
            return Self(mode: .have(r))
        case .idle, .have:
            return self
        }
    }

    // MARK: - Private

    private init(mode: Mode) {
        self.mode = mode
    }
}
