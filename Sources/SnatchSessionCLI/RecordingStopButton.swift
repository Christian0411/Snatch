// Sources/SnatchSessionCLI/RecordingStopButton.swift
import AppKit

/// Pill-shaped "Stop" button rendered next to the recording overlay rectangle.
/// Subclassed only to centralize styling — behavior is plain NSButton.
final class RecordingStopButton: NSButton {

    static let preferredSize = CGSize(width: 88, height: 28)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.title = "Stop"
        self.bezelStyle = .rounded
        self.isBordered = true
        self.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        self.contentTintColor = .systemRed
        self.keyEquivalent = ""  // No accelerator — overlay window doesn't take key focus.
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }
}
