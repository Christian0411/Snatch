# Pre-M6 cursor affordances Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the cropper cursor reflect what a click would do — directional resize cursors over the 8 handles, open-/closed-hand cursor over the rect interior — without changing the state machine, windowing, or event-monitor architecture.

**Architecture:** Pure predicate `desiredCursor` in `SnatchKit/CropperState`, returning a `CropperCursor` enum. AppKit-side mapping in `SnatchAppKit/CropperView` converts the enum to an `NSCursor` and `.set()`s it. Diagonal cursors come from a small `NSCursor` extension that calls private selectors with a `responds(to:)` guard and a `resizeUpDown` fallback.

**Tech Stack:** Swift 5.10, AppKit, XCTest. SnatchKit (pure logic, unit-tested) + SnatchAppKit (AppKit shell, manually smoke-tested).

**Spec:** `docs/superpowers/specs/2026-05-03-pre-m6-cursor-affordances-design.md`

---

## File Map

| File | Action | Purpose |
|---|---|---|
| `Sources/SnatchKit/UI/Cropper/CropperState.swift` | Modify | Add `CropperCursor` enum, add `desiredCursor(at:handleSize:isOverRecordButton:)`, rewrite `shouldShowCrosshair` as wrapper |
| `Sources/SnatchAppKit/NSCursor+ResizeDiagonal.swift` | Create | Two computed `NSCursor` properties for `↘↖` and `↗↙`, backed by private selectors with `responds(to:)` guard |
| `Sources/SnatchAppKit/CropperView.swift` | Modify | Rewrite `updateCursor()` to switch over `desiredCursor`; simplify x/y readout pill check in `draw(_:)` |
| `Tests/SnatchKitTests/CropperStateCursorTests.swift` | Create | ~16 unit tests for `desiredCursor` covering every (mode, location, isOverRecordButton) combination |

Existing tests (`CropperStateCrosshairTests.swift`, all 6) remain unchanged — `shouldShowCrosshair` becomes a wrapper that returns the same boolean for the same inputs, so existing tests keep passing without edits.

---

## Task 1: Add `CropperCursor` enum (no logic yet)

**Files:**
- Modify: `Sources/SnatchKit/UI/Cropper/CropperState.swift`

The enum is the contract for the predicate we'll build in Task 2. Adding it standalone first keeps Task 2's diff focused on logic.

- [ ] **Step 1: Add the enum**

In `Sources/SnatchKit/UI/Cropper/CropperState.swift`, just above the `public struct CropperState` declaration, add:

```swift
/// The cursor the cropper should show, given the current `CropperState.mode`,
/// the cursor's location, and whether it's over the floating Record button.
/// Computed by `CropperState.desiredCursor(...)`. The AppKit-side
/// `CropperView` maps each case to a concrete `NSCursor`.
public enum CropperCursor: Equatable, Sendable {
    case crosshair
    case arrow
    case resizeNWSE
    case resizeNESW
    case resizeVertical
    case resizeHorizontal
    case grab
    case grabbing
}
```

- [ ] **Step 2: Verify it compiles**

Run: `swift build`
Expected: succeeds with no warnings or errors. (No callers yet — just type definition.)

- [ ] **Step 3: Commit**

```bash
git add Sources/SnatchKit/UI/Cropper/CropperState.swift
git commit -m "feat(cropper): add CropperCursor enum"
```

---

## Task 2: Implement `desiredCursor` for `.idle` and `.dragging` modes (TDD)

**Files:**
- Modify: `Sources/SnatchKit/UI/Cropper/CropperState.swift`
- Create: `Tests/SnatchKitTests/CropperStateCursorTests.swift`

These are the simplest cases: `.idle` and `.dragging` always return `.crosshair` when the cursor is non-nil, `.arrow` when nil, regardless of position.

- [ ] **Step 1: Write failing tests**

Create `Tests/SnatchKitTests/CropperStateCursorTests.swift` with:

