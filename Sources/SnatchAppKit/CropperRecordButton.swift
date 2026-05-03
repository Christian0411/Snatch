// Sources/SnatchAppKit/CropperRecordButton.swift
import AppKit

/// Pill-shaped "Record" button rendered next to the cropper rectangle.
/// Custom-drawn for visibility against arbitrary wallpapers — see pre-M6
/// tweaks spec, Item 3.
final class CropperRecordButton: NSButton {

    static let preferredSize = CGSize(width: 88, height: 28)
    static let cornerRadius: CGFloat = 6

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.title = "Record"
        self.isBordered = false
        // .regularSquare suppresses the system bezel (we paint our own pill).
        self.bezelStyle = .regularSquare
        self.wantsLayer = true
        self.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        self.contentTintColor = .white
        self.keyEquivalent = "" // Space/Return are owned by the view; don't fight.
        // Tell NSButton's cell to render the title centered on transparent bg;
        // we draw the pill ourselves in draw(_:).
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
        // NSButton renders the title attributed-string on top of our pill fill.
        super.draw(dirtyRect)
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }
}
