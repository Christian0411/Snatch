// Sources/SnatchAppKit/RecordingStopButton.swift
import AppKit

/// Pill-shaped "Stop" button rendered next to the recording overlay rectangle.
/// Custom-drawn for visibility against arbitrary app backgrounds — see pre-M6
/// tweaks spec, Item 3. Matches `CropperRecordButton` styling exactly; the
/// dashed muted-red border around the captured region (pre-M6 polish item 4)
/// carries the "you're recording" signal so the button itself stays calm.
final class RecordingStopButton: NSButton {

    static let preferredSize = CGSize(width: 88, height: 28)
    static let cornerRadius: CGFloat = 6

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.title = "Stop"
        self.isBordered = false
        self.bezelStyle = .regularSquare
        self.wantsLayer = true
        self.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        self.contentTintColor = .white
        self.keyEquivalent = "" // No accelerator — overlay window doesn't take key focus.
        (self.cell as? NSButtonCell)?.backgroundColor = .clear
        (self.cell as? NSButtonCell)?.isBordered = false
    }

    override func draw(_ dirtyRect: NSRect) {
        let alpha: CGFloat = isHighlighted ? 0.85 : 0.7
        NSColor.black.withAlphaComponent(alpha).setFill()
        NSBezierPath(
            roundedRect: bounds,
            xRadius: Self.cornerRadius,
            yRadius: Self.cornerRadius
        ).fill()
        super.draw(dirtyRect)
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }
}
