// Sources/SnatchCropperCLI/CropperRecordButton.swift
import AppKit

/// Pill-shaped "Record" button rendered next to the cropper rectangle.
/// Subclassed only to centralize styling — behavior is plain NSButton.
final class CropperRecordButton: NSButton {

    static let preferredSize = CGSize(width: 88, height: 28)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.title = "Record"
        self.bezelStyle = .rounded
        self.isBordered = true
        self.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        self.keyEquivalent = "" // Space/Return are owned by the view; don't fight.
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }
}
