// Sources/SnatchAppKit/CropperView.swift
import AppKit
import SnatchKit

/// Renders the cropper overlay for a single screen. Owns a `CropperState`
/// (mutated by Task 11/12 mouse/key handlers), and draws the dim + rect +
/// handles + dimensions label every time the state changes.
public final class CropperView: NSView {

    /// Click-target diameter of each resize handle, in points.
    public static let handleSize: CGFloat = 12

    /// When `true`, `mouseUp` that commits a fresh `.have(rect)` will fire
    /// `onRecord(rect)` directly — same callback path as the Record button /
    /// Space / Return. Set by `MenubarCoordinator.showCropper()` based on
    /// `RememberRegionPreferenceStore` + `AutoStartRecordingPreferenceStore`.
    public var autoStartOnCommit: Bool = false

    /// Most recent mouse position in view-local (flipped, top-left origin)
    /// coordinates. Tracked via a full-view `NSTrackingArea`; cleared on
    /// `mouseExited` so the readout disappears when the cursor leaves the
    /// cropper (e.g. crosses to another display).
    private var mouseLocation: CGPoint?

    /// Programmatic 16×16 crosshair cursor, drawn as two 1pt white lines
    /// centered at (8, 8). Shared across all cropper instances; lazily built
    /// once.
    private static let crosshairCursor: NSCursor = {
        let size = NSSize(width: 16, height: 16)
        let img = NSImage(size: size, flipped: false) { _ in
            NSColor.white.setStroke()
            let p = NSBezierPath()
            p.move(to: NSPoint(x: 8, y: 0))
            p.line(to: NSPoint(x: 8, y: 16))
            p.move(to: NSPoint(x: 0, y: 8))
            p.line(to: NSPoint(x: 16, y: 8))
            p.lineWidth = 1
            p.stroke()
            return true
        }
        return NSCursor(image: img, hotSpot: NSPoint(x: 8, y: 8))
    }()

