# Pre-M6 tweaks — design

**Status:** Draft 2026-05-01.
**Goal:** Three small UX refinements between the (already shipped) pre-M6 polish pass and M6 (notarize + ship). All additive, reversible, bounded to existing M3/M5 surfaces plus one new preference store.

## Motivation

Pre-M6 polish landed dashed cropper/recording borders, circle handles, and the "Remember Last Capture Area" toggle. Three more details would tighten the cropper experience before the design freezes for distribution:

1. **Selection feels imprecise without coordinate feedback.** macOS `⇧⌘4` shows a small crosshair with live x/y; the Snatch cropper currently shows the default arrow cursor and no readout, so users have no way to align a selection to a known pixel boundary.
2. **The Record-button confirmation step is friction for the "drag and go" use case.** When "Remember Last Capture Area" is OFF (cropper opens blank every time), the user is always drawing a fresh rect and the Record button click is purely a confirmation. An optional auto-start would skip it.
3. **The Record and Stop buttons can be hard to see** against varying wallpapers / app backgrounds. Today they use stock `NSButton` with `bezelStyle = .rounded`, which renders semi-translucent and disappears against busy or light backgrounds.

## Non-goals

- No system resize cursors over the 8 cropper handles (the visible affordance is the white circle; the cursor stays as the default arrow). Out of scope and deferred.
- No animated marching-ants on either border. Static dashes only (locked in pre-M6 polish).
- No pre-record countdown or "undo grace period" when Auto-Start fires. Esc-during-recording is the recovery path.
- No additional Preferences window or submenu structure. The new toggle lives in the existing menubar dropdown.
- No changes to `RegionStore`, `CropperState.applyMouseDown/Dragged/Up`, `CropperGeometry`, `CropperHandle`, `RememberRegionPreferenceStore`, or `RecordingOverlayWindow.BorderOverlayView`.

## Items

### Item 1 — Crosshair cursor + x/y readout in selection mode

**File:** `Sources/SnatchAppKit/CropperView.swift` (mouse tracking, cursor swap, label drawing). Plus `Sources/SnatchAppKit/CropperWindow.swift` for `acceptsMouseMovedEvents = true`. Plus a new method on `CropperState` in `Sources/SnatchKit/UI/Cropper/CropperState.swift` for the visibility predicate.

#### Visibility predicate

The crosshair is visible only when a click *would* start a fresh selection drag, plus while the user is actively drawing one:

| `state.mode` | Cursor location | Crosshair visible? |
|---|---|---|
| `.idle` | anywhere | ✅ |
| `.dragging(...)` | anywhere | ✅ |
| `.resizing(...)` | anywhere | ❌ |
| `.have(rect)` | outside `rect` | ✅ |
| `.have(rect)` | inside `rect` (non-handle) | ❌ |
| `.have(rect)` | over any handle's 12pt hit-rect | ❌ |

The predicate is added to `CropperState` so it can be unit-tested in isolation from AppKit:

```swift
public func shouldShowCrosshair(cursor: CGPoint?, handleSize: CGFloat) -> Bool {
    guard let cursor else { return false }
    switch mode {
    case .idle:      return true
    case .dragging:  return true
    case .resizing:  return false
    case .have(let r):
        if CropperGeometry.hitTest(point: cursor, in: r, handleSize: handleSize) != nil {
            return false
        }
        return !r.contains(cursor)
    }
}
```

`CropperView.shouldShowCrosshair` becomes a one-line delegation to `state.shouldShowCrosshair(cursor: mouseLocation, handleSize: Self.handleSize)`.

#### Cursor — programmatic `NSCursor`

A static, lazily-built `NSCursor` rendered into a 16×16 `NSImage` at runtime. No bundled PNG asset; `NSImage(size:flipped:_:)` redraws at any backing scale, so Retina is automatic.

