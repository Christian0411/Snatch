# Pre-M6 Tweaks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Three small UX refinements before M6 (notarize + ship): a crosshair cursor with live x/y readout in cropper selection mode, an "Auto-Start Recording on Selection" menubar toggle gated on Remember Last Capture Area being OFF, and higher-contrast Record / Stop buttons.

**Architecture:** Tweak 1 adds one pure predicate method to `CropperState` (in `SnatchKit`, unit-tested) and uses it from `CropperView` (in `SnatchAppKit`) to drive a programmatic `NSCursor` swap and a screen-space x/y label drawn by the view. Tweak 2 adds `AutoStartRecordingPreferenceStore` paralleling `RememberRegionPreferenceStore`, plus one menu item, one read gate in `MenubarCoordinator.showCropper()`, and a new `autoStartOnCommit` flag on `CropperView` that triggers `onRecord(rect)` directly from `mouseUp`. Tweak 3 replaces the stock `bezelStyle = .rounded` look on both buttons with custom `draw(_:)` calls that fill an opaque dark pill behind the title.

**Tech Stack:** Swift 5.10, macOS 14+, AppKit (`NSBezierPath`, `NSCursor`, `NSImage`, `NSTrackingArea`, `NSStatusItem`, `NSMenu`, `NSButton`), SwiftPM + Xcode (mixed), XCTest. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-05-01-pre-m6-tweaks-design.md`

**Workflow constraints (from prior sessions, do not deviate):**
- Work directly on `main`. **No git worktree.**
- Subagents must NOT run `git checkout`, `git switch`, `git reset --hard`, `git stash`, or any other destructive git command. Read-only inspection (`git log`, `git diff`, `git show`, `git status`) only. If state recovery is needed, surface it to the human; do not self-heal.
- Manual smoke gates require a human at the keyboard.

---

## Pre-flight verification

Before starting Task 1, the executing agent must verify clean baseline state:

- [ ] **Verify branch.** Run: `git rev-parse --abbrev-ref HEAD`
  - Expected: `main`
- [ ] **Verify clean tree.** Run: `git status --porcelain`
  - Expected: empty output (no modified or untracked files)
- [ ] **Verify HEAD is the spec commit.** Run: `git log -1 --oneline`
  - Expected: `bc178ef docs: pre-M6 tweaks design (crosshair, auto-start, button contrast)`
- [ ] **Verify M5 baseline tag exists.** Run: `git tag --list m5-menubar-app`
  - Expected: prints `m5-menubar-app`
- [ ] **Verify SnatchKit tests are green.** Run: `swift test 2>&1 | tail -3`
  - Expected: `Test Suite 'All tests' passed at ...` (live-capture tests skipped without permission is OK)
- [ ] **Verify Xcode App target builds.** Run: `xcodebuild -project Snatch.xcodeproj -scheme Snatch build 2>&1 | tail -3`
  - Expected: `** BUILD SUCCEEDED **`
- [ ] **Read the spec end-to-end.** Open `docs/superpowers/specs/2026-05-01-pre-m6-tweaks-design.md`. The spec is the authoritative source for *what* and *why*; this plan is the authoritative source for *how* and *in what order*.

---

## File structure

### New files

| Path | Responsibility |
|---|---|
| `Sources/SnatchKit/System/AutoStartRecordingPreferenceStore.swift` | UserDefaults-backed bool: should the cropper auto-fire `onRecord` on `mouseUp` commit? Default OFF. |
| `Tests/SnatchKitTests/AutoStartRecordingPreferenceStoreTests.swift` | XCTest coverage for the new store (4 tests, mirrors `RememberRegionPreferenceStoreTests`). |
| `Tests/SnatchKitTests/CropperStateCrosshairTests.swift` | XCTest coverage for the new `CropperState.shouldShowCrosshair(cursor:handleSize:)` predicate (7 tests). |

### Modified files

| Path | Change |
|---|---|
| `Sources/SnatchKit/UI/Cropper/CropperState.swift` | Add `public func shouldShowCrosshair(cursor:handleSize:) -> Bool`. |
| `Sources/SnatchAppKit/CropperView.swift` | Tracking area + `mouseLocation` storage + `mouseMoved` / `mouseExited` / `cursorUpdate` overrides + programmatic crosshair `NSCursor` + x/y label drawing in `draw(_:)` (new step 5) + `autoStartOnCommit` flag + `onRecord` auto-fire from `mouseUp`. |
| `Sources/SnatchAppKit/CropperRecordButton.swift` | Replace `bezelStyle = .rounded` styling with custom `draw(_:)` (dark pill + pressed-state alpha shift). |
| `Sources/SnatchAppKit/RecordingStopButton.swift` | Same pill treatment as `CropperRecordButton`; drop `.systemRed` content tint. |
| `App/AppDelegate.swift` | Construct `AutoStartRecordingPreferenceStore`; pass into both `MenubarCoordinator` and `MenubarController` inits. |
| `App/MenubarCoordinator.swift` | Add `autoStartStore` property + init param; in `showCropper()`, set `cropperWindow.cropperView.autoStartOnCommit = !rememberRegionStore.isEnabled && autoStartStore.isEnabled`. |
| `App/UI/Menubar/MenubarController.swift` | Add `autoStartStore` property + init param; insert "Auto-Start Recording on Selection" menu item directly after "Remember Last Capture Area"; set `isEnabled = !rememberRegionStore.isEnabled` on the new item; add `toggleAutoStartAction`. |

### Untouched (verify by inspection if anything looks off)

- `Sources/SnatchKit/System/RegionStore.swift` — unchanged.
- `Sources/SnatchKit/System/RememberRegionPreferenceStore.swift` — unchanged.
- `Sources/SnatchKit/UI/Cropper/CropperGeometry.swift`, `CropperHandle.swift` — unchanged. `CropperState.applyMouseDown/Dragged/Up` are unchanged; only a *new* method is added.
- `Sources/SnatchAppKit/CropperWindow.swift` — already has `acceptsMouseMovedEvents = true` at line 33. **No edit required**, only verification (Task 4 step 1).
- `Sources/SnatchAppKit/RecordingOverlayWindow.swift` — unchanged.

---

## Task 1: `CropperState.shouldShowCrosshair` predicate + tests (TDD)

**Files:**
- Test: `Tests/SnatchKitTests/CropperStateCrosshairTests.swift` (new)
- Modify: `Sources/SnatchKit/UI/Cropper/CropperState.swift`

This task adds a pure predicate method to `CropperState` so the visibility logic is unit-testable independent of AppKit. `CropperView` will delegate to it in Task 4.

- [ ] **Step 1: Write the failing test file**

Create `Tests/SnatchKitTests/CropperStateCrosshairTests.swift`:

```swift
import XCTest
@testable import SnatchKit