    /// One full-view tracking area, rebuilt on every `updateTrackingAreas`
    /// (covers cropper window resize when the user moves across displays).
    private var trackingArea: NSTrackingArea?

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

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .cursorUpdate, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // AppKit calls updateTrackingAreas() only when geometry changes. If the
        // view's frame is set at init and never changes (cropper is sized to fill
        // the screen), we'd never get a tracking area otherwise.
        if window != nil {
            updateTrackingAreas()
        }
    }

    /// Seed `mouseLocation` from the current global cursor position so the
    /// crosshair / x-y readout appear before the first `mouseMoved` event.
    /// Called by `CropperWindow.becomeKey()` when the cropper is shown — at
    /// that moment the user has just hit ⇧⌘6 and `mouseMoved` won't fire
    /// until they nudge the cursor.
    public func warmMouseLocation() {
        guard let win = window else { return }
        let screenPoint = NSEvent.mouseLocation
        let windowPoint = win.convertPoint(fromScreen: screenPoint)
        let viewPoint = convert(windowPoint, from: nil)
        if bounds.contains(viewPoint) {
            mouseLocation = viewPoint
            needsDisplay = true
            updateCursor()
        }
    }

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

        // Steps 2–4 only apply when there is a rect to draw. Step 5 (the
        // crosshair x/y readout) is independent and applies in .idle and
        // .dragging too — it's drawn after this block.
        if let rect = state.displayRect {

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

        // 5. Crosshair x/y readout (pre-M6 tweaks Item 1). Shown alongside the
        //    custom NSCursor when `shouldShowCrosshair` is true. Numbers are
        //    in CG screen-space (top-left global origin) — matches what the
        //    macOS native screenshot tool shows. Multi-display correctness
        //    relies on the cropper window's frame.origin matching the chosen
        //    screen's frame.origin (M5 single-screen-under-cursor behavior).
        //    NOTE: this runs in every mode (.idle / .dragging / .resizing /
        //    .have) — the predicate gates which modes actually render.
        if let cursor = mouseLocation,
           !cursorIsOverRecordButton,
           state.shouldShowCrosshair(cursor: cursor, handleSize: Self.handleSize),
           let window = window,
           let mainScreen = NSScreen.main {

            // View-local (flipped, top-left) → CG screen-space (top-left global).
            let mainHeight = mainScreen.frame.height
            let cgY_screenTop = mainHeight - (window.frame.origin.y + window.frame.height)
            let cgX = Int((window.frame.origin.x + cursor.x).rounded())
            let cgY = Int((cgY_screenTop + cursor.y).rounded())

            let xStr = "\(cgX)"
            let yStr = "\(cgY)"

            let textAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.white,
            ]

            let xSize = (xStr as NSString).size(withAttributes: textAttrs)
            let ySize = (yStr as NSString).size(withAttributes: textAttrs)
            let textW = max(xSize.width, ySize.width)
            let textH = xSize.height + ySize.height
            let pad: CGFloat = 4
            let pillW = textW + pad * 2
            let pillH = textH + pad * 2

            // Default placement: bottom-right of cursor, 12pt offset.
            var pillX = cursor.x + 12
            var pillY = cursor.y + 12
            // Edge-flip: keep the pill inside the view bounds.
            if pillX + pillW > bounds.width {
                pillX = cursor.x - 12 - pillW
            }
            if pillY + pillH > bounds.height {
                pillY = cursor.y - 12 - pillH
            }

            let pillRect = CGRect(x: pillX, y: pillY, width: pillW, height: pillH)
            NSColor.black.withAlphaComponent(0.7).setFill()
            NSBezierPath(roundedRect: pillRect, xRadius: 6, yRadius: 6).fill()

            // Numbers stacked, left-aligned inside the pill.
            (xStr as NSString).draw(
                at: CGPoint(x: pillX + pad, y: pillY + pad),
                withAttributes: textAttrs
            )
            (yStr as NSString).draw(
                at: CGPoint(x: pillX + pad, y: pillY + pad + xSize.height),
                withAttributes: textAttrs
            )
        }
    }

    // MARK: - Mouse handling

    public override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        mouseLocation = p
        state = state.applyMouseDown(at: p, handleSize: Self.handleSize)
        updateCursor()
    }

    public override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        mouseLocation = p
        state = state.applyMouseDragged(at: p)
        updateCursor()
    }

    public override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        mouseLocation = p
        // Capture before applyMouseUp transitions us into .have. Auto-fire
        // should only happen on a fresh-drag commit, not on resize-end —
        // both paths land in .have(rect), but only .dragging → .have means
        // "the user just defined a new region."
        let wasDragging: Bool = if case .dragging = state.mode { true } else { false }
        state = state.applyMouseUp(at: p)
        updateCursor()
        if autoStartOnCommit, wasDragging, case .have(let rect) = state.mode {
            onRecord?(rect)
        }
    }

    public override func mouseMoved(with event: NSEvent) {
        mouseLocation = convert(event.locationInWindow, from: nil)
        needsDisplay = true
        updateCursor()
    }

    public override func mouseExited(with event: NSEvent) {
        mouseLocation = nil
        needsDisplay = true
    }

    public override func cursorUpdate(with event: NSEvent) {
        updateCursor()
    }

    /// Swap the system cursor based on the current state + `mouseLocation`.
    /// Called from `cursorUpdate(with:)` AND from every mouse-event override
    /// that updates `mouseLocation` — AppKit does not invoke `cursorUpdate`
    /// on every `mouseMoved`, so we drive the swap manually as the cursor
    /// traverses the static tracking area.
    private func updateCursor() {
        if cursorIsOverRecordButton {
            NSCursor.arrow.set()
            return
        }
        if state.shouldShowCrosshair(cursor: mouseLocation, handleSize: Self.handleSize) {
            Self.crosshairCursor.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    /// True when the Record button is visible and the current `mouseLocation`
    /// is inside its frame. Used to suppress the crosshair cursor + x/y pill
    /// over the button — the predicate alone would say "outside rect → show
    /// crosshair," which is wrong when the user is reaching for Record.
    private var cursorIsOverRecordButton: Bool {
        guard !recordButton.isHidden, let cursor = mouseLocation else { return false }
        return recordButton.frame.contains(cursor)
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
