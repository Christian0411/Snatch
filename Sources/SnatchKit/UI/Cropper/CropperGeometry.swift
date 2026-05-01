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

    // MARK: - Handle frames

    /// Frame (origin + size) of each resize handle on `rect`, keyed by the
    /// handle case. Each handle is `handleSize × handleSize` and centered on
    /// the corresponding corner / edge midpoint of `rect`. The `.body` case
    /// has no rendered handle and is intentionally absent from the result.
    public static func handleFrames(
        for rect: CGRect,
        handleSize: CGFloat
    ) -> [CropperHandle: CGRect] {
        let half = handleSize / 2
        let cx = rect.midX
        let cy = rect.midY

        func frame(centeredAt p: CGPoint) -> CGRect {
            CGRect(x: p.x - half, y: p.y - half, width: handleSize, height: handleSize)
        }

        return [
            .topLeft:     frame(centeredAt: CGPoint(x: rect.minX, y: rect.minY)),
            .top:         frame(centeredAt: CGPoint(x: cx,        y: rect.minY)),
            .topRight:    frame(centeredAt: CGPoint(x: rect.maxX, y: rect.minY)),
            .left:        frame(centeredAt: CGPoint(x: rect.minX, y: cy)),
            .right:       frame(centeredAt: CGPoint(x: rect.maxX, y: cy)),
            .bottomLeft:  frame(centeredAt: CGPoint(x: rect.minX, y: rect.maxY)),
            .bottom:      frame(centeredAt: CGPoint(x: cx,        y: rect.maxY)),
            .bottomRight: frame(centeredAt: CGPoint(x: rect.maxX, y: rect.maxY)),
        ]
    }

    // MARK: - Hit-testing

    /// Decide which handle (if any) `point` lands on for a rectangle `rect`
    /// drawn with `handleSize`-pt grips. Resolution order:
    ///   1. The 8 resize-handle frames take precedence (more specific intent).
    ///   2. The rectangle interior maps to `.body` (whole-rect drag).
    ///   3. Anywhere else returns `nil` (fresh drag, replaces the rect).
    public static func hitTest(
        point: CGPoint,
        in rect: CGRect,
        handleSize: CGFloat
    ) -> CropperHandle? {
        let frames = handleFrames(for: rect, handleSize: handleSize)
        for handle in CropperHandle.resizeCases {
            if let f = frames[handle], f.contains(point) {
                return handle
            }
        }
        if rect.contains(point) {
            return .body
        }
        return nil
    }
}
