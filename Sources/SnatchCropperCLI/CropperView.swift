// Sources/SnatchCropperCLI/CropperView.swift
import AppKit
import SnatchKit

/// Renders the cropper overlay for a single screen. Owns a `CropperState`
/// (mutated by Task 11/12 mouse/key handlers), and draws the dim + rect +
/// handles + dimensions label every time the state changes.
final class CropperView: NSView {

    /// Click-target diameter of each resize handle, in points.
    static let handleSize: CGFloat = 12

    /// Mutated by the Task 11/12 event handlers. `didSet` triggers a redraw.
    var state: CropperState {
        didSet { needsDisplay = true }
    }

    init(frame: NSRect, initialRegion: CGRect?) {
        // `initialRegion` is supplied in view-local coords. The AppDelegate
        // (Task 12) does the screen-space → view-local translation by
        // subtracting `screen.frame.origin` before constructing the window.
        // For M3 we only support the primary display, where screen.frame
        // origin is (0, 0) and the conversion is a no-op — explicit
        // translation lives in AppDelegate so multi-display support (a
        // documented M5 carry-over) only requires touching the AppDelegate
        // seam, not the view.
        self.state = CropperState(initial: initialRegion)
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }

    /// Use a flipped coordinate system so y-down matches CG / spec §6 region
    /// semantics. Without this, the math in CropperGeometry would need a
    /// y-flip every time we crossed the AppKit boundary.
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // 1. Full-view dim, with the displayRect cut out.
        NSColor.black.withAlphaComponent(0.4).setFill()
        if let rect = state.displayRect {
            let path = NSBezierPath(rect: bounds)
            path.append(NSBezierPath(rect: rect).reversed)
            path.fill()
        } else {
            bounds.fill()
        }

        guard let rect = state.displayRect else { return }

        // 2. Rectangle outline.
        NSColor.white.setStroke()
        let outline = NSBezierPath(rect: rect)
        outline.lineWidth = 1
        outline.stroke()

        // 3. Resize handles (only when committed or while resizing — not
        //    during a fresh drag).
        if shouldShowHandles {
            NSColor.white.setFill()
            for (_, frame) in CropperGeometry.handleFrames(for: rect, handleSize: Self.handleSize) {
                NSBezierPath(rect: frame).fill()
            }
        }

        // 4. Dimensions label, rendered just outside the rect's top-left.
        let w = Int(rect.width.rounded())
        let h = Int(rect.height.rounded())
        let label = "\(w) × \(h)"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black.withAlphaComponent(0.6),
        ]
        let size = (label as NSString).size(withAttributes: attrs)
        let labelOrigin = CGPoint(
            x: rect.minX,
            y: max(0, rect.minY - size.height - 2)
        )
        (label as NSString).draw(at: labelOrigin, withAttributes: attrs)
    }

    // MARK: - Mouse handling

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        state = state.applyMouseDown(at: p, handleSize: Self.handleSize)
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        state = state.applyMouseDragged(at: p)
    }

    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        state = state.applyMouseUp(at: p)
    }

    private var shouldShowHandles: Bool {
        switch state.mode {
        case .have, .resizing: return true
        case .idle, .dragging: return false
        }
    }
}