```swift
private static let crosshairCursor: NSCursor = {
    let size = NSSize(width: 16, height: 16)
    let img = NSImage(size: size, flipped: false) { _ in
        NSColor.white.setStroke()
        let p = NSBezierPath()
        p.move(to: NSPoint(x: 8, y: 0));  p.line(to: NSPoint(x: 8, y: 16))
        p.move(to: NSPoint(x: 0, y: 8));  p.line(to: NSPoint(x: 16, y: 8))
        p.lineWidth = 1
        p.stroke()
        return true
    }
    return NSCursor(image: img, hotSpot: NSPoint(x: 8, y: 8))
}()
```

Hot-spot is the geometric center of the cross.

#### Cursor swap mechanism

A single full-view `NSTrackingArea` with options `[.mouseMoved, .activeAlways, .cursorUpdate, .inVisibleRect]`. Added in `viewDidMoveToWindow` and rebuilt on `updateTrackingAreas` (covers cropper window resize when the user moves the cropper across displays). `CropperWindow.acceptsMouseMovedEvents = true`.

```swift
override func cursorUpdate(with event: NSEvent) {
    if state.shouldShowCrosshair(cursor: mouseLocation, handleSize: Self.handleSize) {
        Self.crosshairCursor.set()
    } else {
        NSCursor.arrow.set()
    }
}

override func mouseMoved(with event: NSEvent) {
    mouseLocation = convert(event.locationInWindow, from: nil)
    needsDisplay = true   // redraws label
}
```

`mouseLocation: CGPoint?` is a new stored property on `CropperView`, set on every move and cleared on `mouseExited` (to hide the label cleanly when the cursor leaves the cropper, e.g. crossing to a different display).

#### Label drawing

A new step 5 inside `CropperView.draw(_:)`, gated on `state.shouldShowCrosshair(cursor: mouseLocation, handleSize: Self.handleSize)`:

1. **Convert** view-local `mouseLocation` (top-left origin, since the view is flipped) → CG screen-space top-left origin:

   ```swift
   let mainHeight = NSScreen.main!.frame.height
   let cgY_screenTop = mainHeight - (window.frame.origin.y + window.frame.height)
   let cgX = window.frame.origin.x + mouseLocation.x
   let cgY = cgY_screenTop + mouseLocation.y   // view is flipped → y is from window top
   ```

   On the main display this collapses to `cgX = mouseLocation.x; cgY = mouseLocation.y`. Multi-display correctness depends on M5's existing single-screen-under-cursor behavior — the cropper window's `frame.origin` matches the chosen `screen.frame.origin`, so the conversion is correct for whichever screen the cropper is on.

2. **Format** two strings: `"\(Int(cgX.rounded()))"` and `"\(Int(cgY.rounded()))"`. No labels (no "X:" / "Y:") — two left-aligned numbers stacked.

3. **Pill background** sized to fit both lines with 4pt internal padding on every side (text rect insets to `(4, 4, 4, 4)` inside the pill):
   - Fill: `NSColor.black.withAlphaComponent(0.7)`
   - Corner radius: 6pt
   - No border

4. **Text**: 12pt medium white, left-aligned. Font and color match the existing W×H dimensions label (CropperView.swift:100–104).

5. **Position**: `mouseLocation + (12, 12)` in view-local (flipped) coords — bottom-right of cursor. Edge-flip rules:
   - If `pillFrame.maxX > bounds.width` → place at `mouseLocation + (-12 - pillW, 12)` (bottom-left of cursor).
   - If `pillFrame.maxY > bounds.height` → place above the cursor with `y = mouseLocation.y - pillH - 12` instead (top side).
   - Both flips can compose (top-left of cursor near the bottom-right corner of the screen).

#### Auto-start integration (forward reference)

`CropperView` gains `var autoStartOnCommit: Bool = false` (defined here, consumed by Item 2). After `applyMouseUp` produces a new state in `CropperView.mouseUp(with:)`, if the new `mode` is `.have(rect)` AND `autoStartOnCommit`, call `onRecord?(rect)` directly — same callback path as the Record button / Space / Return.

CropperView does not import any `SnatchKit` preference store; the coordinator computes the flag and assigns it on each `showCropper()` call (see Item 2).

#### Coordinate-conversion notes