final class CropperStateCrosshairTests: XCTestCase {

    private let handleSize: CGFloat = 12

    // MARK: - mode == .idle

    func test_idle_alwaysShows_whenCursorPresent() {
        let s = CropperState(initial: nil)
        XCTAssertTrue(s.shouldShowCrosshair(cursor: CGPoint(x: 50, y: 50), handleSize: handleSize))
    }

    func test_idle_doesNotShow_whenCursorIsNil() {
        let s = CropperState(initial: nil)
        XCTAssertFalse(s.shouldShowCrosshair(cursor: nil, handleSize: handleSize))
    }

    // MARK: - mode == .have(rect)

    func test_have_outsideRect_shows() {
        let rect = CGRect(x: 100, y: 100, width: 200, height: 100)
        let s = CropperState(initial: rect)
        // Cursor far outside the rect's bounds.
        XCTAssertTrue(s.shouldShowCrosshair(cursor: CGPoint(x: 50, y: 50), handleSize: handleSize))
    }

    func test_have_insideRect_doesNotShow() {
        let rect = CGRect(x: 100, y: 100, width: 200, height: 100)
        let s = CropperState(initial: rect)
        // Center of rect — interior, not on any handle.
        XCTAssertFalse(s.shouldShowCrosshair(cursor: CGPoint(x: 200, y: 150), handleSize: handleSize))
    }

    func test_have_overHandle_doesNotShow() {
        let rect = CGRect(x: 100, y: 100, width: 200, height: 100)
        let s = CropperState(initial: rect)
        // Cursor at the topLeft handle's center (which is at rect.minX, rect.minY = (100, 100)).
        let frames = CropperGeometry.handleFrames(for: rect, handleSize: handleSize)
        let topLeftCenter = CGPoint(x: frames[.topLeft]!.midX, y: frames[.topLeft]!.midY)
        XCTAssertFalse(s.shouldShowCrosshair(cursor: topLeftCenter, handleSize: handleSize))
    }

    // MARK: - mode == .dragging / .resizing
    //
    // These modes are not constructable from public init, so we drive them
    // through the public mouse transitions to set up the right state.

    func test_dragging_alwaysShows() {
        // Start idle, mouseDown at (10,10) → state goes to .dragging(anchor:current:).
        var s = CropperState(initial: nil)
        s = s.applyMouseDown(at: CGPoint(x: 10, y: 10), handleSize: handleSize)
        // Predicate should report true regardless of where the cursor currently is.
        XCTAssertTrue(s.shouldShowCrosshair(cursor: CGPoint(x: 10, y: 10), handleSize: handleSize))
        XCTAssertTrue(s.shouldShowCrosshair(cursor: CGPoint(x: 999, y: 999), handleSize: handleSize))
    }

