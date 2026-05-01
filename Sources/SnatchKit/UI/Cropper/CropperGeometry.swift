import Foundation
import CoreGraphics

/// Pure geometric helpers for the cropper UI. None of these touch AppKit;
/// they exist to keep the rect/handle math testable under `swift test` and
/// independent from the `NSView` that consumes them.
public enum CropperGeometry {

    // MARK: - Drag-to-create

    /// Build a normalized (positive-extent) `CGRect` from an arbitrary pair
    /// of corner points. Either point can be the anchor; the rect is the
    /// minimum bounding box that contains both.
    public static func rect(from anchor: CGPoint, to current: CGPoint) -> CGRect {
        let x = min(anchor.x, current.x)
        let y = min(anchor.y, current.y)
        let w = abs(current.x - anchor.x)
        let h = abs(current.y - anchor.y)
        return CGRect(x: x, y: y, width: w, height: h)
    }
}
