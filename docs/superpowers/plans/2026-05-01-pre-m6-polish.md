# Pre-M6 Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Four targeted UX refinements before M6 ship — dashed cropper preview border, small grey-rimmed circle handles, "Remember Last Capture Area" menubar toggle, and a dashed/muted recording border.

**Architecture:** Three of the four items are pure draw-call edits in `SnatchAppKit` (CropperView + RecordingOverlayWindow). The fourth — the menubar toggle — adds a new `RememberRegionPreferenceStore` in `SnatchKit/System` (parallel to the existing `ScalePresetStore`), gates the cropper pre-fill read in `MenubarCoordinator.showCropper()`, and adds one checkable menu item in `MenubarController.buildMenu()`. `RegionStore`'s persistence semantics are unchanged — toggling the new preference OFF and back ON is lossless.

**Tech Stack:** Swift 5.10, macOS 14+, AppKit (NSBezierPath, NSStatusItem, NSMenu), SwiftPM + Xcode (mixed), XCTest. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-05-01-pre-m6-polish-design.md`

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
  - Expected: `926123a docs: pre-M6 polish design`
- [ ] **Verify M5 baseline tag exists.** Run: `git tag --list m5-menubar-app`
  - Expected: prints `m5-menubar-app`
- [ ] **Verify SnatchKit tests are green.** Run: `swift test 2>&1 | tail -3`
  - Expected: `Test Suite 'All tests' passed at ...` (live-capture tests skipped without permission is OK)
- [ ] **Verify Xcode App target builds.** Run: `xcodebuild -project Snatch.xcodeproj -scheme Snatch build 2>&1 | tail -3`
  - Expected: `** BUILD SUCCEEDED **`
- [ ] **Read the spec end-to-end.** Open `docs/superpowers/specs/2026-05-01-pre-m6-polish-design.md`. The spec is the authoritative source for *what* and *why*; this plan is the authoritative source for *how* and *in what order*.

---

## File structure

### New files

| Path | Responsibility |
|---|---|
| `Sources/SnatchKit/System/RememberRegionPreferenceStore.swift` | UserDefaults-backed bool: should the cropper pre-fill with the last region? Default ON. |
| `Tests/SnatchKitTests/RememberRegionPreferenceStoreTests.swift` | XCTest coverage for the new store. |

### Modified files

| Path | Change |
|---|---|
| `App/AppDelegate.swift` | Construct `RememberRegionPreferenceStore`; pass into both `MenubarCoordinator` and `MenubarController` inits. |
| `App/MenubarCoordinator.swift` | Add `rememberRegionStore` property + init param; gate the `regionStore.lastRegion` read in `showCropper()`. |
| `App/UI/Menubar/MenubarController.swift` | Add `rememberRegionStore` property + init param; insert "Remember Last Capture Area" menu item between Scale ▸ and Recent Recordings ▸; add `toggleRememberAction`. |
| `Sources/SnatchAppKit/CropperView.swift` | Dashed white outline (`[6, 4]`); circle handles (8pt visible inside 12pt click rect, white fill + 1pt grey stroke). |
| `Sources/SnatchAppKit/RecordingOverlayWindow.swift` | `BorderOverlayView.draw`: 60% alpha red, dashed `[6, 4]`. |

### Untouched

`Sources/SnatchKit/System/RegionStore.swift` — unchanged. It keeps reading and writing unconditionally; the toggle gates the *consumer* (MenubarCoordinator), not the store.

`Sources/SnatchKit/UI/Cropper/CropperGeometry.swift`, `CropperState.swift`, `CropperHandle.swift` — unchanged. Click-target rects and hit-test math are not modified.

---

## Task 1: `RememberRegionPreferenceStore` + tests (TDD)

**Files:**
- Create: `Sources/SnatchKit/System/RememberRegionPreferenceStore.swift`
- Test: `Tests/SnatchKitTests/RememberRegionPreferenceStoreTests.swift`

- [ ] **Step 1: Write the failing test file**

Create `Tests/SnatchKitTests/RememberRegionPreferenceStoreTests.swift` with the following content. Mirrors `ScalePresetStoreTests` structure — isolated `UserDefaults` per test via a UUID-suffixed suite name.

```swift
import XCTest
@testable import SnatchKit

final class RememberRegionPreferenceStoreTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "co.snatch.tests.RememberRegion.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults?.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func test_isEnabled_defaultsToTrue_whenUnset() {
        let store = RememberRegionPreferenceStore(defaults: defaults)
        XCTAssertTrue(store.isEnabled)
    }

    func test_setEnabled_persistsValue() {
        let store = RememberRegionPreferenceStore(defaults: defaults)
        store.setEnabled(false)
        XCTAssertFalse(store.isEnabled)
        store.setEnabled(true)
        XCTAssertTrue(store.isEnabled)
    }

    func test_persistedValue_survivesNewStoreInstance() {
        RememberRegionPreferenceStore(defaults: defaults).setEnabled(false)
        XCTAssertFalse(RememberRegionPreferenceStore(defaults: defaults).isEnabled)
    }

    func test_RememberRegionPreferenceStore_isSendable() {
        let store = RememberRegionPreferenceStore(defaults: defaults)
        Self._requireSendable(store)
    }

    private static func _requireSendable<T: Sendable>(_ value: T) {}
}
```

- [ ] **Step 2: Run tests to verify they fail with "no such type"**

Run: `swift test --filter RememberRegionPreferenceStoreTests 2>&1 | tail -20`

Expected: compile error referencing `RememberRegionPreferenceStore` not being in scope.

- [ ] **Step 3: Write the minimal implementation**

Create `Sources/SnatchKit/System/RememberRegionPreferenceStore.swift`:

```swift
import Foundation

