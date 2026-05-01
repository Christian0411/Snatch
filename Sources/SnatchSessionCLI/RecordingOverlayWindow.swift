// Sources/SnatchSessionCLI/RecordingOverlayWindow.swift
import AppKit

/// Transparent borderless overlay shown around the recording region during
/// `.recording`. Renders a thin red border around the rectangle; everything
/// inside the border is click-through so apps underneath stay usable.
/// Hosts the Stop button as the only hit-testable subview.
///
/// This window is added to `SCContentFilter`'s exclusion list so the overlay
/// itself never appears in the recorded GIF (per spec §6).
final class RecordingOverlayWindow: NSWindow {

    /// Called when the user clicks the Stop button.
    var onStop: (() -> Void)?

    private let overlayView: RecordingOverlayView

    /// Width of the red border stroke, in points.
    static let borderWidth: CGFloat = 2.5

    /// Margin between the rectangle and the Stop button (when button is outside).
    static let stopButtonMargin: CGFloat = 8

    /// `regionInScreenCoords` is the screen-space rectangle (CG coords, top-left
    /// origin) that the user selected via the cropper. The window's frame is
    /// inflated by 64 points on each side so the Stop button can land outside
    /// the rectangle when there's room.
    init(regionInScreenCoords region: CGRect) {
        let inset: CGFloat = 64
        let windowFrame = region.insetBy(dx: -inset, dy: -inset)

        // Convert from CG coords (top-left origin) to AppKit coords (bottom-left
        // origin) for the NSWindow init.
        // NSScreen.screens.first is the PRIMARY display (the one with the
        // menu bar). Its origin is also the AppKit coordinate-system origin,
        // so its height is the right divisor for CG → AppKit y-flip.
        // M5 multi-display: pick the screen containing `region`.
        let screenHeight = NSScreen.screens.first?.frame.height ?? 0
        let appKitFrame = NSRect(
            x: windowFrame.origin.x,
            y: screenHeight - windowFrame.maxY,
            width: windowFrame.width,
            height: windowFrame.height
        )

        // Region inside the window's local (view) coordinate space, with the
        // 64-point inset accounted for. We pass the view-local rect to the
        // content view so it can draw and lay out without re-doing the conversion.
        let regionInViewCoords = CGRect(
            x: inset,
            y: inset,
            width: region.width,
            height: region.height
        )

        self.overlayView = RecordingOverlayView(
            frame: NSRect(origin: .zero, size: appKitFrame.size),
            regionInViewCoords: regionInViewCoords
        )

        super.init(
            contentRect: appKitFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.level = .screenSaver
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // Allow mouse events on the Stop button; the content view's hitTest
        // returns nil elsewhere to pass clicks through.
        self.ignoresMouseEvents = false

        self.contentView = overlayView
        overlayView.onStop = { [weak self] in
            self?.onStop?()
        }
    }

    // Borderless windows default to canBecomeKey=false. We intentionally do NOT
    // override here — the overlay should not steal focus from underlying apps.
    // The Stop button is hit-tested without needing key status.
}

/// Content view of `RecordingOverlayWindow`. Draws the thin red border around
/// `regionInViewCoords` and hosts the Stop button. Returns nil from hitTest
/// for non-button regions so clicks pass through.
private final class RecordingOverlayView: NSView {

    var onStop: (() -> Void)?
    private let regionInViewCoords: CGRect
    private let stopButton: RecordingStopButton

    init(frame: NSRect, regionInViewCoords: CGRect) {
        self.regionInViewCoords = regionInViewCoords
        self.stopButton = RecordingStopButton(
            frame: NSRect(origin: .zero, size: RecordingStopButton.preferredSize)
        )
        super.init(frame: frame)
        stopButton.target = self
        stopButton.action = #selector(stopClicked(_:))
        addSubview(stopButton)
        layoutStopButton()
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }

    /// Flipped so y-down matches CG coords; consistent with CropperView (M3).
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // Draw the thin red border centered on the rectangle's edge.
        NSColor.systemRed.setStroke()
        let stroked = regionInViewCoords.insetBy(
            dx: RecordingOverlayWindow.borderWidth / 2,
            dy: RecordingOverlayWindow.borderWidth / 2
        )
        let path = NSBezierPath(rect: stroked)
        path.lineWidth = RecordingOverlayWindow.borderWidth
        path.stroke()
    }

    /// Pass clicks through everywhere except the Stop button.
    /// `point` is already in our local coordinate space — we are the window's
    /// content view, so AppKit calls hitTest with point in our own coords.
    override func hitTest(_ point: NSPoint) -> NSView? {
        if stopButton.frame.contains(point) {
            return stopButton
        }
        return nil
    }

    @objc private func stopClicked(_ sender: Any?) {
        onStop?()
    }

    override func layout() {
        super.layout()
        layoutStopButton()
    }

    private func layoutStopButton() {
        let btnSize = RecordingStopButton.preferredSize
        let margin = RecordingOverlayWindow.stopButtonMargin

        // Default placement: just below the rectangle's bottom-right corner,
        // outside the red border (so it doesn't compete visually with the rect).
        var x = regionInViewCoords.maxX - btnSize.width
        var y = regionInViewCoords.maxY + margin

        // Fall back inside the rectangle's bottom-right if outside-placement
        // would clip off the bottom of the window (rectangle hugs screen edge).
        if y + btnSize.height > bounds.height {
            y = regionInViewCoords.maxY - btnSize.height - margin
        }

        // Clamp x so the button doesn't fall off the left/right edge of the window.
        x = max(0, min(x, bounds.width - btnSize.width))

        stopButton.frame = NSRect(x: x, y: y, width: btnSize.width, height: btnSize.height)
    }
}
