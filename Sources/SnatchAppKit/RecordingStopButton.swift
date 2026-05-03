// Sources/SnatchAppKit/RecordingStopButton.swift
import AppKit

/// Pill-shaped "Stop" button rendered next to the recording overlay rectangle.
/// Custom-drawn for visibility against arbitrary app backgrounds — see pre-M6
/// tweaks spec, Item 3. Matches `CropperRecordButton` styling exactly; the
/// dashed muted-red border around the captured region (pre-M6 polish item 4)
/// carries the "you're recording" signal so the button itself stays calm.
/// We own the entire `draw(_:)` for the same reason as CropperRecordButton —
/// `super.draw` would erase our pill fill on a transparent overlay window.
final class RecordingStopButton: NSButton {

    static let preferredSize = CGSize(width: 88, height: 28)
    static let cornerRadius: CGFloat = 6

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.title = "Stop"
        self.isBordered = false
        self.bezelStyle = .regularSquare
        self.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        self.keyEquivalent = "" // No accelerator — overlay window doesn't take key focus.
    }

    override func draw(_ dirtyRect: NSRect) {
        // 1. Pill background.
        let alpha: CGFloat = isHighlighted ? 0.85 : 0.7
        NSColor.black.withAlphaComponent(alpha).setFill()
        NSBezierPath(
            roundedRect: bounds,
            xRadius: Self.cornerRadius,
            yRadius: Self.cornerRadius
        ).fill()

        // 2. Title, centered. We draw it ourselves rather than via super.draw —
        //    super.draw would re-paint the cell's background and erase our pill.
        let attrs: [NSAttributedString.Key: Any] = [
            .font: self.font ?? NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let titleSize = (title as NSString).size(withAttributes: attrs)
        let origin = NSPoint(
            x: (bounds.width - titleSize.width) / 2,
            y: (bounds.height - titleSize.height) / 2
        )
        (title as NSString).draw(at: origin, withAttributes: attrs)
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }
}
