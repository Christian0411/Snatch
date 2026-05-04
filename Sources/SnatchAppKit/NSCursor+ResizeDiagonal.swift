// Sources/SnatchAppKit/NSCursor+ResizeDiagonal.swift
import AppKit

/// Diagonal resize cursors for cropper corner handles. macOS does not
/// publicly expose `↘↖` / `↗↙` cursors, so these go through the private
/// `_windowResize…` selectors guarded by `responds(to:)`. If the
/// selector ever disappears in a future macOS release, the cropper
/// degrades gracefully to `resizeUpDown` rather than crashing.
extension NSCursor {

    /// `↘↖` cursor — top-left and bottom-right resize handles.
    public static var resizeDiagonalNWSE: NSCursor {
        diagonalCursor(selector: "_windowResizeNorthWestSouthEastCursor")
    }

    /// `↗↙` cursor — top-right and bottom-left resize handles.
    public static var resizeDiagonalNESW: NSCursor {
        diagonalCursor(selector: "_windowResizeNorthEastSouthWestCursor")
    }

    private static func diagonalCursor(selector name: String) -> NSCursor {
        let sel = NSSelectorFromString(name)
        guard NSCursor.responds(to: sel),
              let unmanaged = NSCursor.perform(sel),
              let cursor = unmanaged.takeUnretainedValue() as? NSCursor
        else {
            return .resizeUpDown
        }
        return cursor
    }
}