    func test_resizing_neverShows() {
        // Start with a committed rect; mouseDown on a handle drives state into .resizing.
        let rect = CGRect(x: 100, y: 100, width: 200, height: 100)
        let frames = CropperGeometry.handleFrames(for: rect, handleSize: handleSize)
        let bottomRight = CGPoint(x: frames[.bottomRight]!.midX, y: frames[.bottomRight]!.midY)

        var s = CropperState(initial: rect)
        s = s.applyMouseDown(at: bottomRight, handleSize: handleSize)
        // Predicate should report false regardless of where the cursor currently is.
        XCTAssertFalse(s.shouldShowCrosshair(cursor: bottomRight, handleSize: handleSize))
        XCTAssertFalse(s.shouldShowCrosshair(cursor: CGPoint(x: 50, y: 50), handleSize: handleSize))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail with "no such method"**

Run: `swift test --filter CropperStateCrosshairTests 2>&1 | tail -20`

Expected: compile error referencing `shouldShowCrosshair` not being a member of `CropperState`.

- [ ] **Step 3: Add the predicate to `CropperState`**

Open `Sources/SnatchKit/UI/Cropper/CropperState.swift`. After the `committedRect` computed property (currently around lines 50–54) and before the `// MARK: - Transitions` line (around line 56), insert:

```swift
    // MARK: - Crosshair visibility

    /// Should the cropper show a crosshair cursor + coordinate readout right
    /// now? The predicate captures "a click would start a fresh drag, OR the
    /// user is currently drawing one." See pre-M6 tweaks spec, Item 1.
    ///
    /// - `cursor` is in view-local coordinates (top-left origin, since the
    ///   cropper view is flipped). Pass `nil` to indicate "the cursor is
    ///   outside the cropper view" (e.g. the user moved to another display).
    /// - `handleSize` is the same `CGFloat` constant the view uses for hit
    ///   testing (currently `CropperView.handleSize = 12`).
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

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter CropperStateCrosshairTests 2>&1 | tail -10`

Expected: 7 tests, all pass.

- [ ] **Step 5: Run the full SnatchKit suite to verify no regressions**

Run: `swift test 2>&1 | tail -3`

Expected: `Test Suite 'All tests' passed at ...`

- [ ] **Step 6: Commit**

```bash
git add Sources/SnatchKit/UI/Cropper/CropperState.swift Tests/SnatchKitTests/CropperStateCrosshairTests.swift
git commit -m "feat(cropper): CropperState.shouldShowCrosshair predicate"
```

---

## Task 2: `AutoStartRecordingPreferenceStore` + tests (TDD)

**Files:**
- Test: `Tests/SnatchKitTests/AutoStartRecordingPreferenceStoreTests.swift` (new)
- Create: `Sources/SnatchKit/System/AutoStartRecordingPreferenceStore.swift` (new)

Mirrors `RememberRegionPreferenceStore` pattern; only meaningful diffs are the default value (`false` instead of `true`) and the UserDefaults key (`"autoStartOnSelection"`).

- [ ] **Step 1: Write the failing test file**

Create `Tests/SnatchKitTests/AutoStartRecordingPreferenceStoreTests.swift`:

```swift
import XCTest
@testable import SnatchKit

final class AutoStartRecordingPreferenceStoreTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "co.snatch.tests.AutoStart.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults?.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func test_isEnabled_defaultsToFalse_whenUnset() {
        let store = AutoStartRecordingPreferenceStore(defaults: defaults)
        XCTAssertFalse(store.isEnabled)
    }

    func test_setEnabled_persistsValue() {
        let store = AutoStartRecordingPreferenceStore(defaults: defaults)
        store.setEnabled(true)
        XCTAssertTrue(store.isEnabled)
        store.setEnabled(false)
        XCTAssertFalse(store.isEnabled)
    }

    func test_persistedValue_survivesNewStoreInstance() {
        AutoStartRecordingPreferenceStore(defaults: defaults).setEnabled(true)
        XCTAssertTrue(AutoStartRecordingPreferenceStore(defaults: defaults).isEnabled)
    }

    func test_AutoStartRecordingPreferenceStore_isSendable() {
        let store = AutoStartRecordingPreferenceStore(defaults: defaults)
        Self._requireSendable(store)
    }

    private static func _requireSendable<T: Sendable>(_ value: T) {}
}
```

- [ ] **Step 2: Run tests to verify they fail with "no such type"**

Run: `swift test --filter AutoStartRecordingPreferenceStoreTests 2>&1 | tail -20`

Expected: compile error referencing `AutoStartRecordingPreferenceStore` not being in scope.

- [ ] **Step 3: Write the minimal implementation**

Create `Sources/SnatchKit/System/AutoStartRecordingPreferenceStore.swift`:

```swift
import Foundation

/// UserDefaults-backed bool: should the cropper auto-fire `onRecord` the
/// instant a fresh selection commits (i.e., on `mouseUp` from `.dragging`)?
/// Default `false` (preserves M5/pre-M6 behavior — user must click Record,
/// or press Space/Return).
///
/// Pattern parallels `RememberRegionPreferenceStore`. The runtime gate also
/// requires `RememberRegionPreferenceStore.isEnabled == false` — see
/// `MenubarCoordinator.showCropper()`.
public final class AutoStartRecordingPreferenceStore: @unchecked Sendable {
    // UserDefaults is documented thread-safe by Apple. All access goes
    // through `defaults.object(forKey:)` / `defaults.set(_:forKey:)`.
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "autoStartOnSelection") {
        self.defaults = defaults
        self.key = key
    }

    public var isEnabled: Bool {
        // `object(forKey:) as? Bool` returns nil when the key is unset, so
        // the `?? false` fallback gives us "default OFF on first launch."
        defaults.object(forKey: key) as? Bool ?? false
    }

    public func setEnabled(_ value: Bool) {
        defaults.set(value, forKey: key)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter AutoStartRecordingPreferenceStoreTests 2>&1 | tail -10`

Expected: 4 tests, all pass.

- [ ] **Step 5: Run the full SnatchKit suite to verify no regressions**

Run: `swift test 2>&1 | tail -3`

Expected: `Test Suite 'All tests' passed at ...`

- [ ] **Step 6: Commit**

```bash
git add Sources/SnatchKit/System/AutoStartRecordingPreferenceStore.swift Tests/SnatchKitTests/AutoStartRecordingPreferenceStoreTests.swift
git commit -m "feat(system): AutoStartRecordingPreferenceStore (default OFF)"
```

---

## Task 3: Wire `AutoStartRecordingPreferenceStore` through `MenubarCoordinator` and `MenubarController`

**Files:**
- Modify: `App/AppDelegate.swift`
- Modify: `App/MenubarCoordinator.swift`
- Modify: `App/UI/Menubar/MenubarController.swift`

This task plumbs the new store into both UI seams. The cropper-side flag (`autoStartOnCommit`) is read by `CropperView` in Task 4; this task only sets it. The fact that `CropperView` doesn't yet have the property is fine — Swift will compile only once Task 4 lands. **For that reason, this task and Task 4 must be implemented as one batch from a build-correctness perspective. Stage commits per step but do not run `xcodebuild` between Task 3 and Task 4 — see Step 8.**

- [ ] **Step 1: Add stored property + init parameter to `MenubarCoordinator`**

Open `App/MenubarCoordinator.swift`. After the existing `let rememberRegionStore: RememberRegionPreferenceStore` line (currently line 18), insert:

```swift
    let autoStartStore: AutoStartRecordingPreferenceStore
```

In the init signature (currently lines 31–42), insert the new parameter immediately after `rememberRegionStore: RememberRegionPreferenceStore,` (currently line 36):

```swift
         autoStartStore: AutoStartRecordingPreferenceStore,
```

In the init body (currently lines 43–55), after the existing `self.rememberRegionStore = rememberRegionStore` assignment (currently line 48), insert:

```swift
        self.autoStartStore = autoStartStore
```

- [ ] **Step 2: Set `autoStartOnCommit` in `showCropper()`**

Still in `App/MenubarCoordinator.swift`. Find `showCropper()` (currently lines 134–166). Locate the existing `if rememberRegionStore.isEnabled, let last = ...` / `else` block that ends at the closing `}` after `cropperWindow.cropperView.state = CropperState(initial: nil)` (currently line 155).

Immediately after that closing `}` (currently line 155) and before `cropperWindow.orderFrontRegardless()` (currently line 157), insert one blank line and the assignment:

```swift

        cropperWindow.cropperView.autoStartOnCommit =
            !rememberRegionStore.isEnabled && autoStartStore.isEnabled
```

The resulting block should read:

```swift
        if rememberRegionStore.isEnabled, let last = regionStore.lastRegion {
            let viewLocal = CGRect(
                x: last.origin.x - screen.frame.origin.x,
                y: last.origin.y - screen.frame.origin.y,
                width: last.width,
                height: last.height
            )
            cropperWindow.cropperView.state = CropperState(initial: viewLocal)
        } else {
            cropperWindow.cropperView.state = CropperState(initial: nil)
        }

        cropperWindow.cropperView.autoStartOnCommit =
            !rememberRegionStore.isEnabled && autoStartStore.isEnabled

        cropperWindow.orderFrontRegardless()
```

- [ ] **Step 3: Add stored property + init parameter to `MenubarController`**

Open `App/UI/Menubar/MenubarController.swift`. After the existing `private let rememberRegionStore: RememberRegionPreferenceStore` line (currently line 10), insert:

```swift
    private let autoStartStore: AutoStartRecordingPreferenceStore
```

In the init signature (currently lines 19–25), insert the new parameter immediately after `rememberRegionStore: RememberRegionPreferenceStore,` (currently line 21):

```swift
         autoStartStore: AutoStartRecordingPreferenceStore,
```

In the init body (currently lines 26–33), after `self.rememberRegionStore = rememberRegionStore` (currently line 28), insert:

```swift
        self.autoStartStore = autoStartStore
```

- [ ] **Step 4: Insert the new menu item in `buildMenu()`**

Still in `App/UI/Menubar/MenubarController.swift`. Find `buildMenu()` (starts at line 68). Locate the existing "Remember Last Capture Area" block (currently lines 92–99) — it ends with `menu.addItem(remember)`.

Immediately after `menu.addItem(remember)` (currently line 99) and before the comment `// Recent Recordings ▸  (built lazily in menuWillOpen via delegate)` (currently line 101), insert one blank line and the new block:

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

The resulting region of `buildMenu()` should read:

```swift
        let remember = NSMenuItem(
            title: "Remember Last Capture Area",
            action: #selector(toggleRememberAction),
            keyEquivalent: ""
        )
        remember.target = self
        remember.state = rememberRegionStore.isEnabled ? .on : .off
        menu.addItem(remember)

        let autoStart = NSMenuItem(
            title: "Auto-Start Recording on Selection",
            action: #selector(toggleAutoStartAction),
            keyEquivalent: ""
        )
        autoStart.target = self
        autoStart.state = autoStartStore.isEnabled ? .on : .off
        autoStart.isEnabled = !rememberRegionStore.isEnabled
        menu.addItem(autoStart)

        // Recent Recordings ▸  (built lazily in menuWillOpen via delegate)
        let recentItem = NSMenuItem(title: "Recent Recordings", action: nil, keyEquivalent: "")
```

- [ ] **Step 5: Add the `toggleAutoStartAction` handler**

Still in `App/UI/Menubar/MenubarController.swift`. Find the existing `toggleRememberAction` (currently lines 139–141). Immediately after its closing brace, insert one blank line and:

```swift

    @objc private func toggleAutoStartAction() {
        autoStartStore.setEnabled(!autoStartStore.isEnabled)
    }
```

- [ ] **Step 6: Update `AppDelegate` to construct the store and pass it**

Open `App/AppDelegate.swift`. After the existing `private var rememberRegionStore: RememberRegionPreferenceStore!` (currently line 16), insert:

```swift
    private var autoStartStore: AutoStartRecordingPreferenceStore!
```

In `applicationDidFinishLaunching`, after `rememberRegionStore = RememberRegionPreferenceStore()` (currently line 40), insert:

```swift
        autoStartStore   = AutoStartRecordingPreferenceStore()
```

In the `MenubarCoordinator(...)` init call (currently lines 54–67), insert the new argument immediately after `rememberRegionStore: rememberRegionStore,` (currently line 60):

```swift
            autoStartStore: autoStartStore,
```

In the `MenubarController(...)` init call (currently lines 77–92), insert the new argument immediately after `rememberRegionStore: rememberRegionStore,` (currently line 80):

```swift
            autoStartStore: autoStartStore,
```

- [ ] **Step 7: Verify SnatchKit tests still green**

Run: `swift test 2>&1 | tail -3`

Expected: `Test Suite 'All tests' passed at ...` (no SnatchKit code changed in this task; this confirms the new store is still happy with the rest of the suite.)

- [ ] **Step 8: Do NOT run `xcodebuild` yet**

The Xcode App target depends on `CropperView.autoStartOnCommit`, which Task 4 introduces. Running `xcodebuild` here will fail with `value of type 'CropperView' has no member 'autoStartOnCommit'`. Proceed directly to Task 4, which adds the property in step 1.

- [ ] **Step 9: Commit**

```bash
git add App/AppDelegate.swift App/MenubarCoordinator.swift App/UI/Menubar/MenubarController.swift
git commit -m "feat(menubar): Auto-Start Recording on Selection toggle + coordinator gate"
```

---

## Task 4: Crosshair cursor + x/y readout + auto-start commit on `CropperView`

**Files:**
- Modify: `Sources/SnatchAppKit/CropperView.swift`
- Verify (no edit): `Sources/SnatchAppKit/CropperWindow.swift` (`acceptsMouseMovedEvents` already present)

This task lands all of Item 1 (crosshair + label) plus the cropper-side half of Item 2 (`autoStartOnCommit` flag + auto-fire from `mouseUp`). Manual smoke verification happens in Task 6.

- [ ] **Step 1: Verify `CropperWindow` already has `acceptsMouseMovedEvents`**

Open `Sources/SnatchAppKit/CropperWindow.swift`. Confirm line 33 reads:

```swift
        self.acceptsMouseMovedEvents = true
```

If it does, no edit is required — proceed to Step 2. If it doesn't, add it inside `init` after `self.ignoresMouseEvents = false`. (This should already be present; the spec verified its existence.)

- [ ] **Step 2: Add the `autoStartOnCommit` stored property + crosshair `NSCursor` + `mouseLocation` storage**

Open `Sources/SnatchAppKit/CropperView.swift`. After the existing `public static let handleSize: CGFloat = 12` line (line 11) and before `public var onRecord:` (line 14), insert:

```swift

    /// When `true`, `mouseUp` that commits a fresh `.have(rect)` will fire
    /// `onRecord(rect)` directly — same callback path as the Record button /
    /// Space / Return. Set by `MenubarCoordinator.showCropper()` based on
    /// `RememberRegionPreferenceStore` + `AutoStartRecordingPreferenceStore`.
    public var autoStartOnCommit: Bool = false

    /// Most recent mouse position in view-local (flipped, top-left origin)
    /// coordinates. Tracked via a full-view `NSTrackingArea`; cleared on
    /// `mouseExited` so the readout disappears when the cursor leaves the
    /// cropper (e.g. crosses to another display).
    private var mouseLocation: CGPoint?

    /// Programmatic 16×16 crosshair cursor, drawn as two 1pt white lines
    /// centered at (8, 8). Shared across all cropper instances; lazily built
    /// once.
    private static let crosshairCursor: NSCursor = {
        let size = NSSize(width: 16, height: 16)
        let img = NSImage(size: size, flipped: false) { _ in
            NSColor.white.setStroke()
            let p = NSBezierPath()
            p.move(to: NSPoint(x: 8, y: 0))
            p.line(to: NSPoint(x: 8, y: 16))
            p.move(to: NSPoint(x: 0, y: 8))
            p.line(to: NSPoint(x: 16, y: 8))
            p.lineWidth = 1
            p.stroke()
            return true
        }
        return NSCursor(image: img, hotSpot: NSPoint(x: 8, y: 8))
    }()

    /// One full-view tracking area, rebuilt on every `updateTrackingAreas`
    /// (covers cropper window resize when the user moves across displays).
    private var trackingArea: NSTrackingArea?
```

- [ ] **Step 3: Override `updateTrackingAreas` to install the tracking area**

Still in `Sources/SnatchAppKit/CropperView.swift`. After the existing `public required init?(coder: NSCoder) { fatalError("not implemented") }` line (line 49), insert one blank line and:

```swift

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .cursorUpdate, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }
```

- [ ] **Step 4: Override `mouseMoved`, `mouseExited`, and `cursorUpdate`**

Still in `Sources/SnatchAppKit/CropperView.swift`. After the existing `public override func mouseUp(with event: NSEvent)` block (currently lines 125–128) and before the `private var shouldShowHandles: Bool` block (currently line 130), insert one blank line and:

```swift

    public override func mouseMoved(with event: NSEvent) {
        mouseLocation = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    public override func mouseExited(with event: NSEvent) {
        mouseLocation = nil
        needsDisplay = true
    }

    public override func cursorUpdate(with event: NSEvent) {
        if state.shouldShowCrosshair(cursor: mouseLocation, handleSize: Self.handleSize) {
            Self.crosshairCursor.set()
        } else {
            NSCursor.arrow.set()
        }
    }
```

- [ ] **Step 5: Auto-fire `onRecord` from `mouseUp` when flag is set**

Still in `Sources/SnatchAppKit/CropperView.swift`. Find `mouseUp(with:)` (currently lines 125–128). Replace its body with:

```swift
    public override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        state = state.applyMouseUp(at: p)
        if autoStartOnCommit, case .have(let rect) = state.mode {
            onRecord?(rect)
        }
    }
```

- [ ] **Step 6: Add x/y readout drawing as step 5 inside `draw(_:)`**

Still in `Sources/SnatchAppKit/CropperView.swift`. Find the end of `draw(_:)` — specifically the line `(label as NSString).draw(at: labelOrigin, withAttributes: attrs)` (currently line 110), which is the final statement of the existing step 4 (W×H label). Immediately after that line (still inside `draw(_:)`, before its closing `}` on line 111), insert one blank line and the new step 5 block:

```swift

        // 5. Crosshair x/y readout (pre-M6 tweaks Item 1). Shown alongside the
        //    custom NSCursor when `shouldShowCrosshair` is true. Numbers are
        //    in CG screen-space (top-left global origin) — matches what the
        //    macOS native screenshot tool shows. Multi-display correctness
        //    relies on the cropper window's frame.origin matching the chosen
        //    screen's frame.origin (M5 single-screen-under-cursor behavior).
        if let cursor = mouseLocation,
           state.shouldShowCrosshair(cursor: cursor, handleSize: Self.handleSize),
           let window = window,
           let mainScreen = NSScreen.main {

            // View-local (flipped, top-left) → CG screen-space (top-left global).
            let mainHeight = mainScreen.frame.height
            let cgY_screenTop = mainHeight - (window.frame.origin.y + window.frame.height)
            let cgX = Int((window.frame.origin.x + cursor.x).rounded())
            let cgY = Int((cgY_screenTop + cursor.y).rounded())

            let xStr = "\(cgX)"
            let yStr = "\(cgY)"

            let textAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.white,
            ]

            let xSize = (xStr as NSString).size(withAttributes: textAttrs)
            let ySize = (yStr as NSString).size(withAttributes: textAttrs)
            let textW = max(xSize.width, ySize.width)
            let textH = xSize.height + ySize.height
            let pad: CGFloat = 4
            let pillW = textW + pad * 2
            let pillH = textH + pad * 2

            // Default placement: bottom-right of cursor, 12pt offset.
            var pillX = cursor.x + 12
            var pillY = cursor.y + 12
            // Edge-flip: keep the pill inside the view bounds.
            if pillX + pillW > bounds.width {
                pillX = cursor.x - 12 - pillW
            }
            if pillY + pillH > bounds.height {
                pillY = cursor.y - 12 - pillH
            }

            let pillRect = CGRect(x: pillX, y: pillY, width: pillW, height: pillH)
            NSColor.black.withAlphaComponent(0.7).setFill()
            NSBezierPath(roundedRect: pillRect, xRadius: 6, yRadius: 6).fill()

            // Numbers stacked, left-aligned inside the pill.
            (xStr as NSString).draw(
                at: CGPoint(x: pillX + pad, y: pillY + pad),
                withAttributes: textAttrs
            )
            (yStr as NSString).draw(
                at: CGPoint(x: pillX + pad, y: pillY + pad + xSize.height),
                withAttributes: textAttrs
            )
        }
```

- [ ] **Step 7: Verify SnatchKit tests still green**

Run: `swift test 2>&1 | tail -3`

Expected: `Test Suite 'All tests' passed at ...` (CropperView lives in `SnatchAppKit`; SnatchKit tests are unaffected, but we run them as a smoke check.)

- [ ] **Step 8: Verify the Xcode App target builds**

Run: `xcodebuild -project Snatch.xcodeproj -scheme Snatch build 2>&1 | tail -3`

Expected: `** BUILD SUCCEEDED **`. (Task 3's `cropperWindow.cropperView.autoStartOnCommit = ...` reference now resolves against the new property.)

If the build fails citing `autoStartOnCommit`, double-check Step 2 — the property must be `public var autoStartOnCommit: Bool = false`. If it fails citing `shouldShowCrosshair`, ensure Task 1 was committed (the predicate lives in `SnatchKit`).

- [ ] **Step 9: Commit**

```bash
git add Sources/SnatchAppKit/CropperView.swift
git commit -m "feat(cropper): crosshair cursor + x/y readout + auto-start commit"
```

---

## Task 5: Higher-contrast Record / Stop buttons

**Files:**
- Modify: `Sources/SnatchAppKit/CropperRecordButton.swift`
- Modify: `Sources/SnatchAppKit/RecordingStopButton.swift`

Both buttons become custom-drawn pills: solid dark translucent background (70% black, 85% while pressed), white 13pt semibold title, no border, 6pt corner radius. Same 88×28 footprint, same callsite layout. Stop drops its `.systemRed` content tint (the dashed muted-red border around the captured region carries the "you're recording" signal — pre-M6 polish item 4).

- [ ] **Step 1: Replace `CropperRecordButton` body**

Open `Sources/SnatchAppKit/CropperRecordButton.swift`. Replace the entire file contents with:

```swift
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
```

- [ ] **Step 2: Replace `RecordingStopButton` body**

Open `Sources/SnatchAppKit/RecordingStopButton.swift`. Replace the entire file contents with:

```swift
// Sources/SnatchAppKit/RecordingStopButton.swift
import AppKit

/// Pill-shaped "Stop" button rendered next to the recording overlay rectangle.
/// Custom-drawn for visibility against arbitrary app backgrounds — see pre-M6
/// tweaks spec, Item 3. Matches `CropperRecordButton` styling exactly; the
/// dashed muted-red border around the captured region (pre-M6 polish item 4)
/// carries the "you're recording" signal so the button itself stays calm.
final class RecordingStopButton: NSButton {

    static let preferredSize = CGSize(width: 88, height: 28)
    static let cornerRadius: CGFloat = 6

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.title = "Stop"
        self.isBordered = false
        self.bezelStyle = .regularSquare
        self.wantsLayer = true
        self.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        self.contentTintColor = .white
        self.keyEquivalent = "" // No accelerator — overlay window doesn't take key focus.
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
        super.draw(dirtyRect)
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }
}
```

- [ ] **Step 3: Verify SnatchKit tests still green**

Run: `swift test 2>&1 | tail -3`

Expected: `Test Suite 'All tests' passed at ...`

- [ ] **Step 4: Verify the Xcode App target builds**

Run: `xcodebuild -project Snatch.xcodeproj -scheme Snatch build 2>&1 | tail -3`

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add Sources/SnatchAppKit/CropperRecordButton.swift Sources/SnatchAppKit/RecordingStopButton.swift
git commit -m "feat(buttons): high-contrast dark pill Record/Stop buttons"
```

---

## Task 6: Manual smoke test (pre-M6 gate)

**Files:** none — this task is human-driven verification.

This gate confirms all three tweaks work end-to-end on real hardware. A subagent **must not** mark this task complete; surface it to the human operator.

- [ ] **Step 1: Build and launch the App**

Easiest path: open `Snatch.xcodeproj` in Xcode and press ⌘R. Alternatively, run:

```bash
xcodebuild -project Snatch.xcodeproj -scheme Snatch build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`. Then locate `Snatch.app` in DerivedData (Xcode → Product → Show Build Folder in Finder) and double-click to launch.

Expected: Snatch icon appears in the menubar; no console crashes.

- [ ] **Step 2: Crosshair — idle / dragging**

Press ⇧⌘6.
- [ ] Cropper appears blank (or with the prior region pre-filled, depending on Remember toggle state — either is fine for this step).
- [ ] Cursor is a small white `+` (not the default arrow).
- [ ] An x/y label follows the cursor at bottom-right offset, two numbers stacked left-aligned, dark pill background.
- [ ] Numbers update smoothly as the cursor moves.
- [ ] Move cursor near the right and bottom screen edges — the label flips left and/or up so it never clips off the cropper.

- [ ] **Step 3: Crosshair — coord accuracy**

With the cursor visible in the Snatch cropper, take note of an x/y reading. Then press Esc, hit ⇧⌘4 (macOS native screenshot region tool), and hover the same physical pixel.
- [ ] The two readings should match (within ±1 due to rounding).

Press Esc again to dismiss the screenshot tool. Re-trigger Snatch with ⇧⌘6.

- [ ] **Step 4: Crosshair — drag persistence**

Drag a region inside the Snatch cropper.
- [ ] During the drag, the crosshair + x/y label persist (showing live coords on the moving corner).
- [ ] The existing W×H dimensions label still appears at the rect's top-left.

- [ ] **Step 5: Crosshair — visibility transitions**

Release the mouse to enter `.have(rect)`. Move the cursor inside the rect (not on a handle).
- [ ] Cursor reverts to the default arrow.
- [ ] The x/y label disappears.

Move the cursor outside the rect.
- [ ] Crosshair `+` returns; x/y label reappears.

Hover any of the 8 resize handles (white circles at corners + edge midpoints).
- [ ] Cursor reverts to the default arrow over each handle.

- [ ] **Step 6: Crosshair — resize**

Click and drag a handle to resize the rect.
- [ ] Throughout the resize gesture, the cursor stays as the default arrow (no crosshair).
- [ ] No x/y label is drawn.

Release to land back in `.have(rect)`. Press Esc to dismiss the cropper.

- [ ] **Step 7: Auto-Start menu — disabled when Remember is ON**

Click the Snatch menubar icon. Confirm "Remember Last Capture Area" is checked (default ON). If it isn't, click it once to turn it on, then re-open the menu.
- [ ] Menu shows: Start Recording → Scale ▸ → Remember Last Capture Area ✓ → **Auto-Start Recording on Selection (greyed out)** → Recent Recordings ▸ → About Snatch → Quit Snatch.
- [ ] Clicking the greyed "Auto-Start Recording on Selection" item does nothing.

- [ ] **Step 8: Auto-Start menu — enabled when Remember is OFF**

Click "Remember Last Capture Area" to toggle it OFF. Re-open the menubar.
- [ ] "Auto-Start Recording on Selection" is now **enabled** (clickable, unchecked).

Click "Auto-Start Recording on Selection" to toggle it ON. Re-open the menubar.
- [ ] "Auto-Start Recording on Selection" now has a checkmark.

- [ ] **Step 9: Auto-Start firing**

Press ⇧⌘6.
- [ ] Cropper opens **blank** (no pre-fill, since Remember is OFF).

Drag a region.
- [ ] On `mouseUp` (release), recording starts **immediately** — the cropper closes, the dashed muted-red border appears around the dragged region, the menubar icon turns red.

Click Stop (or hit ⇧⌘6).
- [ ] GIF saves to Desktop, notification appears.

- [ ] **Step 10: Auto-Start OFF still uses Record button**

Open the menubar, toggle Auto-Start OFF (Remember stays OFF). Press ⇧⌘6.
- [ ] Cropper opens blank. Drag a region.
- [ ] Recording does **not** auto-start. The Record button appears, and you must click it (or press Space/Return) to begin recording.

Click Esc to dismiss.

- [ ] **Step 11: Persistence across relaunch**

Quit Snatch (menubar → Quit Snatch). Re-launch.
- [ ] Open menubar — Remember is still OFF, Auto-Start is still OFF (or whatever you last set them to).

Toggle both back to your preferred state.

- [ ] **Step 12: Higher-contrast buttons — Record**

Press ⇧⌘6 (with Remember OFF, Auto-Start OFF). Drag a region.
- [ ] The Record button is a solid dark pill (charcoal-ish) with crisp white "Record" text — readable against any wallpaper.

Click and hold the Record button (don't release yet).
- [ ] The pill background visibly darkens (`isHighlighted` pressed state).

Release to begin recording.

- [ ] **Step 13: Higher-contrast buttons — Stop**

While recording, look at the Stop button on the recording overlay.
- [ ] The Stop button has the same dark pill treatment with white "Stop" text — readable against the underlying app, no red tint.
- [ ] Click and hold to confirm pressed state darkens.

Release to stop the recording. GIF saves.

- [ ] **Step 14: Sign-off**

If all 13 prior steps pass, this gate is complete. Update `CLAUDE.md` "Status" section to add a "Pre-M6 tweaks ✅ Complete" line, then commit.

If any step fails, **do not** advance to M6. Surface the failure mode to the human operator and decide whether to fix forward or revert the offending task's commit.

---

## Self-review checklist (for the plan author, not the executor)

This section is a record that the plan was self-reviewed against the spec. If you are the executor, ignore this section and start at Task 1.

- **Spec coverage:**
  - Spec Item 1 (crosshair + readout) — predicate → Task 1; cursor + label + tracking → Task 4. ✓
  - Spec Item 2 (Auto-Start toggle): 2a store → Task 2; 2b coordinator gate → Task 3 step 2; 2c menu item → Task 3 steps 4–5; 2d AppDelegate wiring → Task 3 step 6; cropper-side `autoStartOnCommit` flag + `mouseUp` auto-fire → Task 4 steps 2 + 5. ✓
  - Spec Item 3 (button restyle) — Task 5. ✓
  - Spec testing (`AutoStartRecordingPreferenceStoreTests`) → Task 2. ✓
  - Spec testing (`CropperStateCrosshairTests`) → Task 1. ✓
  - Spec testing (manual smoke) → Task 6. ✓
- **Placeholder scan:** No TBDs / TODOs / "fill in later". All steps contain actual code, exact file paths, and exact commands.
- **Type consistency:**
  - `AutoStartRecordingPreferenceStore`, `isEnabled`, `setEnabled(_:)`, key `"autoStartOnSelection"`, default `?? false`, init param `autoStartStore` — used identically across spec and Tasks 2, 3.
  - `CropperState.shouldShowCrosshair(cursor:handleSize:)` — same signature in Task 1 (def + tests) and Task 4 (callers in `cursorUpdate` and `draw(_:)`).
  - `CropperView.autoStartOnCommit` — declared in Task 4 step 2, written by Task 3 step 2, read by Task 4 step 5.
  - `CropperRecordButton` / `RecordingStopButton` — same `preferredSize` (88×28), same `cornerRadius` (6), same alpha values (0.7 / 0.85), same font weight (semibold 13pt) in spec and Task 5.
- **Build-correctness ordering:** Task 3 introduces `cropperView.autoStartOnCommit = ...` which doesn't exist until Task 4. Plan flags this in Task 3 Step 8 (do NOT run xcodebuild between 3 and 4) and verifies the App target builds in Task 4 Step 8. ✓
- **Scope:** ~150 lines of Swift across 5 modified files + 1 new ~25-line store + 2 new test files. Single milestone-sized polish pass. No decomposition needed.