- `NSEvent.locationInWindow` is in window coordinates with bottom-left origin (AppKit convention). `convert(_:from:nil)` to the flipped CropperView gives top-left view-local — what we want for drawing.
- The conversion to CG screen-space (top-left global origin) is needed only for the *displayed* readout, since the user-visible expectation is "global pixel coordinates as macOS reports them in `⇧⌘4`."

### Item 2 — Auto-Start Recording on Selection

#### 2a. New preference store

**New file:** `Sources/SnatchKit/System/AutoStartRecordingPreferenceStore.swift`. Near-clone of `RememberRegionPreferenceStore`. Two diffs vs. that store: default is `false` (not `true`) and the key is `"autoStartOnSelection"`.

```swift
import Foundation

/// UserDefaults-backed bool: should the cropper auto-fire `onRecord` the
/// instant a fresh selection commits (i.e., on `mouseUp` from `.dragging`)?
/// Default `false` (preserves M5/pre-M6 behavior — user clicks Record,
/// or presses Space/Return).
///
/// The runtime gate also requires `RememberRegionPreferenceStore.isEnabled
/// == false`. See `MenubarCoordinator.showCropper()`.
public final class AutoStartRecordingPreferenceStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "autoStartOnSelection") {
        self.defaults = defaults
        self.key = key
    }

    public var isEnabled: Bool {
        defaults.object(forKey: key) as? Bool ?? false
    }

    public func setEnabled(_ value: Bool) {
        defaults.set(value, forKey: key)
    }
}
```

#### 2b. Coordinator wiring

**File:** `App/MenubarCoordinator.swift`.

Add stored property + init parameter immediately after the existing `rememberRegionStore`:

```swift
let autoStartStore: AutoStartRecordingPreferenceStore
```

Inside `showCropper()`, after the existing `if rememberRegionStore.isEnabled, let last = ...` / `else` block that assigns `cropperWindow.cropperView.state`, and before `cropperWindow.orderFrontRegardless()`:

```swift
cropperWindow.cropperView.autoStartOnCommit =
    !rememberRegionStore.isEnabled && autoStartStore.isEnabled