```swift
import XCTest
import CoreGraphics
@testable import SnatchKit

final class CropperStateCursorTests: XCTestCase {

    private let handleSize: CGFloat = 12

    // MARK: - mode == .idle

    func test_idle_withCursorPresent_isCrosshair() {
        let s = CropperState(initial: nil)
        XCTAssertEqual(
            s.desiredCursor(at: CGPoint(x: 50, y: 50), handleSize: handleSize, isOverRecordButton: false),
            .crosshair
        )
    }

    func test_idle_withCursorNil_isArrow() {
        let s = CropperState(initial: nil)
        XCTAssertEqual(
            s.desiredCursor(at: nil, handleSize: handleSize, isOverRecordButton: false),
            .arrow
        )
    }

    // MARK: - mode == .dragging

    func test_dragging_isCrosshair_anywhere() {
        // Drive into .dragging via mouseDown from .idle.
        var s = CropperState(initial: nil)
        s = s.applyMouseDown(at: CGPoint(x: 10, y: 10), handleSize: handleSize)
        XCTAssertEqual(
            s.desiredCursor(at: CGPoint(x: 10, y: 10), handleSize: handleSize, isOverRecordButton: false),
            .crosshair
        )
        XCTAssertEqual(
            s.desiredCursor(at: CGPoint(x: 999, y: 999), handleSize: handleSize, isOverRecordButton: false),
            .crosshair
        )
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter CropperStateCursorTests`
Expected: compile error — `desiredCursor(at:handleSize:isOverRecordButton:)` does not exist on `CropperState`.

- [ ] **Step 3: Add minimal `desiredCursor` implementation**

In `Sources/SnatchKit/UI/Cropper/CropperState.swift`, inside the `CropperState` struct (next to `shouldShowCrosshair`), add:

```swift
/// The cursor the view should display right now, given the current mode,
/// the cursor's view-local position, and whether the cursor is over the
/// floating Record button. Pure: no AppKit dependency.
///
/// - `cursor` is in view-local coordinates (top-left origin, since the
///   cropper view is flipped). Pass `nil` to indicate "the cursor is
///   outside the cropper view."
/// - `handleSize` is the same `CGFloat` constant the view uses for hit
///   testing (currently `CropperView.handleSize = 12`).
/// - `isOverRecordButton` short-circuits to `.arrow` when true, regardless
///   of mode or location. The Record button is owned by the view, so the
///   hit-test is performed there and passed in here.
public func desiredCursor(
    at cursor: CGPoint?,
    handleSize: CGFloat,
    isOverRecordButton: Bool
) -> CropperCursor {
    if isOverRecordButton { return .arrow }
    guard cursor != nil else { return .arrow }
    switch mode {
    case .idle, .dragging:
        return .crosshair
    case .resizing, .have:
        // Filled in by Tasks 3 and 4.
        return .arrow
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter CropperStateCursorTests`
Expected: all 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/SnatchKit/UI/Cropper/CropperState.swift Tests/SnatchKitTests/CropperStateCursorTests.swift
git commit -m "feat(cropper): add desiredCursor predicate (idle + dragging cases)"
```

---

## Task 3: Implement `desiredCursor` for `.have(rect)` mode (TDD)

**Files:**
- Modify: `Sources/SnatchKit/UI/Cropper/CropperState.swift`
- Modify: `Tests/SnatchKitTests/CropperStateCursorTests.swift`

Extends `desiredCursor` to map handle hit-tests to directional cursors and the rect interior to `.grab`. Outside the rect → `.crosshair`. Cursor nil over a `.have(rect)` is already covered by the early-nil-check in Task 2's implementation, but we add an explicit test row for it (#11b in the spec).

The rect used in tests: `CGRect(x: 50, y: 50, width: 100, height: 100)`. Handle centers (from `CropperGeometry.handleFrames`):
- topLeft (50, 50), top (100, 50), topRight (150, 50)
- left (50, 100), right (150, 100)
- bottomLeft (50, 150), bottom (100, 150), bottomRight (150, 150)

- [ ] **Step 1: Add failing tests for `.have(rect)` cases**

Append to `Tests/SnatchKitTests/CropperStateCursorTests.swift`:

```swift
    // MARK: - mode == .have(rect)

    private func haveState() -> CropperState {
        CropperState(initial: CGRect(x: 50, y: 50, width: 100, height: 100))
    }

    func test_have_overTopLeft_isResizeNWSE() {
        XCTAssertEqual(
            haveState().desiredCursor(at: CGPoint(x: 50, y: 50), handleSize: handleSize, isOverRecordButton: false),
            .resizeNWSE
        )
    }

    func test_have_overBottomRight_isResizeNWSE() {
        XCTAssertEqual(
            haveState().desiredCursor(at: CGPoint(x: 150, y: 150), handleSize: handleSize, isOverRecordButton: false),
            .resizeNWSE
        )
    }

    func test_have_overTopRight_isResizeNESW() {
        XCTAssertEqual(
            haveState().desiredCursor(at: CGPoint(x: 150, y: 50), handleSize: handleSize, isOverRecordButton: false),
            .resizeNESW
        )
    }

    func test_have_overBottomLeft_isResizeNESW() {
        XCTAssertEqual(
            haveState().desiredCursor(at: CGPoint(x: 50, y: 150), handleSize: handleSize, isOverRecordButton: false),
            .resizeNESW
        )
    }

    func test_have_overTopEdge_isResizeVertical() {
        XCTAssertEqual(
            haveState().desiredCursor(at: CGPoint(x: 100, y: 50), handleSize: handleSize, isOverRecordButton: false),
            .resizeVertical
        )
    }

    func test_have_overBottomEdge_isResizeVertical() {
        XCTAssertEqual(
            haveState().desiredCursor(at: CGPoint(x: 100, y: 150), handleSize: handleSize, isOverRecordButton: false),
            .resizeVertical
        )
    }

    func test_have_overLeftEdge_isResizeHorizontal() {
        XCTAssertEqual(
            haveState().desiredCursor(at: CGPoint(x: 50, y: 100), handleSize: handleSize, isOverRecordButton: false),
            .resizeHorizontal
        )
    }

    func test_have_overRightEdge_isResizeHorizontal() {
        XCTAssertEqual(
            haveState().desiredCursor(at: CGPoint(x: 150, y: 100), handleSize: handleSize, isOverRecordButton: false),
            .resizeHorizontal
        )
    }

    func test_have_insideBody_isGrab() {
        XCTAssertEqual(
            haveState().desiredCursor(at: CGPoint(x: 100, y: 100), handleSize: handleSize, isOverRecordButton: false),
            .grab
        )
    }

    func test_have_outsideRect_isCrosshair() {
        XCTAssertEqual(
            haveState().desiredCursor(at: CGPoint(x: 10, y: 10), handleSize: handleSize, isOverRecordButton: false),
            .crosshair
        )
    }

    func test_have_cursorNil_isArrow() {
        XCTAssertEqual(
            haveState().desiredCursor(at: nil, handleSize: handleSize, isOverRecordButton: false),
            .arrow
        )
    }

    // MARK: - Record-button override

    func test_have_overRecordButton_overridesGrab() {
        // Cursor would otherwise resolve to .grab inside the rect's body.
        XCTAssertEqual(
            haveState().desiredCursor(at: CGPoint(x: 100, y: 100), handleSize: handleSize, isOverRecordButton: true),
            .arrow
        )
    }

    func test_idle_overRecordButton_isArrow() {
        // Record button is hidden in .idle, but the override still applies if true is passed.
        let s = CropperState(initial: nil)
        XCTAssertEqual(
            s.desiredCursor(at: CGPoint(x: 100, y: 100), handleSize: handleSize, isOverRecordButton: true),
            .arrow
        )
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter CropperStateCursorTests`
Expected: every new `.have` test fails with "expected X but got .arrow" (the placeholder return from Task 2).

- [ ] **Step 3: Add the `.have(rect)` branch + private helper**

In `Sources/SnatchKit/UI/Cropper/CropperState.swift`, replace the `.resizing, .have:` branch in `desiredCursor` and add a private helper:

```swift
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
    case .resizing:
        // Filled in by Task 4.
        return .arrow
    case .have(let r):
        guard let h = CropperGeometry.hitTest(point: p, in: r, handleSize: handleSize) else {
            return .crosshair
        }
        return Self.cursorFor(handle: h, gestureActive: false)
    }
}

