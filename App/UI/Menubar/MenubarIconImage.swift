import AppKit
import SnatchKit

extension MenubarIcon {
    /// Constructs the NSImage representation. `.idle` is a template
    /// (auto-tinted by macOS to match menubar theme). `.recording` and
    /// `.permissionDenied` use a red palette since the color is part
    /// of the signal.
    var nsImage: NSImage {
        switch self {
        case .idle:
            let img = NSImage(systemSymbolName: "camera.viewfinder",
                              accessibilityDescription: "Snatch")!
            img.isTemplate = true
            return img
        case .recording:
            let cfg = NSImage.SymbolConfiguration(paletteColors: [.systemRed])
            let img = NSImage(systemSymbolName: "record.circle.fill",
                              accessibilityDescription: "Recording")!
                .withSymbolConfiguration(cfg)!
            return img
        case .permissionDenied:
            let cfg = NSImage.SymbolConfiguration(paletteColors: [.systemRed])
            let img = NSImage(systemSymbolName: "exclamationmark.triangle.fill",
                              accessibilityDescription: "Permission required")!
                .withSymbolConfiguration(cfg)!
            return img
        }
    }
}
