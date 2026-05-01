# Pre-M6 polish — design

**Status:** Approved 2026-05-01.
**Goal:** Four targeted UX refinements before M6 (notarization + ship). All additive, reversible, and bounded to existing M3/M5 surfaces.

## Motivation

M5 shipped a working menubar app with an end-to-end cropper → record → GIF flow. Before locking the design and notarizing for distribution, four small details should be tightened to better match macOS-native screenshot conventions and to expose one user-controllable preference:

1. The cropper preview border should look like a "selection" rather than a hard outline.
2. The cropper resize handles should look like native screenshot-tool handles (small circles, not squares).
3. Users should be able to choose whether the cropper pre-fills with the last selected region.
4. The red recording border should be visually quieter — it's ambient feedback while you work, not an alarm.

The mental reference is the macOS native screenshot tool (⇧⌘5 region capture): white marching-ants dashes around the selection, white circle handles with a subtle grey rim.

## Non-goals

- No animation on either border (no marching-ants motion). Static dashes only.
- No drop shadows on handles. White fill + grey stroke is sufficient.
- No new preferences UI surface (no Preferences window). The toggle lives directly in the menubar dropdown.
- No changes to `RegionStore`'s persistence semantics. It continues to read/write unconditionally; the toggle gates the *consumer*, not the store.
- No changes to hit-test geometry. Click targets remain 12pt; only the visible draw shrinks.

## Items

### Item 1 — Cropper preview border becomes dashed

**File:** `Sources/SnatchAppKit/CropperView.swift`, inside `draw(_:)` step 2.

**Change:** Before stroking the rectangle outline, call `outline.setLineDash([6, 4], count: 2, phase: 0)`. Color stays `NSColor.white`, line width stays 1pt.

**Rationale:** A `[6, 4]` pattern reads as classic "marching ants" — dense enough to perceive as a continuous frame, with enough rhythm to communicate "this is a selection in progress."

### Item 2 — Cropper handles become small grey-rimmed white circles

**File:** `Sources/SnatchAppKit/CropperView.swift`, inside `draw(_:)` step 3.

**Change:** Replace the per-handle `NSBezierPath(rect: frame).fill()` with:

```swift
let visible = frame.insetBy(dx: 2, dy: 2)   // 12pt click rect → 8pt visible oval
let oval = NSBezierPath(ovalIn: visible)
NSColor.white.setFill()
oval.fill()
NSColor.systemGray.setStroke()
oval.lineWidth = 1
oval.stroke()
```

The outer `NSColor.white.setFill()` call before the loop should be removed (each handle now sets its own fill).

**Click target unchanged.** `CropperGeometry.handleFrames` continues to return the 12pt rects used by `CropperState.applyMouseDown` for hit-testing. Only the draw path shrinks.

**Rationale:** 8pt visible circle is small enough to read as "delicate" without sacrificing fingertip targeting. The grey stroke ensures handles remain visible against both light and dark backgrounds (a pure white fill can disappear on light wallpapers).

### Item 3 — "Remember Last Capture Area" toggle

This is the only item with structural impact. Three pieces:

#### 3a. New preference store

**New file:** `Sources/SnatchKit/System/RememberRegionPreferenceStore.swift`.

```swift
import Foundation

/// UserDefaults-backed bool: should the cropper pre-fill with the last
/// recorded region? Defaults to `true` (preserves M5 behavior on first launch).
public final class RememberRegionPreferenceStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "rememberRegion") {
        self.defaults = defaults
        self.key = key
    }

    public var isEnabled: Bool {
        // `object(forKey:) as? Bool` returns nil when unset, so we default to true.
        defaults.object(forKey: key) as? Bool ?? true
    }

    public func setEnabled(_ value: Bool) {
        defaults.set(value, forKey: key)
    }
}
```

Pattern parallels `ScalePresetStore`. `RegionStore` is **not** modified — it keeps unconditionally persisting the last region, so toggling OFF and back ON later is lossless.

#### 3b. Read gate in `MenubarCoordinator.showCropper()`

**File:** `App/MenubarCoordinator.swift`.

Today (lines ~142–152):

```swift
if let last = regionStore.lastRegion {
    let viewLocal = CGRect(/* ... */)
    cropperWindow.cropperView.state = CropperState(initial: viewLocal)
} else {
    cropperWindow.cropperView.state = CropperState(initial: nil)
}
```

After:

```swift
if rememberRegionStore.isEnabled, let last = regionStore.lastRegion {
    let viewLocal = CGRect(/* ... */)
    cropperWindow.cropperView.state = CropperState(initial: viewLocal)
} else {
    cropperWindow.cropperView.state = CropperState(initial: nil)
}
```

