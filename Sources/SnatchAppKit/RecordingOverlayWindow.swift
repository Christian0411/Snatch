// Sources/SnatchAppKit/RecordingOverlayWindow.swift
import AppKit

/// Wraps the two NSWindows that make up the recording feedback UI:
///
///   1. A click-through, borderless transparent window that covers the
///      recording region and renders a thin red border around its edge.
///      `ignoresMouseEvents = true` so the user can interact with the
///      apps being recorded.
///
///   2. A small, regular borderless window that hosts the Stop button.
///      Positioned outside the rectangle (or inside if the rect hugs an
///      edge). Receives mouse events normally so the button is clickable.
///
/// Both windows live at `.screenSaver` level and are added to
/// `SCContentFilter`'s exclusion list so they don't appear in the GIF.
///
/// Naming note: the type is named `RecordingOverlayWindow` for backwards
/// compatibility with AppDelegate's existing references, but it is no longer
/// an `NSWindow` subclass — it's a coordinator that owns both windows.
public final class RecordingOverlayWindow {

    /// Called when the user clicks the Stop button.
    public var onStop: (() -> Void)?

    /// The thin-red-border window covering the region. Click-through.
    private let borderWindow: BorderOverlayWindow

    /// The small clickable window hosting the Stop button. Not click-through.
    private let stopWindow: StopButtonOverlayWindow

    /// SCWindow exclusion list needs windowNumbers for BOTH overlays so
    /// neither leaks into the GIF.
    public var windowNumbers: [Int] {
        [borderWindow.windowNumber, stopWindow.windowNumber]
    }

    /// Width of the red border stroke, in points.
    public static let borderWidth: CGFloat = 2.5

    /// Margin between the rectangle and the Stop button (when button is outside).
    public static let stopButtonMargin: CGFloat = 8

    /// `regionInScreenCoords` is the screen-space rectangle (CG coords, top-left
    /// origin) that the user selected via the cropper.
    public init(regionInScreenCoords region: CGRect) {
        self.borderWindow = BorderOverlayWindow(regionInScreenCoords: region)
        self.stopWindow = StopButtonOverlayWindow(regionInScreenCoords: region)
        self.stopWindow.onStop = { [weak self] in
            self?.onStop?()
        }
    }

    /// Show both windows.
    public func orderFrontRegardless() {
        borderWindow.orderFrontRegardless()
        stopWindow.orderFrontRegardless()
    }

    /// Hide both windows.
    public func orderOut(_ sender: Any?) {
        borderWindow.orderOut(sender)
        stopWindow.orderOut(sender)
    }
}

// MARK: - Border (click-through)

/// Borderless transparent NSWindow that renders the thin red border.
/// `ignoresMouseEvents = true` so clicks pass through to whatever's below.
private final class BorderOverlayWindow: NSWindow {

    init(regionInScreenCoords region: CGRect) {
        // Inflate by enough to give the stroke breathing room. Border width is
        // 2.5pt; we add a few extra so the stroke isn't clipped at window edges.
        let inset: CGFloat = 8
        let windowFrame = region.insetBy(dx: -inset, dy: -inset)

        // CG coords (top-left origin) → AppKit coords (bottom-left origin).
        let screenHeight = NSScreen.screens.first?.frame.height ?? 0
        let appKitFrame = NSRect(
            x: windowFrame.origin.x,
            y: screenHeight - windowFrame.maxY,
            width: windowFrame.width,
            height: windowFrame.height
        )

        let regionInViewCoords = CGRect(
            x: inset,
            y: inset,
            width: region.width,
            height: region.height
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
        // CRITICAL: this is what makes the body click-through. AppKit consumes
        // mouse events at the window level, not the view level — view.hitTest
        // returning nil is NOT enough.
        self.ignoresMouseEvents = true

        let view = BorderOverlayView(
            frame: NSRect(origin: .zero, size: appKitFrame.size),
            regionInViewCoords: regionInViewCoords
        )
        self.contentView = view
    }
}

private final class BorderOverlayView: NSView {

    private let regionInViewCoords: CGRect

    init(frame: NSRect, regionInViewCoords: CGRect) {
        self.regionInViewCoords = regionInViewCoords
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }

    /// Flipped so y-down matches CG / cropper convention.
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.systemRed.setStroke()
        let stroked = regionInViewCoords.insetBy(
            dx: RecordingOverlayWindow.borderWidth / 2,
            dy: RecordingOverlayWindow.borderWidth / 2
        )
        let path = NSBezierPath(rect: stroked)
        path.lineWidth = RecordingOverlayWindow.borderWidth
        path.stroke()
    }
}

// MARK: - Stop button (clickable)

/// Small borderless window hosting the Stop button. Sized just large enough
/// for the button + padding. `ignoresMouseEvents = false` so the button is
/// clickable; window position is chosen so it doesn't overlap the captured
/// region (or, when no room outside, it sits at the bottom-right inside).
private final class StopButtonOverlayWindow: NSWindow {

    var onStop: (() -> Void)?

    private let stopButton: RecordingStopButton

    init(regionInScreenCoords region: CGRect) {
        let btnSize = RecordingStopButton.preferredSize
        let padding: CGFloat = 6  // small breathing room around the button
        let winSize = CGSize(
            width: btnSize.width + 2 * padding,
            height: btnSize.height + 2 * padding
        )

        // Default placement: just below the rectangle's bottom-right corner.
        // CG coords (top-left origin) at this point.
        let margin = RecordingOverlayWindow.stopButtonMargin
        var cgX = region.maxX - btnSize.width - padding
        var cgY = region.maxY + margin

        // Find the screen so we know the bottom of usable space.
        let screen = NSScreen.screens.first
        let screenHeight = screen?.frame.height ?? 0
        let screenWidth = screen?.frame.width ?? 0

        // Fall back inside the rectangle's bottom-right if outside-placement
        // would clip off the screen bottom (rectangle hugs bottom edge).
        if cgY + winSize.height > screenHeight {
            cgY = region.maxY - btnSize.height - padding - margin
        }

        // Clamp x so the button window doesn't fall off the left/right edge.
        cgX = max(0, min(cgX, screenWidth - winSize.width))
        cgY = max(0, min(cgY, screenHeight - winSize.height))

        // CG → AppKit y-flip.
        let appKitFrame = NSRect(
            x: cgX,
            y: screenHeight - cgY - winSize.height,
            width: winSize.width,
            height: winSize.height
        )

        self.stopButton = RecordingStopButton(
            frame: NSRect(
                x: padding, y: padding,
                width: btnSize.width, height: btnSize.height
            )
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
        self.ignoresMouseEvents = false  // we want the button click

        let container = NSView(frame: NSRect(origin: .zero, size: winSize))
        // Optional: subtle darkening so the button is visible on light
        // backgrounds. Comment out if pure transparency is preferred.
        // container.wantsLayer = true
        // container.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.25).cgColor
        // container.layer?.cornerRadius = 8
        container.addSubview(stopButton)
        self.contentView = container

        stopButton.target = self
        stopButton.action = #selector(stopClicked(_:))
    }

    @objc private func stopClicked(_ sender: Any?) {
        onStop?()
    }
}
