// Sources/SnatchAppKit/CropperView.swift
import AppKit
import SnatchKit

/// Renders the cropper overlay for a single screen. Owns a `CropperState`
/// (mutated by Task 11/12 mouse/key handlers), and draws the dim + rect +
/// handles + dimensions label every time the state changes.
public final class CropperView: NSView {

    /// Click-target diameter of each resize handle, in points.
    public static let handleSize: CGFloat = 12

    /// Called when the user confirms the region (Record button, Space, or Return).
    public var onRecord: ((CGRect) -> Void)?

    /// Called when the user cancels (Esc).
    public var onCancel: (() -> Void)?

    /// Floating Record button shown in .have mode, positioned near the rect.
    private let recordButton = CropperRecordButton(
        frame: NSRect(origin: .zero, size: CropperRecordButton.preferredSize)
    )

    /// Mutated by the Task 11/12 event handlers. `didSet` triggers a redraw.
    public var state: CropperState {
        didSet {
            needsDisplay = true
            needsLayout = true
        }
    }

    public init(frame: NSRect, initialRegion: CGRect?) {
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
        recordButton.target = self
        recordButton.action = #selector(recordButtonClicked(_:))
        recordButton.isHidden = true
        addSubview(recordButton)
    }

    public required init?(coder: NSCoder) { fatalError("not implemented") }

    /// Use a flipped coordinate system so y-down matches CG / spec §6 region
    /// semantics. Without this, the math in CropperGeometry would need a
    /// y-flip every time we crossed the AppKit boundary.
    public override var isFlipped: Bool { true }

    public override func draw(_ dirtyRect: NSRect) {
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

        // 2. Rectangle outline (dashed — matches macOS native screenshot tool).
        NSColor.white.setStroke()
        let outline = NSBezierPath(rect: rect)
        outline.lineWidth = 1
        outline.setLineDash([6, 4], count: 2, phase: 0)
        outline.stroke()

        // 3. Resize handles (only when committed or while resizing — not
        //    during a fresh drag). Drawn as small white circles with a thin
        //    grey rim — matches macOS native screenshot tool. Click target
        //    stays at `Self.handleSize` (12pt); the visible oval is inset
        //    by 2pt on each side, giving an 8pt circle centered in the
        //    12pt hit zone.
        if shouldShowHandles {
            for (_, frame) in CropperGeometry.handleFrames(for: rect, handleSize: Self.handleSize) {
                let visible = frame.insetBy(dx: 2, dy: 2)
                let oval = NSBezierPath(ovalIn: visible)
                NSColor.white.setFill()
                oval.fill()
                NSColor.systemGray.setStroke()
                oval.lineWidth = 1
                oval.stroke()
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

    public override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        state = state.applyMouseDown(at: p, handleSize: Self.handleSize)
    }

    public override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        state = state.applyMouseDragged(at: p)
    }

    public override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        state = state.applyMouseUp(at: p)
    }

    private var shouldShowHandles: Bool {
        switch state.mode {
        case .have, .resizing: return true
        case .idle, .dragging: return false
        }
    }

    // MARK: - First-responder + keys

    public override var acceptsFirstResponder: Bool { true }

    public override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // Esc
            onCancel?()
        case 49, 36, 76: // Space (49), Return (36), Enter (76 — keypad)
            if let rect = state.committedRect {
                onRecord?(rect)
            }
            // No-op while .idle / .dragging / .resizing — the user has not
            // settled on a rectangle yet.
        default:
            super.keyDown(with: event)
        }
    }

    // MARK: - Record button

    @objc private func recordButtonClicked(_ sender: Any?) {
        if let rect = state.committedRect {
            onRecord?(rect)
        }
    }

    public override func layout() {
        super.layout()
        layoutRecordButton()
    }

    private func layoutRecordButton() {
        guard case .have(let rect) = state.mode else {
            recordButton.isHidden = true
            return
        }
        recordButton.isHidden = false
        let btnSize = CropperRecordButton.preferredSize
        // Placement: just below the rectangle's bottom-right, tucked back
        // inside the screen if the rect is near the bottom edge.
        var x = rect.maxX - btnSize.width
        var y = rect.maxY + 8
        if y + btnSize.height > bounds.height {
            // Fall back to inside the rect at the bottom-right.
            y = rect.maxY - btnSize.height - 8
        }
        x = max(0, min(x, bounds.width - btnSize.width))
        recordButton.frame = NSRect(x: x, y: y, width: btnSize.width, height: btnSize.height)
    }
}