/// Maps a hit-tested handle to its directional cursor. `gestureActive`
/// distinguishes hover (`.body` → `.grab`) from an in-progress body-move
/// (`.body` → `.grabbing`); for the 8 resize handles the result is the
/// same in both cases.
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

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter CropperStateCursorTests`
Expected: all 3 prior tests + 13 new tests pass (16 total).

- [ ] **Step 5: Commit**

```bash
git add Sources/SnatchKit/UI/Cropper/CropperState.swift Tests/SnatchKitTests/CropperStateCursorTests.swift
git commit -m "feat(cropper): desiredCursor handles .have(rect) — handles, body, outside, record-button"
```

---

## Task 4: Implement `desiredCursor` for `.resizing` mode with gesture lock (TDD)

**Files:**
- Modify: `Sources/SnatchKit/UI/Cropper/CropperState.swift`
- Modify: `Tests/SnatchKitTests/CropperStateCursorTests.swift`

`.resizing(handle, ...)` returns the cursor for `handle` regardless of where the mouse currently is. `.body` returns `.grabbing` (closed hand) since the gesture is active.

- [ ] **Step 1: Add failing tests for `.resizing` cases**

Append to `Tests/SnatchKitTests/CropperStateCursorTests.swift`:

```swift
    // MARK: - mode == .resizing (gesture lock)

    func test_resizing_body_isGrabbing_anywhere() {
        // Start with a committed rect; mouseDown inside the body drives state into .resizing(.body).
        let rect = CGRect(x: 50, y: 50, width: 100, height: 100)
        var s = CropperState(initial: rect)
        s = s.applyMouseDown(at: CGPoint(x: 100, y: 100), handleSize: handleSize)
        XCTAssertEqual(
            s.desiredCursor(at: CGPoint(x: 100, y: 100), handleSize: handleSize, isOverRecordButton: false),
            .grabbing
        )
        // Cursor wandered far off the rect — still grabbing.
        XCTAssertEqual(
            s.desiredCursor(at: CGPoint(x: 999, y: 999), handleSize: handleSize, isOverRecordButton: false),
            .grabbing
        )
    }

    func test_resizing_topLeft_isResizeNWSE_anywhere() {
        let rect = CGRect(x: 50, y: 50, width: 100, height: 100)
        var s = CropperState(initial: rect)
        s = s.applyMouseDown(at: CGPoint(x: 50, y: 50), handleSize: handleSize)
        XCTAssertEqual(
            s.desiredCursor(at: CGPoint(x: 50, y: 50), handleSize: handleSize, isOverRecordButton: false),
            .resizeNWSE
        )
        // Cursor drifts off the handle — gesture cursor stays locked.
        XCTAssertEqual(
            s.desiredCursor(at: CGPoint(x: 200, y: 200), handleSize: handleSize, isOverRecordButton: false),
            .resizeNWSE
        )
    }

    func test_resizing_leftEdge_isResizeHorizontal_anywhere() {
        let rect = CGRect(x: 50, y: 50, width: 100, height: 100)
        var s = CropperState(initial: rect)
        s = s.applyMouseDown(at: CGPoint(x: 50, y: 100), handleSize: handleSize)
        XCTAssertEqual(
            s.desiredCursor(at: CGPoint(x: 50, y: 100), handleSize: handleSize, isOverRecordButton: false),
            .resizeHorizontal
        )
        XCTAssertEqual(
            s.desiredCursor(at: CGPoint(x: 999, y: 999), handleSize: handleSize, isOverRecordButton: false),
            .resizeHorizontal
        )
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter CropperStateCursorTests`
Expected: 3 new `.resizing` tests fail with "expected X but got .arrow".

- [ ] **Step 3: Replace the `.resizing` placeholder with the gesture-lock branch**

In `Sources/SnatchKit/UI/Cropper/CropperState.swift`, replace the `.resizing` case in `desiredCursor`:

```swift
    case .resizing(let handle, _, _, _):
        return Self.cursorFor(handle: handle, gestureActive: true)
```

(The whole switch should now have no placeholders.)

- [ ] **Step 4: Run tests to verify all pass**

Run: `swift test --filter CropperStateCursorTests`
Expected: all 19 tests pass (3 idle/dragging + 13 have + 3 resizing).

- [ ] **Step 5: Commit**

```bash
git add Sources/SnatchKit/UI/Cropper/CropperState.swift Tests/SnatchKitTests/CropperStateCursorTests.swift
git commit -m "feat(cropper): desiredCursor handles .resizing with gesture-locked cursor"
```

---

## Task 5: Rewrite `shouldShowCrosshair` as a wrapper around `desiredCursor`

**Files:**
- Modify: `Sources/SnatchKit/UI/Cropper/CropperState.swift`

Existing 6 `shouldShowCrosshair` tests in `CropperStateCrosshairTests.swift` are the regression suite. They must keep passing without edits.

- [ ] **Step 1: Replace the body of `shouldShowCrosshair`**

In `Sources/SnatchKit/UI/Cropper/CropperState.swift`, replace the body of `shouldShowCrosshair(cursor:handleSize:)` with:

```swift
public func shouldShowCrosshair(cursor: CGPoint?, handleSize: CGFloat) -> Bool {
    desiredCursor(at: cursor, handleSize: handleSize, isOverRecordButton: false) == .crosshair
}
```

(Delete the old switch-statement body; keep the public signature and the doc comment intact.)

- [ ] **Step 2: Run the entire SnatchKit test suite**

Run: `swift test`
Expected: all tests pass — including the 6 `CropperStateCrosshairTests` and the 19 new `CropperStateCursorTests`. Total test count should be the prior count + 19.

- [ ] **Step 3: Commit**

```bash
git add Sources/SnatchKit/UI/Cropper/CropperState.swift
git commit -m "refactor(cropper): shouldShowCrosshair now delegates to desiredCursor"
```

---

## Task 6: Add `NSCursor+ResizeDiagonal` extension

**Files:**
- Create: `Sources/SnatchAppKit/NSCursor+ResizeDiagonal.swift`

Two computed properties on `NSCursor`, each delegating to a private static helper that calls a private AppKit selector via `NSSelectorFromString` + `responds(to:)` + `perform`. Falls back to `.resizeUpDown` if the selector is missing.

- [ ] **Step 1: Create the file**

Create `Sources/SnatchAppKit/NSCursor+ResizeDiagonal.swift`:

```swift
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
```

- [ ] **Step 2: Verify it compiles**

Run: `swift build`
Expected: builds with no warnings or errors. (No callers yet — call sites land in Task 7.)

- [ ] **Step 3: Commit**

```bash
git add Sources/SnatchAppKit/NSCursor+ResizeDiagonal.swift
git commit -m "feat(appkit): add NSCursor.resizeDiagonalNWSE/NESW via private selectors"
```

---

## Task 7: Wire `desiredCursor` into `CropperView.updateCursor()`

**Files:**
- Modify: `Sources/SnatchAppKit/CropperView.swift`

Replace the existing `updateCursor()` body (which only knows about crosshair vs. arrow + the Record-button override) with a switch over `state.desiredCursor(...)`.

- [ ] **Step 1: Replace `updateCursor()` and add `nsCursor(for:)` helper**

In `Sources/SnatchAppKit/CropperView.swift`, find the existing `updateCursor()` method:

```swift
private func updateCursor() {
    if cursorIsOverRecordButton {
        NSCursor.arrow.set()
        return
    }
    if state.shouldShowCrosshair(cursor: mouseLocation, handleSize: Self.handleSize) {
        Self.crosshairCursor.set()
    } else {
        NSCursor.arrow.set()
    }
}
```

Replace it with:

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

- [ ] **Step 2: Verify it compiles**

Run: `swift build`
Expected: builds with no warnings or errors. The CropperView now imports `CropperCursor` (already public from SnatchKit) and uses the new `NSCursor` extension (in the same target).

- [ ] **Step 3: Commit**

```bash
git add Sources/SnatchAppKit/CropperView.swift
git commit -m "feat(cropper): wire desiredCursor into CropperView.updateCursor"
```

---

## Task 8: Simplify the x/y readout pill check in `draw(_:)`

**Files:**
- Modify: `Sources/SnatchAppKit/CropperView.swift`

`desiredCursor`'s `isOverRecordButton: true` short-circuit subsumes the existing `!cursorIsOverRecordButton` clause in the pill predicate, so we can collapse the check.

- [ ] **Step 1: Update the pill-check predicate**

In `Sources/SnatchAppKit/CropperView.swift`, find the start of step 5 in `draw(_:)`:

```swift
if let cursor = mouseLocation,
   !cursorIsOverRecordButton,
   state.shouldShowCrosshair(cursor: cursor, handleSize: Self.handleSize),
   let window = window,
   let mainScreen = NSScreen.main {
```

Replace with:

```swift
if let cursor = mouseLocation,
   state.desiredCursor(
       at: cursor,
       handleSize: Self.handleSize,
       isOverRecordButton: cursorIsOverRecordButton
   ) == .crosshair,
   let window = window,
   let mainScreen = NSScreen.main {
```

(The `!cursorIsOverRecordButton` clause is removed; `desiredCursor` returns `.arrow` — not `.crosshair` — when the cursor is over the Record button.)

- [ ] **Step 2: Verify it compiles**

Run: `swift build`
Expected: builds with no warnings or errors.

- [ ] **Step 3: Run the full SnatchKit test suite**

Run: `swift test`
Expected: all tests pass, no regressions.

- [ ] **Step 4: Commit**

```bash
git add Sources/SnatchAppKit/CropperView.swift
git commit -m "refactor(cropper): simplify x/y pill check via desiredCursor"
```

---

## Task 9: Build the App target and run a manual smoke test

**Files:** none (verification only)

The cursor extension uses a private AppKit selector — verifying it works end-to-end requires running the app, not just the test suite. Run through the smoke matrix from the spec on a real cropper.

- [ ] **Step 1: Build the App target**

Run: `xcodebuild -project Snatch.xcodeproj -scheme Snatch build`
Expected: build succeeds. The resulting `.app` is the dev-signed build under `~/Library/Developer/Xcode/DerivedData/Snatch-*/Build/Products/Debug/Snatch.app`.

- [ ] **Step 2: Launch the app and trigger the cropper**

Open the built `Snatch.app`. Click the menubar icon and choose "Capture Region…" (or press ⇧⌘6).

Expected: cropper appears. If "Remember Last Capture Area" is on, you'll see the last rect; otherwise a fresh dim overlay with a crosshair cursor.

- [ ] **Step 3: Run through the cursor smoke matrix**

For each row, hover the described location and verify the cursor matches. If "Remember Last Capture Area" is off, drag a fresh rect first, then hover.

| Region | Expected cursor |
|---|---|
| Dim area outside the rect | white "+" crosshair |
| `.topLeft` handle (rect's top-left circle) | `↘↖` diagonal |
| `.topRight` handle | `↗↙` diagonal |
| `.bottomLeft` handle | `↗↙` diagonal |
| `.bottomRight` handle | `↘↖` diagonal |
| `.top` handle (top edge midpoint) | `↕` vertical |
| `.bottom` handle | `↕` vertical |
| `.left` handle | `↔` horizontal |
| `.right` handle | `↔` horizontal |
| Inside the rect, not on a handle | open hand |
| Hover over the floating Record button | arrow |

- [ ] **Step 4: Verify gesture-lock behavior**

  - Mouse-down on the `.bottomRight` handle, drag the cursor far off the handle (still holding the mouse button down). Cursor stays `↘↖` for the duration. Release. Cursor returns to whatever the post-release location dictates.
  - Mouse-down inside the rect's body, drag to move it. Cursor changes from open hand → closed hand on mouse-down, stays closed for the duration of the drag, returns to open hand (or whatever) on release.

- [ ] **Step 5: Verify the existing crosshair x/y readout still works**

Move the cursor in the dim area outside the rect — the white "+" cursor and the x/y coordinates pill should both still appear (this is the existing behavior; we're verifying we didn't break it).

Move the cursor over the Record button — both the cursor swap to arrow and the pill suppression should still work.

- [ ] **Step 6: Note any regressions**

If anything misbehaves, capture details (what action, expected vs. observed cursor) and stop here — return to fix before claiming completion. If everything matches, the manual smoke is done.

- [ ] **Step 7: No commit for this task**

Verification only. Nothing to commit.

---

## Verification summary

When all tasks are complete:

- `swift test` passes — 6 existing crosshair tests + 19 new cursor tests + everything else.
- `xcodebuild ... build` succeeds for the App target.
- All 11 cursor smoke-matrix rows match.
- Gesture lock works for both resize and body-move.
- The x/y readout pill still appears outside the rect and disappears over the Record button (existing behavior preserved).
