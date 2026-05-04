# Pre-M6 cursor affordances — design

**Status:** Draft 2026-05-03.
**Goal:** Make the cropper cursor reflect what a click would do. Resize cursors over the 8 resize handles; open-/closed-hand cursor over the rect interior. No state-machine changes; no new windows; no event monitors.

## Motivation

The cropper today shows two cursors: a custom white "+" crosshair (over the dim area, in `.idle` and `.dragging`, and outside `.have(rect)`) and the system arrow everywhere else. The 8 resize handles and the rect's body all draw the arrow — even though clicking-and-dragging on those regions resizes or moves the rect. Users who don't already know body-drag-to-move works have to discover it by trying. The native macOS screenshot tool sets directional resize cursors over its handles and an open-hand cursor over its rect interior; Snatch should match that affordance.

A previous round (pre-M6 tweaks, 2026-05-01) explicitly deferred resize cursors with the rationale "the visible affordance is the white circle; the cursor stays as the default arrow". That decision is reversed here.

## Non-goals

- **No click-through to underlying windows.** A larger design considered making the rect interior pass clicks through to the app beneath, with ⌘ as a modifier to engage move-mode. That design ran into permission and keyboard-focus complications and was cut. The rect interior continues to belong to the cropper; clicks inside continue to start a `.body` move.
- **No ⌘ modifier behavior.** No new modifier-key semantics anywhere in the cropper.
- **No on-screen hint text** ("⌘ to move", etc.). The cursor change is the affordance.
- **No changes to the state machine.** `applyMouseDown`, `applyMouseDragged`, `applyMouseUp`, `CropperGeometry.hitTest`, `CropperGeometry.resize`, and the `CropperState.Mode` cases are untouched. Body-drag-to-move already works (since M3) — we're adding visual feedback for behavior that already exists.
- **No preference store, menu item, or user-facing toggle.** The new cursors are unconditional.
- **No M6 work.** This is a pre-M6 polish item; M6 (Developer ID + notarization + ship) follows.

## Behavior

The cursor at a given moment is determined by `(state.mode, cursor location, isOverRecordButton)`:

| Mode | Cursor location | Cursor |
|---|---|---|
| `.idle` | anywhere in view, cursor present | `crosshair` (existing custom white "+") |
| `.idle` | cursor outside view (`mouseLocation == nil`) | `arrow` |
| `.dragging(...)` | anywhere | `crosshair` |
| `.have(rect)` | over `.topLeft` or `.bottomRight` handle | `↘↖` (resize NWSE) |
| `.have(rect)` | over `.topRight` or `.bottomLeft` handle | `↗↙` (resize NESW) |
| `.have(rect)` | over `.top` or `.bottom` handle | `↕` (`NSCursor.resizeUpDown`) |
| `.have(rect)` | over `.left` or `.right` handle | `↔` (`NSCursor.resizeLeftRight`) |
| `.have(rect)` | inside rect, not on a handle, not over Record button | `openHand` (grab) |
| `.have(rect)` | outside rect | `crosshair` |
| `.have(rect)` | over the floating Record button | `arrow` |
| `.have(rect)` | cursor outside view (`mouseLocation == nil`) | `arrow` |
| `.resizing(handle: .body, …)` | (gesture active, location ignored) | `closedHand` (grabbing) |
| `.resizing(handle: .topLeft, …)` etc. | (gesture active, location ignored) | locked to that handle's directional cursor |

### Gesture lock

During `.resizing(...)`, the cursor is locked to the gesture's intended cursor regardless of where the mouse currently is. Two reasons:

1. **macOS convention.** macOS window-resize cursors stay locked for the duration of the drag — releasing your grip on the corner doesn't switch the cursor mid-drag.
2. **Drift tolerance.** Resize handles are 12pt hit-rects; during a drag the user's pointer often crosses outside that area. We don't want the cursor to "jitter" between resize and crosshair as they cross the handle boundary.

The gesture lock falls out naturally from the predicate: when `mode == .resizing(handle, …)`, the predicate returns the cursor for `handle` and ignores `point`.

### Record-button override

When the cursor is over the floating Record button (visible in `.have(rect)`), the cursor is `arrow`. This rule overrides everything else — including a hypothetical handle that overlaps the button (would only occur for very small rects near a screen edge). The check is short-circuited at the top of the predicate.

## Architecture

The pattern follows `CropperState.shouldShowCrosshair` introduced in pre-M6 tweaks: a pure predicate in `SnatchKit` that takes the cursor location and parameters, and a thin AppKit-side mapping in `SnatchAppKit/CropperView` that converts the predicate result into an `NSCursor` and calls `.set()`.

### `Sources/SnatchKit/UI/Cropper/CropperState.swift` — additions

A new enum and a new method:

```swift
public enum CropperCursor: Equatable, Sendable {
    case crosshair
    case arrow
    case resizeNWSE
    case resizeNESW
    case resizeVertical
    case resizeHorizontal
    case grab        // openHand — over body, no gesture
    case grabbing    // closedHand — body-move gesture in progress
}

public func desiredCursor(
    at cursor: CGPoint?,
    handleSize: CGFloat,
    isOverRecordButton: Bool
) -> CropperCursor {
    if isOverRecordButton { return .arrow }
    guard let p = cursor else { return .arrow }
    switch mode {
    case .idle, .dragging:
        return .crosshair
    case .resizing(let handle, _, _, _):
        return Self.cursorFor(handle: handle, gestureActive: true)
    case .have(let r):
        guard let h = CropperGeometry.hitTest(point: p, in: r, handleSize: handleSize) else {
            return .crosshair
        }
        return Self.cursorFor(handle: h, gestureActive: false)
    }
}

private static func cursorFor(handle: CropperHandle, gestureActive: Bool) -> CropperCursor {
    switch handle {
    case .topLeft, .bottomRight: return .resizeNWSE
    case .topRight, .bottomLeft: return .resizeNESW
    case .top, .bottom:          return .resizeVertical
    case .left, .right:          return .resizeHorizontal
    case .body:                  return gestureActive ? .grabbing : .grab
    }
}
```

`shouldShowCrosshair(cursor:handleSize:)` is rewritten as a one-line wrapper:

```swift
public func shouldShowCrosshair(cursor: CGPoint?, handleSize: CGFloat) -> Bool {
    desiredCursor(at: cursor, handleSize: handleSize, isOverRecordButton: false) == .crosshair
}
```

The wrapper preserves all 7 existing `shouldShowCrosshair` test cases — `desiredCursor` with `isOverRecordButton: false` returns `.crosshair` in exactly the same situations the old direct predicate returned `true`.

### `Sources/SnatchAppKit/NSCursor+ResizeDiagonal.swift` — new file

The private-API call sites for the diagonal resize cursors. Two computed properties on `NSCursor`, each delegating to a private helper that guards the call with `responds(to:)` and falls back to `resizeUpDown`:

```swift
import AppKit

extension NSCursor {
    /// `↘↖` cursor — used for top-left and bottom-right resize handles.
    /// Backed by the private `_windowResizeNorthWestSouthEastCursor` selector;
    /// falls back to `resizeUpDown` if the selector ever disappears.
    static var resizeDiagonalNWSE: NSCursor {
        diagonalCursor(selector: "_windowResizeNorthWestSouthEastCursor")
    }

    /// `↗↙` cursor — used for top-right and bottom-left resize handles.
    static var resizeDiagonalNESW: NSCursor {
        diagonalCursor(selector: "_windowResizeNorthEastSouthWestCursor")
    }

    private static func diagonalCursor(selector name: String) -> NSCursor {
        let sel = NSSelectorFromString(name)
        if NSCursor.responds(to: sel),
           let result = NSCursor.perform(sel),
           let cursor = result.takeUnretainedValue() as? NSCursor {
            return cursor
        }
        return .resizeUpDown
    }
}
```

`takeUnretainedValue()` is correct here: NSCursor's class methods that return system cursors follow the Cocoa convention of returning unowned shared instances (no `alloc`/`copy`/`new`/`init`/`create` in the name).

The private-API path was vetted in the brainstorming session:

- The selectors exist in the AppKit runtime headers as of macOS 14 / 15 (and earlier).
- Shipping non–Mac App Store apps (e.g. Skim) use this exact pattern.
- Notarization scans for malware and signing, not for private-API usage. App Store review *does* reject private API but Snatch ships via Developer ID, not the App Store.
- The `responds(to:)` guard provides forward compatibility — if Apple removes the selectors, Snatch silently falls back to `resizeUpDown`.

### `Sources/SnatchAppKit/CropperView.swift` — modifications

`updateCursor()` is rewritten to switch over `desiredCursor`:

```swift
private func updateCursor() {
    let cursor = state.desiredCursor(
        at: mouseLocation,
        handleSize: Self.handleSize,
        isOverRecordButton: cursorIsOverRecordButton
    )
    nsCursor(for: cursor).set()
}

private func nsCursor(for c: CropperCursor) -> NSCursor {
    switch c {
    case .crosshair:        return Self.crosshairCursor
    case .arrow:            return .arrow
    case .resizeNWSE:       return .resizeDiagonalNWSE
    case .resizeNESW:       return .resizeDiagonalNESW
    case .resizeVertical:   return .resizeUpDown
    case .resizeHorizontal: return .resizeLeftRight
    case .grab:             return .openHand
    case .grabbing:         return .closedHand
    }
}
```

