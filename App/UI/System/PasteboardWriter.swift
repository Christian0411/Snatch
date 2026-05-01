import AppKit
import os
import SnatchKit

/// Writes a file URL to the general pasteboard so ⌘V pastes the file
/// (preserving GIF animation in Slack, Discord, Finder, etc.).
@MainActor
final class PasteboardWriter {
    init() {}

    func copy(fileURL: URL) {
        let pb = NSPasteboard.general
        pb.clearContents()
        let success = pb.writeObjects([fileURL as NSURL])
        if !success {
            Log.system.error("pasteboard.writeObjects returned false for \(fileURL.path, privacy: .public)")
        }
    }
}
