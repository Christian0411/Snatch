// Sources/SnatchAppKit/NSCursor+ResizeDiagonal.swift
import AppKit

/// Diagonal resize cursors for cropper corner handles. macOS does not
/// publicly expose `↘↖` / `↗↙` cursors, so these go through the private
/// `_windowResize…` selectors guarded by `responds(to:)`. If the
/// selector ever disappears in a future macOS release, the cropper
/// degrades gracefully to `resizeUpDown` — visibly wrong over a diagonal
/// handle (the glyph implies vertical resize) but functional and
/// non-crashing. Detection: a manual cropper-cursor smoke pass on each
/// new macOS major.
///
/// Not cached: matches `NSCursor.arrow` / `.crosshair` and the rest of
/// AppKit's `+systemCursor` accessors, which re-resolve on each call.
/// `responds(to:)` + `perform` is a runtime hash lookup — single-digit
/// microseconds — and caching would freeze the fallback at first access
/// if the selector ever vanishes mid-session.
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