The crosshair x/y readout pill currently checks `state.shouldShowCrosshair(...) && !cursorIsOverRecordButton`. The `cursorIsOverRecordButton` clause is now subsumed by `desiredCursor`'s top-level override, so the pill check simplifies to:

```swift
state.desiredCursor(
    at: cursor,
    handleSize: Self.handleSize,
    isOverRecordButton: cursorIsOverRecordButton
) == .crosshair
```

No new mouse handlers; no changes to `mouseDown` / `mouseDragged` / `mouseUp` / `mouseMoved` / `mouseExited` / `cursorUpdate`. Cursor swap timing matches today: every event that updates `mouseLocation` calls `updateCursor()`, plus the pre-existing `cursorUpdate(with:)` AppKit hook.

## Tests

**`Tests/SnatchKitTests/CropperStateCursorTests.swift`** — new file, ~16 cases. Pure unit tests, no AppKit dependency.

| # | Mode | Cursor at | isOverRecordButton | Expected |
|---|---|---|---|---|
| 1 | `.idle` | non-nil point | false | `.crosshair` |
| 2 | `.idle` | nil | false | `.arrow` |
| 3 | `.dragging(...)` | any | false | `.crosshair` |
| 4 | `.have(50,50,100,100)` | over `.topLeft` (50,50) | false | `.resizeNWSE` |
| 5 | `.have(50,50,100,100)` | over `.bottomRight` (150,150) | false | `.resizeNWSE` |
| 6 | `.have(50,50,100,100)` | over `.topRight` (150,50) | false | `.resizeNESW` |
| 7 | `.have(50,50,100,100)` | over `.bottomLeft` (50,150) | false | `.resizeNESW` |
| 8 | `.have(50,50,100,100)` | over `.top` (100,50) | false | `.resizeVertical` |
| 9 | `.have(50,50,100,100)` | over `.left` (50,100) | false | `.resizeHorizontal` |
| 10 | `.have(50,50,100,100)` | inside body (100,100) | false | `.grab` |
| 11 | `.have(50,50,100,100)` | outside (10,10) | false | `.crosshair` |
| 11b | `.have(50,50,100,100)` | nil | false | `.arrow` |
| 12 | `.have(50,50,100,100)` | inside body (100,100) | **true** | `.arrow` (override) |
| 13 | `.resizing(handle: .body, …)` | (any) | false | `.grabbing` |
| 14 | `.resizing(handle: .topLeft, …)` | (any) | false | `.resizeNWSE` |
| 15 | `.resizing(handle: .left, …)` | (any) | false | `.resizeHorizontal` |

All seven existing `shouldShowCrosshair` test cases continue to pass unchanged — the wrapper delegates to `desiredCursor(... isOverRecordButton: false)`, which preserves the old semantics for every input.

No AppKit-side tests for `NSCursor+ResizeDiagonal`. The extension is a thin private-API call with a `responds(to:)` fallback; correctness is verified by manual smoke testing during the M6 polish pass:

- Open the cropper, hover each of the 8 handles. Each shows the correct directional cursor.
- Hover the rect body. Cursor is `openHand`.
- Mouse-down on body, drag. Cursor is `closedHand` for the duration; rect moves with the drag.
- Mouse-down on a corner handle, drag. Cursor stays diagonal for the duration; rect resizes.
- Hover the floating Record button. Cursor is `arrow`.
- Hover the dim area outside the rect. Cursor is the white "+" crosshair (existing).

## Files touched

```
Sources/SnatchKit/UI/Cropper/CropperState.swift           (modified — add CropperCursor + desiredCursor; rewrite shouldShowCrosshair as wrapper)
Sources/SnatchAppKit/NSCursor+ResizeDiagonal.swift        (new — ~30 LOC)
Sources/SnatchAppKit/CropperView.swift                    (modified — updateCursor + draw pill check)
Tests/SnatchKitTests/CropperStateCursorTests.swift        (new — ~80 LOC)
```

Estimated total change: ~150–180 LOC.

## Risks and rollback

- **Private-API stability.** Mitigated by `responds(to:)` guard. If Apple removes the selectors in a future macOS, the diagonal handles fall back to `resizeUpDown` (a degraded but functional cursor). Detection: a manual test on each new macOS major.
- **Cursor-swap timing.** AppKit calls `cursorUpdate(with:)` only when the cursor crosses tracking-area boundaries — not on every `mouseMoved`. This is why pre-M6 tweaks added an explicit `updateCursor()` call from `mouseMoved`/`mouseDown`/`mouseDragged`/`mouseUp`. The same call sites cover the new cursor transitions; no new triggers needed.

Rollback is trivial: revert `updateCursor()` to its prior form (crosshair/arrow only), drop the new file, and delete the cursor-test file. No data, no preferences, no on-disk state to undo.
