// Sources/SnatchAppKit/CropperRecordButton.swift
import AppKit

/// Pill-shaped "Record" button rendered next to the cropper rectangle.
/// Custom-drawn for visibility against arbitrary wallpapers — see pre-M6
/// tweaks spec, Item 3. We own the entire `draw(_:)`: pill background +
/// title text. We do NOT call `super.draw` because `NSButtonCell.draw`
/// redraws into the layer in a way that erases our fill on a transparent
/// overlay window.
final class CropperRecordButton: NSButton {

    static let preferredSize = CGSize(width: 88, height: 28)
    static let cornerRadius: CGFloat = 6

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.title = "Record"
        self.isBordered = false
        // .regularSquare suppresses the system bezel (we paint our own pill).
        self.bezelStyle = .regularSquare
        self.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        self.keyEquivalent = "" // Space/Return are owned by the view; don't fight.
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