```

This is recomputed on every cropper open, so toggling either preference takes effect on the next ⇧⌘6 / menubar click.

#### 2c. Menubar menu item

**File:** `App/UI/Menubar/MenubarController.swift`. Inside `buildMenu()`, immediately after the existing "Remember Last Capture Area" item and before the Recent Recordings ▸ submenu:

```swift
let autoStart = NSMenuItem(
    title: "Auto-Start Recording on Selection",
    action: #selector(toggleAutoStartAction),
    keyEquivalent: ""
)
autoStart.target = self
autoStart.state = autoStartStore.isEnabled ? .on : .off
autoStart.isEnabled = !rememberRegionStore.isEnabled
menu.addItem(autoStart)
```

`isEnabled = !rememberRegionStore.isEnabled` makes the item greyed out (NSMenu's disabled state) when Remember is ON. The user cannot enable Auto-Start without first turning Remember off — by construction, the (Remember ON, Auto-Start ON) combination is unreachable from the UI.

New action handler (next to `toggleRememberAction`):

```swift
@objc private func toggleAutoStartAction() {
    autoStartStore.setEnabled(!autoStartStore.isEnabled)
}
```

`buildMenu()` is invoked fresh on every status-item click, so the disabled state and checkmark stay in sync without a `menuWillOpen` change.

#### 2d. AppDelegate wiring

**File:** `App/AppDelegate.swift`. Where `rememberRegionStore = RememberRegionPreferenceStore()` is constructed, add a sibling:

```swift
autoStartStore = AutoStartRecordingPreferenceStore()
```

Pass into both `MenubarCoordinator.init(...)` and `MenubarController.init(...)` as `autoStartStore: autoStartStore`, immediately after the existing `rememberRegionStore: rememberRegionStore` argument.

#### Behavior matrix

| Remember | Auto-Start | Cropper open behavior |
|---|---|---|
| ON | OFF | Pre-fills last region; user clicks Record / Space / Return. (today, unchanged) |
| ON | ON\* | *Unreachable from UI — Auto-Start menu item is disabled when Remember is ON.* |
| OFF | OFF | Blank cropper; user drags + clicks Record / Space / Return. (today, unchanged) |
| OFF | ON | Blank cropper; user drags → instant `onRecord(rect)` on `mouseUp`. |

\* If a user manually sets both keys via `defaults write`, the runtime gate (`!rememberRegionStore.isEnabled && autoStartStore.isEnabled`) makes Remember win and Auto-Start has no effect. No surprise auto-record on cropper open.

### Item 3 — Higher-contrast Record / Stop buttons

**Files:** `Sources/SnatchAppKit/CropperRecordButton.swift`, `Sources/SnatchAppKit/RecordingStopButton.swift`.

#### Shared spec

Both buttons become custom-drawn pills, identical except for title:

| Property | Value |
|---|---|
| Background | `NSColor.black.withAlphaComponent(0.7)` (`0.85` while `isHighlighted`) |
| Corner radius | 6pt |
| Border | none |
| Title | 13pt semibold white, centered |
| Size | 88×28 (unchanged) |
| Disabled state | not used (neither button is ever shown disabled) |

The dropped `.systemRed` content tint on Stop is intentional — the dashed muted-red border around the captured region (pre-M6 polish item 4) carries the "you're recording" signal; the button just needs to be findable and clickable.

#### Implementation

```swift
final class CropperRecordButton: NSButton {
    static let preferredSize = CGSize(width: 88, height: 28)
    static let cornerRadius: CGFloat = 6

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.title = "Record"
        self.isBordered = false
        self.bezelStyle = .regularSquare
        self.wantsLayer = true
        self.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        self.contentTintColor = .white
        self.keyEquivalent = ""
        (self.cell as? NSButtonCell)?.backgroundColor = .clear
        (self.cell as? NSButtonCell)?.isBordered = false
    }

    override func draw(_ dirtyRect: NSRect) {
        let alpha: CGFloat = isHighlighted ? 0.85 : 0.7
        NSColor.black.withAlphaComponent(alpha).setFill()
        NSBezierPath(roundedRect: bounds,
                     xRadius: Self.cornerRadius,
                     yRadius: Self.cornerRadius).fill()
        super.draw(dirtyRect)   // NSButton renders the title attributed-string on top
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }
}
```

`RecordingStopButton` is identical except `title = "Stop"`. The previous `contentTintColor = .systemRed` is dropped — text becomes white, matching Record.

`super.draw(dirtyRect)` runs *after* the pill fill so the title text renders on top. With `isBordered = false` and `bezelStyle = .regularSquare`, NSButton's default background painting is suppressed.

#### Why `draw(_:)` and not layer-backed `backgroundColor`

A layer-backed `backgroundColor` doesn't follow `isHighlighted` transitions and would require a separate KVO hookup. Drawing in `draw(_:)` makes pressed-state styling a one-line read of `isHighlighted` and avoids layering edge cases on transparent windows.

#### Layout/positioning

`CropperView.layoutRecordButton()` (CropperView.swift:169) and `RecordingOverlayWindow`'s placement of `RecordingStopButton` keep their existing math. Only the visual is changing; the buttons keep their 88×28 footprint and their callsite layout.

## Testing

### New unit tests

**`Tests/SnatchKitTests/AutoStartRecordingPreferenceStoreTests.swift`** — mirrors `RememberRegionPreferenceStoreTests`:

1. `test_isEnabled_defaultsToFalse_whenUnset`
2. `test_setEnabled_persistsValue`
3. `test_persistedValue_survivesNewStoreInstance`
4. `test_AutoStartRecordingPreferenceStore_isSendable`

Isolated `UserDefaults(suiteName: "co.snatch.tests.AutoStart.\(UUID().uuidString)")` per test.

**`Tests/SnatchKitTests/CropperStateCrosshairTests.swift`** — covers the new `shouldShowCrosshair(cursor:handleSize:)` predicate on `CropperState`:

1. `test_idle_alwaysShows`
2. `test_dragging_alwaysShows`
3. `test_resizing_neverShows`
4. `test_have_outsideRect_shows`
5. `test_have_insideRect_doesNotShow`
6. `test_have_overHandle_doesNotShow` — uses a known handle position from `CropperGeometry.handleFrames(for:handleSize:)`
7. `test_nilCursor_doesNotShow`

### No new tests for visual / AppKit-only changes

- Crosshair `NSCursor` image rendering — visual; eyeballed during smoke.
- x/y label drawing and edge-flip placement — visual.
- Auto-start `mouseUp` → `onRecord` plumbing — three lines inside `CropperView.mouseUp`; testing it would require synthesizing an `NSEvent`, fragile and low-value.
- Button restyle — pure draw.

The underlying state machines (`CropperState`, `CropperGeometry`, `RecordingSession`) are unchanged and remain covered by their existing unit tests.

### Manual smoke test (additions to the pre-M6 gate)

#### Tweak 1 — Crosshair

1. Build and launch `Snatch.app`.
2. ⇧⌘6 → blank cropper. Cursor is a small white `+` with x/y label following bottom-right of the cursor. Numbers update smoothly with movement.
3. Move cursor near far-right and bottom edges; label flips left and/or up so it never clips off the cropper.
4. Compare displayed x/y values to `⇧⌘4`'s readout at the same pixel — values should match.
5. Drag a region. During drag, crosshair + x/y label persist (live coords on the moving corner). Existing W×H label still shows at the rect's top-left.
6. Release into `.have(rect)`. Move cursor inside rect → cursor reverts to default arrow, x/y label disappears. Move outside → crosshair returns.
7. Hover any of the 8 handles → cursor reverts to default arrow.
8. Click and drag a handle (`.resizing`) → crosshair stays hidden throughout the resize gesture.

#### Tweak 2 — Auto-Start toggle

9. Open menubar with Remember ON: "Auto-Start Recording on Selection" appears below "Remember Last Capture Area" but is **greyed out**.
10. Toggle Remember OFF → re-open menubar → Auto-Start is **enabled** (clickable, unchecked).
11. Toggle Auto-Start ON → ⇧⌘6 → blank cropper → drag a region → recording starts immediately on `mouseUp` (red dashed border appears, no Record click needed).
12. Toggle Auto-Start OFF (Remember still OFF) → ⇧⌘6 → drag → Record button appears, recording does NOT auto-start.
13. Quit and relaunch → both preferences persist; menu state matches what was set before quit.

#### Tweak 3 — Higher-contrast buttons

14. Cropper Record button is a solid dark pill with crisp white "Record" text — readable against any wallpaper.
15. Click and hold the Record button → background visibly darkens (`isHighlighted` pressed state).
16. Recording overlay's Stop button has the same dark pill treatment with white "Stop" text — readable against any underlying app, no red tint.

## Risk and reversibility

| Item | Risk | Rollback |
|---|---|---|
| Tweak 1 (crosshair + label) | Tracking-area overhead on every `mouseMoved`. Bounded — single full-view tracking area, redraw is one rect. | Revert `CropperView.swift` and `CropperWindow.acceptsMouseMovedEvents`. The new `CropperState.shouldShowCrosshair(...)` method is dead code if unused; safe to leave or remove. |
| Tweak 2 (Auto-Start) | Adds one UserDefaults key (`autoStartOnSelection`). Runtime gate makes the (Remember ON, Auto-Start ON) combination impossible-by-construction even via `defaults write`. | Remove the menu item, the gate, and `autoStartStore` wiring. Key becomes unused; no migration. |
| Tweak 3 (button restyle) | Custom `draw(_:)` could conflict with future macOS UI evolutions. We sidestep by drawing only the pill background and letting `super.draw` render the title. | Revert `CropperRecordButton.swift` and `RecordingStopButton.swift`. |

## Out of scope (deferred)

- System resize cursors (`NSCursor.resizeUpDownLeftRight`, etc.) over the cropper handles.
- Animated marching-ants on either border.
- Pre-record countdown / undo grace period when Auto-Start fires.
- Multi-display crosshair correctness beyond M5's single-screen-under-cursor behavior.
- Pulsing or animated Stop button while recording.
- Hover state on either button beyond pressed feedback.
- A general Preferences window or additional menubar submenu structure.
