// Sources/SnatchAppKit/CropperWindow.swift
import AppKit

/// Transparent borderless overlay window at `NSWindow.Level.screenSaver`,
/// sized to fill `screen`. Configured per spec §6.
///
/// `canBecomeKey` is overridden to true because borderless windows default
/// to false — without this, keyboard events (Esc, Space, Enter) would never
/// reach the view's responder chain.
public final class CropperWindow: NSWindow {

    public let cropperView: CropperView

    /// The screen frame the cropper is currently sized to. The
    /// `setFrame(_:display:)` override clamps any incoming frame ≠ this back
    /// to it, which is what blocks macOS's edge-drag resize gesture (a
    /// borderless `.screenSaver` window still accepts that gesture even
    /// without `.resizable` in the style mask). Kept mutable so the menubar
    /// coordinator can legitimately re-target the cropper to a different
    /// screen via `resetToScreen(_:)`.
    private var expectedScreenFrame: CGRect

    public init(screen: NSScreen, initialRegion: CGRect?) {
        let frame = screen.frame
        self.cropperView = CropperView(frame: NSRect(origin: .zero, size: frame.size), initialRegion: initialRegion)
        self.expectedScreenFrame = frame

        // 4-arg designated initializer; see Task 9 note on why the
        // 5-arg `…:screen:` convenience form can't be called here.
        super.init(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.level = .screenSaver
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true

        self.contentView = cropperView
    }

    public required init?(coder: NSCoder) { fatalError("not implemented") }

    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { true }

    public override func becomeKey() {
        super.becomeKey()
        self.makeFirstResponder(cropperView)
        cropperView.warmMouseLocation()
    }

    /// Clamp away macOS's edge-drag resize gesture. The cropper is sized to
    /// `expectedScreenFrame` and must stay there until something legitimately
    /// re-targets it (see `resetToScreen(_:)`) — but on macOS 14+ a borderless
    /// `.screenSaver` window still accepts the system edge-drag resize
    /// gesture, which calls into here with a smaller rect. Always forwarding
    /// `expectedScreenFrame` discards the gesture's rect; same-frame calls
    /// (e.g. the init-time NSWindow setup) are unaffected since the value
    /// being forwarded equals the value they passed in. The
    /// `setFrame(_:display:animate:)` variant routes through
    /// this method at the NSWindow layer, so a separate override isn't
    /// needed.
    public override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(expectedScreenFrame, display: flag)
    }

    /// Re-target the cropper to a different screen. Updates
    /// `expectedScreenFrame` first so the `setFrame(_:display:)` clamp
    /// doesn't immediately squash the call, then forwards to
    /// `super.setFrame` directly.
    public func resetToScreen(_ screen: NSScreen) {
        expectedScreenFrame = screen.frame
        super.setFrame(screen.frame, display: false)
    }
}
