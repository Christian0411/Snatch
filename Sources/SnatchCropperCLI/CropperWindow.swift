// Sources/SnatchCropperCLI/CropperWindow.swift
import AppKit

/// Transparent borderless overlay window at `NSWindow.Level.screenSaver`,
/// sized to fill `screen`. Configured per spec §6.
///
/// `canBecomeKey` is overridden to true because borderless windows default
/// to false — without this, keyboard events (Esc, Space, Enter) would never
/// reach the view's responder chain.
final class CropperWindow: NSWindow {

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
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
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