/// UserDefaults-backed bool: should the cropper pre-fill with the last
/// recorded region? Defaults to `true` (preserves M5 behavior on first launch).
///
/// Pattern parallels `ScalePresetStore`. `RegionStore` continues to read and
/// write the region unconditionally; this preference only gates the consumer
/// in `MenubarCoordinator.showCropper()`.
public final class RememberRegionPreferenceStore: @unchecked Sendable {
    // UserDefaults is documented thread-safe by Apple. All access goes
    // through `defaults.object(forKey:)` / `defaults.set(_:forKey:)`.
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "rememberRegion") {
        self.defaults = defaults
        self.key = key
    }

    public var isEnabled: Bool {
        // `object(forKey:) as? Bool` returns nil when the key is unset, so
        // the `?? true` fallback gives us "default ON on first launch."
        defaults.object(forKey: key) as? Bool ?? true
    }

    public func setEnabled(_ value: Bool) {
        defaults.set(value, forKey: key)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter RememberRegionPreferenceStoreTests 2>&1 | tail -10`

Expected: 4 tests, all pass.

- [ ] **Step 5: Run the full SnatchKit suite to verify no regressions**

Run: `swift test 2>&1 | tail -3`

Expected: `Test Suite 'All tests' passed at ...`

- [ ] **Step 6: Commit**

```bash
git add Sources/SnatchKit/System/RememberRegionPreferenceStore.swift Tests/SnatchKitTests/RememberRegionPreferenceStoreTests.swift
git commit -m "feat(system): RememberRegionPreferenceStore (default ON)"
```

---

## Task 2: Wire `RememberRegionPreferenceStore` into `MenubarCoordinator` (read gate)

**Files:**
- Modify: `App/MenubarCoordinator.swift`
- Modify: `App/AppDelegate.swift`

This task adds the property + init parameter to `MenubarCoordinator`, gates the `regionStore.lastRegion` read, and updates the `AppDelegate` call site so the project still compiles. The new menu item (Task 3) is not yet exposed to the user — toggle is unreachable but the gate is live (and will continue to default ON because the store defaults to `true`).

- [ ] **Step 1: Add the stored property + init parameter to `MenubarCoordinator`**

Open `App/MenubarCoordinator.swift`. After the existing `let scaleStore: ScalePresetStore` property declaration (around line 17), add:

```swift
    let rememberRegionStore: RememberRegionPreferenceStore
```

In the init signature (around lines 30–40), insert the parameter immediately after `scaleStore: ScalePresetStore,`:

```swift
         rememberRegionStore: RememberRegionPreferenceStore,
```

In the init body (around lines 41–52), after the existing `self.scaleStore = scaleStore` assignment, add:

```swift
        self.rememberRegionStore = rememberRegionStore
```

- [ ] **Step 2: Gate the `regionStore.lastRegion` read in `showCropper()`**

Open `App/MenubarCoordinator.swift`. Find the `showCropper()` method (around lines 131–157). Locate the existing block:

```swift
        if let last = regionStore.lastRegion {
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
```

Replace the `if let last = regionStore.lastRegion {` line with:

```swift
        if rememberRegionStore.isEnabled, let last = regionStore.lastRegion {
```

The rest of the block (the `viewLocal` computation, the `else` branch) is unchanged. When the toggle is OFF, both arms of `&&` short-circuit on the first false and we fall through to the `else` branch — same path as "no persisted region."

- [ ] **Step 3: Update `AppDelegate` to construct the store and pass it**

Open `App/AppDelegate.swift`. After the `private var scaleStore: ScalePresetStore!` property (line 15), add:

```swift
    private var rememberRegionStore: RememberRegionPreferenceStore!
```

In `applicationDidFinishLaunching`, after the line `scaleStore = ScalePresetStore()` (line 38), add:

```swift
        rememberRegionStore = RememberRegionPreferenceStore()
```

In the `MenubarCoordinator(...)` init call (lines 52–64), insert the new argument immediately after `scaleStore: scaleStore,`:

```swift
            rememberRegionStore: rememberRegionStore,
```

- [ ] **Step 4: Verify SnatchKit tests still green**

Run: `swift test 2>&1 | tail -3`

Expected: `Test Suite 'All tests' passed at ...` (no SnatchKit code changed; this confirms the new store is still happy with the rest of the suite.)

- [ ] **Step 5: Verify the Xcode App target builds**

Run: `xcodebuild -project Snatch.xcodeproj -scheme Snatch build 2>&1 | tail -3`

Expected: `** BUILD SUCCEEDED **`

If the build fails citing `MenubarController` (which we haven't updated yet), double-check Step 3 — only `MenubarCoordinator`'s init was changed in this task. `MenubarController.init` is updated in Task 3.

- [ ] **Step 6: Commit**

```bash
git add App/MenubarCoordinator.swift App/AppDelegate.swift
git commit -m "feat(coordinator): gate cropper pre-fill on RememberRegionPreferenceStore"
```

---

## Task 3: Wire `RememberRegionPreferenceStore` into `MenubarController` (menu item)

**Files:**
- Modify: `App/UI/Menubar/MenubarController.swift`
- Modify: `App/AppDelegate.swift`

- [ ] **Step 1: Add the stored property + init parameter to `MenubarController`**

Open `App/UI/Menubar/MenubarController.swift`. After the existing `private let scaleStore: ScalePresetStore` property (around line 9), add:

```swift
    private let rememberRegionStore: RememberRegionPreferenceStore
```

In the init signature (around lines 18–23), insert the parameter immediately after `scaleStore: ScalePresetStore,`:

```swift
         rememberRegionStore: RememberRegionPreferenceStore,
```

In the init body (around lines 24–29), after `self.scaleStore = scaleStore`, add:

```swift
        self.rememberRegionStore = rememberRegionStore
```

- [ ] **Step 2: Insert the menu item in `buildMenu()`**

Open `App/UI/Menubar/MenubarController.swift`. Find `buildMenu()` (starts around line 65). Locate the lines that close the Scale ▸ submenu and start the Recent Recordings ▸ submenu:

```swift
        scaleItem.submenu = scaleSub
        menu.addItem(scaleItem)

        // Recent Recordings ▸  (built lazily in menuWillOpen via delegate)
        let recentItem = NSMenuItem(title: "Recent Recordings", action: nil, keyEquivalent: "")
```

Insert the new item between `menu.addItem(scaleItem)` and the Recent Recordings comment, leaving one blank line on each side:

```swift
        scaleItem.submenu = scaleSub
        menu.addItem(scaleItem)

        let remember = NSMenuItem(
            title: "Remember Last Capture Area",
            action: #selector(toggleRememberAction),
            keyEquivalent: ""
        )
        remember.target = self
        remember.state = rememberRegionStore.isEnabled ? .on : .off
        menu.addItem(remember)

        // Recent Recordings ▸  (built lazily in menuWillOpen via delegate)
        let recentItem = NSMenuItem(title: "Recent Recordings", action: nil, keyEquivalent: "")
```

- [ ] **Step 3: Add the action handler**

Still in `App/UI/Menubar/MenubarController.swift`, in the `@objc private func` block (after `setScaleAction` and before `aboutAction`, around line 126), add:

```swift
    @objc private func toggleRememberAction() {
        rememberRegionStore.setEnabled(!rememberRegionStore.isEnabled)
    }
```

`buildMenu()` is already invoked fresh on every status-item click (see `statusItemClicked`), so the checkmark naturally reflects current state without changes to `menuWillOpen`.

- [ ] **Step 4: Update `AppDelegate` to pass the store to `MenubarController`**

Open `App/AppDelegate.swift`. In the `MenubarController(...)` init call (around lines 74–88), insert the new argument immediately after `scaleStore: scaleStore,`:

```swift
            rememberRegionStore: rememberRegionStore,
```

- [ ] **Step 5: Verify SnatchKit tests still green**

Run: `swift test 2>&1 | tail -3`

Expected: `Test Suite 'All tests' passed at ...`

- [ ] **Step 6: Verify the Xcode App target builds**

Run: `xcodebuild -project Snatch.xcodeproj -scheme Snatch build 2>&1 | tail -3`

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
git add App/UI/Menubar/MenubarController.swift App/AppDelegate.swift
git commit -m "feat(menubar): Remember Last Capture Area toggle"
```

---

## Task 4: Cropper preview border — dashed white

**Files:**
- Modify: `Sources/SnatchAppKit/CropperView.swift`

- [ ] **Step 1: Apply the dash pattern in `draw(_:)`**

Open `Sources/SnatchAppKit/CropperView.swift`. Find step 2 of `draw(_:)` (around lines 71–75):

```swift
        // 2. Rectangle outline.
        NSColor.white.setStroke()
        let outline = NSBezierPath(rect: rect)
        outline.lineWidth = 1
        outline.stroke()
```

Replace with:

```swift
        // 2. Rectangle outline (dashed — matches macOS native screenshot tool).
        NSColor.white.setStroke()
        let outline = NSBezierPath(rect: rect)
        outline.lineWidth = 1
        outline.setLineDash([6, 4], count: 2, phase: 0)
        outline.stroke()
```

`setLineDash` is per-path state, so it does not leak to the handle ovals drawn in step 3.

- [ ] **Step 2: Verify SnatchKit tests still green**

Run: `swift test 2>&1 | tail -3`

Expected: `Test Suite 'All tests' passed at ...` (CropperView is in `SnatchAppKit`, not `SnatchKit`, so SnatchKit tests are unaffected — but we run them as a smoke check.)

- [ ] **Step 3: Verify the Xcode App target builds**

Run: `xcodebuild -project Snatch.xcodeproj -scheme Snatch build 2>&1 | tail -3`

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add Sources/SnatchAppKit/CropperView.swift
git commit -m "feat(cropper): dashed preview border"
```

---

## Task 5: Cropper handles — small grey-rimmed white circles

**Files:**
- Modify: `Sources/SnatchAppKit/CropperView.swift`

- [ ] **Step 1: Replace the handle-drawing block in `draw(_:)`**

Open `Sources/SnatchAppKit/CropperView.swift`. Find step 3 of `draw(_:)` (around lines 77–84):

```swift
        // 3. Resize handles (only when committed or while resizing — not
        //    during a fresh drag).
        if shouldShowHandles {
            NSColor.white.setFill()
            for (_, frame) in CropperGeometry.handleFrames(for: rect, handleSize: Self.handleSize) {
                NSBezierPath(rect: frame).fill()
            }
        }
```

Replace with:

```swift
        // 3. Resize handles (only when committed or while resizing — not
        //    during a fresh drag). Drawn as small white circles with a thin
        //    grey rim — matches macOS native screenshot tool. Click target
        //    stays at `Self.handleSize` (12pt); the visible oval is inset
        //    by 2pt on each side, giving an 8pt circle centered in the
        //    12pt hit zone.
        if shouldShowHandles {
            for (_, frame) in CropperGeometry.handleFrames(for: rect, handleSize: Self.handleSize) {
                let visible = frame.insetBy(dx: 2, dy: 2)
                let oval = NSBezierPath(ovalIn: visible)
                NSColor.white.setFill()
                oval.fill()
                NSColor.systemGray.setStroke()
                oval.lineWidth = 1
                oval.stroke()
            }
        }
```

`CropperGeometry.handleFrames` and `CropperState.applyMouseDown` are unchanged — hit-testing still uses the full 12pt rects.

- [ ] **Step 2: Verify SnatchKit tests still green**

Run: `swift test 2>&1 | tail -3`

Expected: `Test Suite 'All tests' passed at ...` (CropperGeometry and CropperState tests cover the hit-test geometry, which is unchanged.)

- [ ] **Step 3: Verify the Xcode App target builds**

Run: `xcodebuild -project Snatch.xcodeproj -scheme Snatch build 2>&1 | tail -3`

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add Sources/SnatchAppKit/CropperView.swift
git commit -m "feat(cropper): small grey-rimmed circle handles"
```

---

## Task 6: Recording border — dashed and dampened

**Files:**
- Modify: `Sources/SnatchAppKit/RecordingOverlayWindow.swift`

- [ ] **Step 1: Update `BorderOverlayView.draw(_:)`**

Open `Sources/SnatchAppKit/RecordingOverlayWindow.swift`. Find `BorderOverlayView.draw(_:)` (around lines 134–144):

```swift
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.systemRed.setStroke()
        let stroked = regionInViewCoords.insetBy(
            dx: RecordingOverlayWindow.borderWidth / 2,
            dy: RecordingOverlayWindow.borderWidth / 2
        )
        let path = NSBezierPath(rect: stroked)
        path.lineWidth = RecordingOverlayWindow.borderWidth
        path.stroke()
    }
```

Replace with:

```swift
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // Muted red + dashed: ambient feedback while recording, not an
        // alarm. 60% alpha keeps "you are recording" readable at a glance
        // without being visually loud while you work in the captured app.
        // Dash pattern matches the cropper for visual consistency.
        NSColor.systemRed.withAlphaComponent(0.6).setStroke()
        let stroked = regionInViewCoords.insetBy(
            dx: RecordingOverlayWindow.borderWidth / 2,
            dy: RecordingOverlayWindow.borderWidth / 2
        )
        let path = NSBezierPath(rect: stroked)
        path.lineWidth = RecordingOverlayWindow.borderWidth
        path.setLineDash([6, 4], count: 2, phase: 0)
        path.stroke()
    }
```

Width and inset arithmetic are unchanged.

- [ ] **Step 2: Verify SnatchKit tests still green**

Run: `swift test 2>&1 | tail -3`

Expected: `Test Suite 'All tests' passed at ...`

- [ ] **Step 3: Verify the Xcode App target builds**

Run: `xcodebuild -project Snatch.xcodeproj -scheme Snatch build 2>&1 | tail -3`

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add Sources/SnatchAppKit/RecordingOverlayWindow.swift
git commit -m "feat(overlay): dashed muted-red recording border"
```

---

## Task 7: Manual smoke test (pre-M6 gate)

**Files:** none — this task is human-driven verification.

This gate confirms all four refinements work end-to-end on real hardware. A subagent **must not** mark this task complete; surface it to the human operator.

- [ ] **Step 1: Build and launch the App**

Easiest path: open `Snatch.xcodeproj` in Xcode and press ⌘R. Alternatively, run:

```bash
xcodebuild -project Snatch.xcodeproj -scheme Snatch build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`. Then locate `Snatch.app` in DerivedData (Xcode → Product → Show Build Folder in Finder) and double-click to launch.

Expected: Snatch icon appears in the menubar; no console crashes.

- [ ] **Step 2: Trigger cropper, verify visuals**

Press ⇧⌘6.
- [ ] Cropper appears.
- [ ] Drag to select a region. Border around the selection is **dashed white** (not solid).
- [ ] Resize handles at the 8 anchor points are **small white circles with a thin grey rim** (not squares, not pure white).
- [ ] Resize a handle by dragging — handle hit-testing still feels easy (12pt click target preserved).

- [ ] **Step 3: Record and verify recording-border visuals**

Click Record (or press Space).
- [ ] Red border surrounds the captured region.
- [ ] Border is **dashed** (not solid).
- [ ] Red is **visibly muted** (≈60% alpha, not full saturation) — not as loud as the M5 baseline.
- [ ] Click Stop. GIF is saved to Desktop.

- [ ] **Step 4: Verify the menubar toggle exists and is checked by default**

Click the Snatch menubar icon.
- [ ] Menu shows: Start Recording → Scale ▸ → **Remember Last Capture Area** → Recent Recordings ▸ → About Snatch → Quit Snatch.
- [ ] "Remember Last Capture Area" has a **checkmark** (default ON).

- [ ] **Step 5: Verify pre-fill behavior with toggle ON**

Press ⇧⌘6.
- [ ] Cropper opens with the **previous region pre-filled** (dashed outline visible immediately).

Press Esc to dismiss.

- [ ] **Step 6: Toggle OFF and verify blank cropper**

Click the Snatch menubar icon → click "Remember Last Capture Area" to toggle OFF.

Click the Snatch menubar icon again.
- [ ] No checkmark next to "Remember Last Capture Area".

Press ⇧⌘6.
- [ ] Cropper opens **blank** (full dim, no rectangle visible until you drag).

Press Esc to dismiss.

- [ ] **Step 7: Verify persistence across relaunch**

Click the Snatch menubar icon → Quit Snatch.

Re-launch (open the .app from Step 1 again).

Click the Snatch menubar icon.
- [ ] "Remember Last Capture Area" is still **unchecked** (toggle persisted).

Press ⇧⌘6.
- [ ] Cropper opens **blank** (no pre-fill, even though `RegionStore` still holds the prior region).

- [ ] **Step 8: Verify losslessness — toggle ON restores the prior region**

Click the Snatch menubar icon → click "Remember Last Capture Area" to toggle ON.

Press ⇧⌘6.
- [ ] Cropper opens with the **previously recorded region pre-filled** — the rect that was recorded before the toggle was ever turned off. (Proves `RegionStore` was untouched while the toggle was OFF.)

- [ ] **Step 9: Sign-off**

If all 8 prior steps pass, this gate is complete. Update `CLAUDE.md` "Status" section to add a "Pre-M6 polish ✅ Complete" line, then commit.

If any step fails, **do not** advance to M6. Surface the failure mode to the human operator and decide whether to fix forward or revert the offending task's commit.

---

## Self-review checklist (for the plan author, not the executor)

This section is a record that the plan was self-reviewed against the spec. If you are the executor, ignore this section and start at Task 1.

- **Spec coverage:**
  - Spec Item 1 (cropper dashed border) → Task 4. ✓
  - Spec Item 2 (small circle handles) → Task 5. ✓
  - Spec Item 3 (Remember toggle): 3a store → Task 1; 3b read gate → Task 2; 3c menu item → Task 3; 3d AppDelegate wiring → Tasks 2 & 3. ✓
  - Spec Item 4 (recording border) → Task 6. ✓
  - Spec testing (`RememberRegionPreferenceStoreTests`) → Task 1. ✓
  - Spec testing (manual smoke) → Task 7. ✓
- **Placeholder scan:** No TBDs / TODOs / "fill in later". All steps contain actual code, exact file paths, and exact commands.
- **Type consistency:** `RememberRegionPreferenceStore`, `isEnabled`, `setEnabled(_:)`, key `"rememberRegion"`, default `?? true`, init param name `rememberRegionStore` — used identically across spec and Tasks 1, 2, 3.
- **Scope:** ~30 lines of Swift across 5 modified files + 1 new ~25-line store + 1 new test file. Single milestone-sized polish pass. No decomposition needed.
