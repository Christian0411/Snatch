import Foundation
import CoreGraphics

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

    /// Should the cropper show a crosshair cursor + coordinate readout right
    /// now? The predicate captures "a click would start a fresh drag, OR the
    /// user is currently drawing one." See pre-M6 tweaks spec, Item 1.
    ///
    /// - `cursor` is in view-local coordinates (top-left origin, since the
    ///   cropper view is flipped). Pass `nil` to indicate "the cursor is
    ///   outside the cropper view" (e.g. the user moved to another display).
    /// - `handleSize` is the same `CGFloat` constant the view uses for hit
    ///   testing (currently `CropperView.handleSize = 12`).
    public func shouldShowCrosshair(cursor: CGPoint?, handleSize: CGFloat) -> Bool {
        guard let cursor else { return false }
        switch mode {
        case .idle:      return true
        case .dragging:  return true
        case .resizing:  return false
        case .have(let r):
            if CropperGeometry.hitTest(point: cursor, in: r, handleSize: handleSize) != nil {
                return false
            }
            return !r.contains(cursor)
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