`MenubarCoordinator` gains a stored `rememberRegionStore: RememberRegionPreferenceStore` and a corresponding init parameter.

#### 3c. Menubar menu item

**File:** `App/UI/Menubar/MenubarController.swift`, inside `buildMenu()`, inserted between the Scale ▸ submenu and the Recent Recordings ▸ submenu:

```swift
let remember = NSMenuItem(
    title: "Remember Last Capture Area",
    action: #selector(toggleRememberAction),
    keyEquivalent: ""
)
remember.target = self
remember.state = rememberRegionStore.isEnabled ? .on : .off
menu.addItem(remember)
```

New action handler:

```swift
@objc private func toggleRememberAction() {
    rememberRegionStore.setEnabled(!rememberRegionStore.isEnabled)
}
```

Because `buildMenu()` is already invoked fresh on every status-item click (see `statusItemClicked`), the checkmark naturally reflects current state without needing changes to `menuWillOpen`. `MenubarController` gains a stored `rememberRegionStore` and a corresponding init parameter.

#### 3d. Wiring

**File:** `App/AppDelegate.swift`. Where `regionStore = RegionStore()` is constructed (~line 37), add a sibling `rememberRegionStore = RememberRegionPreferenceStore()`. Pass it into `MenubarCoordinator.init` and `MenubarController.init` alongside the existing stores.

### Item 4 — Recording border becomes dashed and dampened

**File:** `Sources/SnatchAppKit/RecordingOverlayWindow.swift`, inside `BorderOverlayView.draw(_:)`.

Today:

```swift
NSColor.systemRed.setStroke()
let stroked = regionInViewCoords.insetBy(/* ... */)
let path = NSBezierPath(rect: stroked)
path.lineWidth = RecordingOverlayWindow.borderWidth
path.stroke()
```

After:

```swift
NSColor.systemRed.withAlphaComponent(0.6).setStroke()
let stroked = regionInViewCoords.insetBy(/* ... */)
let path = NSBezierPath(rect: stroked)
path.lineWidth = RecordingOverlayWindow.borderWidth
path.setLineDash([6, 4], count: 2, phase: 0)
path.stroke()
```

Width stays 2.5pt. Dash pattern matches the cropper for visual consistency. 60% alpha keeps the red readable as "you are recording" without making it visually loud while you're working in the captured app.

## Testing

### New unit tests

`Tests/SnatchKitTests/RememberRegionPreferenceStoreTests.swift`, mirroring `ScalePresetStoreTests`:

1. `test_isEnabled_defaultsToTrue_whenUnset`
2. `test_setEnabled_persistsValue`
3. `test_isEnabled_readsAcrossInstances` (simulates relaunch via a second store over the same `UserDefaults`)

Each test uses an isolated `UserDefaults(suiteName: "co.snatch.tests.RememberRegion.\(UUID().uuidString)")` like the other `*StoreTests`.

### No new tests for visual changes

Items 1, 2, and 4 are draw-only. The underlying state machines (`CropperState`, `CropperGeometry`, `RecordingSession`) are unchanged and remain covered by their existing unit tests. Verification is via manual smoke test (below).

### Manual smoke test (pre-M6 gate)

1. Build and launch `Snatch.app`.
2. ⇧⌘6 → cropper appears with dashed white border and small grey-rimmed white circle handles.
3. Drag a region, click Record → red border around region is dashed and visibly muted (not full-saturation).
4. Stop, verify GIF still saves correctly.
5. Open menubar dropdown → "Remember Last Capture Area" appears between Scale ▸ and Recent Recordings ▸ with a checkmark.
6. Re-open cropper → previous region is pre-filled.
7. Click the menu item to toggle OFF → checkmark disappears.
8. Quit Snatch, relaunch.
9. Open menubar → checkmark is still OFF (persisted).
10. Open cropper → starts blank (no pre-fill), even though the prior region is still in `RegionStore`.
11. Toggle ON, open cropper → previous region returns (proves losslessness).

## Risk and reversibility

- **Items 1, 2, 4** — pure pixels. If anything looks wrong, revert the draw changes; no migration needed.
- **Item 3** — adds one `UserDefaults` key (`rememberRegion`). Worst case: ignore the key in a future build and behavior reverts to "always on." No data is at risk; `RegionStore`'s data is untouched.

## Out of scope (deferred)

- Animated marching-ants motion on either border.
- Drop shadows on handles.
- A general Preferences window or an additional preferences submenu structure. Revisit when the second user-facing preference appears.
- Per-display handling improvements. Cropper still uses the screen under the cursor, as in M5.
