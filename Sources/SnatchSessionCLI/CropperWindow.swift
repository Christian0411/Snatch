// Sources/SnatchSessionCLI/CropperWindow.swift
import AppKit

/// Transparent borderless overlay window at `NSWindow.Level.screenSaver`,
/// sized to fill `screen`. Configured per spec §6.
///
/// `canBecomeKey` is overridden to true because borderless windows default
/// to false — without this, keyboard events (Esc, Space, Enter) would never
/// reach the view's responder chain.
final class CropperWindow: NSWindow {

    let cropperView: CropperView

    init(screen: NSScreen, initialRegion: CGRect?) {
        let frame = screen.frame
        self.cropperView = CropperView(frame: NSRect(origin: .zero, size: frame.size), initialRegion: initialRegion)

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

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func becomeKey() {
        super.becomeKey()
        self.makeFirstResponder(cropperView)
    }
}
