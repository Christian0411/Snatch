# Snatch M3 — Cropper UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the transparent full-screen cropper overlay. User drags a rectangle, resizes it via 8 handles or moves it bodily, sees a live `W × H` label, and either confirms with **Record** / Space / Enter (region persisted; rectangle written to stdout for M4 to wire up) or cancels with Esc. No capture, no encoding, no menubar — those land at M4/M5.

**Architecture:** Two-layer split. *Pure logic* (`CropperHandle`, `CropperGeometry`, `CropperState`, `RegionStore`) lives in `SnatchKit` so it's exercised under `swift test` with no UI dependencies — this is the bulk of M3's verifiable correctness. *AppKit shell* (`CropperWindow`, `CropperView`, `CropperRecordButton`, `AppDelegate`) lives in a new `Snatch` SPM executable target and is smoke-tested by hand per spec §9. The shell is glue: it forwards mouse / keyboard events into `CropperState` and renders whatever rect `CropperState.displayRect` returns.

**Tech Stack:** Swift 5.10, AppKit (`NSWindow`, `NSView`, `NSButton`, `NSBezierPath`), Foundation (`UserDefaults`), CoreGraphics (`CGRect` / `CGPoint` math, used in the headless-testable cropper logic), XCTest. Still Swift Package Manager — Xcode project transition deferred to M5 (see "Build system" below).

---

## Spec references

This plan implements the parts of `docs/superpowers/specs/2026-04-30-snatch-design.md` covering:
- §4 UX — cropper interactions (drag, 8 resize handles, dimensions label, Record button, Space/Enter/Esc)
- §5 Code layout (`UI/Cropper/`, `System/RegionStore`)
- §6 `CropperWindow` (transparent borderless, screen-saver level, key, full-screen dim, pre-drawn rectangle from `RegionStore.lastRegion`)
- §6 `RegionStore` (UserDefaults-backed `CGRect` persistence)
- §7 Flow 1 step 4 (cropper emits `onRecordRequested(region:)`; `RegionStore.persist(region)`)
- §7 Flow 3 cropping branch (Esc → cancel during cropping)
- §9 Testing strategy rows for `CropperWindow` (drag math + handle hit-testing — TDD; visual interaction — manual smoke) and `RegionStore` (UserDefaults isolation suite)

Out of scope for M3 (covered in later milestones):
- `RecordingSession` state machine integration — M4
- `MenubarController`, `HotkeyRegistrar`, `PasteboardWriter`, `NotificationPresenter`, `RecentRecordingsStore`, `ScalePresetStore` — M5
- Pre-warm strategy (cropper pre-instantiated and `orderOut`'d at launch, `SCShareableContent` pre-fetched, etc.) — M5
- Permissions modal — M5 (M3's executable inherits the parent terminal's screen-recording permission, but does not need it since no capture happens)
- Red-border recording overlay — M5 (lives parallel to the cropper, but only matters during `.recording`)
- Excluding cropper from SCStream capture (`SCContentFilter` exclusion list) — M4 (M3 doesn't capture)
- Xcode project + `.app` bundle — M5 (rationale below)

## Build system: stay on SPM for M3 (deferring Xcode project to M5)

Spec §3 says:

> **Phase 2 (M3+, app layer)**: One Xcode project — `Snatch.xcodeproj` — added when AppKit/SwiftUI app target is needed.

The "added when needed" qualifier is the operative phrase. Here is what M3 actually needs:

- A runnable AppKit `NSApplication` with a custom `NSWindow` shown on launch. SPM executable targets host this fine — `NSApplication.shared.run()` from `@main` is a one-line entry point and AppKit windows draw correctly without an `.app` bundle.
- A way to verify "user clicked Record → expected output". Since the spec literally says "emits 'user wants to record region X' to a console", `print` from an SPM executable + a tester reading stdout is exactly the fit.

Here is what M3 does *not* need yet:

- `LSUIElement = YES` (menubar-only, no Dock icon) — there is no menubar yet; the Dock icon during M3 is fine and helps the tester know the app is foregrounded.
- Carbon hotkey registration / `RegisterEventHotKey` — global hotkey is M5.
- `UserNotifications` framework permissions / entitlements — notifications are M5.
- Code signing / hardened runtime — required for the signed release build at M6.
- Screen Recording permission — there is no `SCStream` use in M3; permission is wired up by M2's `SCStreamWrapper` already and the cropper doesn't touch it.

All four of those *do* need an `.app` bundle, an Info.plist, entitlements, and likely a dev team — exactly the things Xcode handles natively. **Doing the Xcode transition at M5, where four bundle-shaped requirements land at once, is one transition instead of two.** Doing it at M3 forces M3 to author Info.plist + provisioning + entitlements with no immediate user of any of them.

The M3 plan therefore adds a new SPM executable target `SnatchCropperCLI` with `@main AppDelegate`. It runs via `swift run snatch-cropper-cli`. M5 will lift the `App/`, `UI/Cropper/`, and `System/RegionStore` files into the new `Snatch.xcodeproj` essentially verbatim (the file layout stays per spec §5; only the build system changes).

If a future reader disagrees and wants Xcode at M3, the swap is mechanical: create the project, add `App/AppDelegate.swift` + `UI/Cropper/*.swift` to the app target, declare `SnatchKit` as a local package dependency, retire the `SnatchCropperCLI` SPM target. Nothing in the layered design constrains the build system.

## File Structure

After M3 completes, the repo looks like (new/changed entries marked):

```
/Users/starship/src/snatch/
├── .gitignore
├── CLAUDE.md                                            (modified — Status: M3 done)
├── README.md
├── Package.swift                                        (modified — add SnatchCropperCLI target)
├── Sources/
│   ├── SnatchKit/
│   │   ├── Shared/
│   │   │   ├── RGBAFrame.swift
│   │   │   └── ScalePreset.swift
│   │   ├── Encoder/
│   │   │   └── GifskiEncoder.swift
│   │   ├── Capture/
│   │   │   ├── BridgeQueue.swift
│   │   │   ├── FrameConverter.swift
│   │   │   └── SCStreamWrapper.swift
│   │   ├── Logging/
│   │   │   └── Log.swift
│   │   ├── UI/
│   │   │   └── Cropper/
│   │   │       ├── CropperHandle.swift                  (new)
│   │   │       ├── CropperGeometry.swift                (new)
│   │   │       └── CropperState.swift                   (new)
│   │   └── System/
│   │       └── RegionStore.swift                        (new)
│   ├── SnatchCLI/
│   │   └── main.swift
│   ├── SnatchRecordCLI/
│   │   └── main.swift
│   └── SnatchCropperCLI/                                (new)
│       ├── AppDelegate.swift                            (new)
│       ├── CropperWindow.swift                          (new)
│       ├── CropperView.swift                            (new)
│       ├── CropperRecordButton.swift                    (new)
│       └── main.swift                                   (new — @main entry, NSApplication.run())
├── Tests/
│   └── SnatchKitTests/
│       ├── (existing M1/M2 test files unchanged)
│       ├── CropperHandleTests.swift                     (new)
│       ├── CropperGeometryTests.swift                   (new)
│       ├── CropperStateTests.swift                      (new)
│       └── RegionStoreTests.swift                       (new)
├── vendor/
│   └── gifski/
│       ├── libgifski.a
│       ├── gifski.h
│       └── module.modulemap
├── scripts/
│   ├── check-prereqs.sh
│   └── build-gifski.sh
└── docs/
    └── superpowers/
        ├── plans/
        │   ├── 2026-04-30-m1-encoder-smoke-test.md
        │   ├── 2026-04-30-m2-capture-pipeline.md
        │   └── 2026-04-30-m3-cropper-ui.md              (this file)
        └── specs/
            └── 2026-04-30-snatch-design.md
```

**Layering rules:**
1. `SnatchKit/UI/Cropper/` and `SnatchKit/System/RegionStore.swift` import only `Foundation` and `CoreGraphics` — **no `AppKit`**. Pure logic, headlessly testable.
2. `SnatchCropperCLI/` files are the only ones that import `AppKit`. They consume the pure types from `SnatchKit`.
3. `CropperState` does not know about `RegionStore`; the AppDelegate is the seam that loads from / persists to the store.

This split is the same testability story used for the capture pipeline in M2: pure transforms in `SnatchKit`, system-y wrapper in the executable target, smoke-tested at the seam.

## Naming convention notes

Some terminology used throughout:

- **"Region"** — a `CGRect` in global Cocoa screen coordinates. The same units that `SCStream`'s `region:` parameter takes (M2 already uses these). Origin is top-left in CG-screen-space.
- **"Display rect"** — what `CropperState.displayRect` returns, i.e. the rectangle the view should draw *right now*. May be different from the persisted region while the user is mid-drag.
- **"Handle"** — one of the 8 resize grips on the rectangle's perimeter, plus a synthetic `.body` value meaning "the user grabbed inside the rect to move it whole-cloth".
- **`handleSize`** — the click-target diameter of a handle, in points. `CropperGeometry.hitTest` takes it as a parameter so tests don't bake it in. The view supplies a constant (M3 uses 12 pt; tweak in smoke).

## Coordinate system

`CropperView` sets `isFlipped = true` so its local coords match Cocoa-screen / CG (origin top-left, y increasing downward). All `CropperGeometry` math is coordinate-system-agnostic — it operates on `CGPoint` / `CGRect` arithmetic that works the same in either orientation. The flip only matters when AppKit hands us mouse events; with `isFlipped = true`, `event.locationInWindow` in view coords lines up with `region` semantics directly.

---

## Tasks

### Task 1: Add `CropperHandle` enum + tests

The 8 resize grips plus a `.body` case for whole-rectangle drags. Pure value type, used by `CropperGeometry` and `CropperState`.

**Files:**
- Create: `Sources/SnatchKit/UI/Cropper/CropperHandle.swift`
- Create: `Tests/SnatchKitTests/CropperHandleTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/SnatchKitTests/CropperHandleTests.swift`:

```swift
import XCTest
@testable import SnatchKit

final class CropperHandleTests: XCTestCase {

    func test_resizeCases_containsAllEightCornersAndEdges_inExpectedOrder() {
        XCTAssertEqual(
            CropperHandle.resizeCases,
            [.topLeft, .top, .topRight, .left, .right, .bottomLeft, .bottom, .bottomRight]
        )
    }

    func test_resizeCases_doesNotIncludeBody() {
        XCTAssertFalse(CropperHandle.resizeCases.contains(.body))
    }

    func test_caseIterable_includesAllNineCases() {
        XCTAssertEqual(CropperHandle.allCases.count, 9)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter CropperHandleTests`
Expected: build error — `CropperHandle` is not defined.

- [ ] **Step 3: Create the enum**

Create `Sources/SnatchKit/UI/Cropper/CropperHandle.swift`:

```swift
import Foundation

/// One of the 9 grab points on a cropper rectangle: the 8 resize handles
/// arranged around the perimeter, plus `.body` meaning "the user grabbed
/// inside the rect to move it whole-cloth".
public enum CropperHandle: Hashable, Sendable, CaseIterable {
    case topLeft, top, topRight
    case left,        right
    case bottomLeft, bottom, bottomRight
    case body

    /// The 8 resize cases in clockwise-ish order (corners + edges).
    /// `body` is intentionally excluded — these are the cases that map to
    /// a rendered grip in the UI and to a directional resize behavior in
    /// `CropperGeometry.resize`.
    public static let resizeCases: [CropperHandle] = [
        .topLeft, .top, .topRight,
        .left,           .right,
        .bottomLeft, .bottom, .bottomRight,
    ]
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter CropperHandleTests`
Expected: 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/SnatchKit/UI/Cropper/CropperHandle.swift \
        Tests/SnatchKitTests/CropperHandleTests.swift
git commit -m "feat(cropper): add CropperHandle enum (8 resize cases + body)"
```

---

### Task 2: `CropperGeometry.rect(from:to:)` — drag-to-create math

Normalize an arbitrary `(anchor, current)` pair into a positive-extent `CGRect`. This is the math behind "click and drag from anywhere to anywhere" — order doesn't matter.

**Files:**
- Create: `Sources/SnatchKit/UI/Cropper/CropperGeometry.swift`
- Create: `Tests/SnatchKitTests/CropperGeometryTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/SnatchKitTests/CropperGeometryTests.swift`:

```swift
import XCTest
import CoreGraphics
@testable import SnatchKit

final class CropperGeometryTests: XCTestCase {

    // MARK: - rect(from:to:)

    func test_rect_topLeftToBottomRight_buildsPositiveExtentRect() {
        let r = CropperGeometry.rect(
            from: CGPoint(x: 10, y: 20),
            to:   CGPoint(x: 110, y: 80)
        )
        XCTAssertEqual(r, CGRect(x: 10, y: 20, width: 100, height: 60))
    }

    func test_rect_bottomRightToTopLeft_normalizesToPositiveExtent() {
        let r = CropperGeometry.rect(
            from: CGPoint(x: 110, y: 80),
            to:   CGPoint(x: 10, y: 20)
        )
        XCTAssertEqual(r, CGRect(x: 10, y: 20, width: 100, height: 60))
    }

    func test_rect_zeroDelta_returnsZeroSizeRect() {
        let r = CropperGeometry.rect(
            from: CGPoint(x: 50, y: 50),
            to:   CGPoint(x: 50, y: 50)
        )
        XCTAssertEqual(r, CGRect(x: 50, y: 50, width: 0, height: 0))
    }

    func test_rect_negativeCoordinates_workNormally() {
        // Multi-display setups can put a region into negative territory.
        let r = CropperGeometry.rect(
            from: CGPoint(x: -100, y: -50),
            to:   CGPoint(x: 0, y: 0)
        )
        XCTAssertEqual(r, CGRect(x: -100, y: -50, width: 100, height: 50))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter CropperGeometryTests`
Expected: build error — `CropperGeometry` is not defined.

- [ ] **Step 3: Implement `CropperGeometry.rect(from:to:)`**

Create `Sources/SnatchKit/UI/Cropper/CropperGeometry.swift`:

```swift
import Foundation
import CoreGraphics

/// Pure geometric helpers for the cropper UI. None of these touch AppKit;
/// they exist to keep the rect/handle math testable under `swift test` and
/// independent from the `NSView` that consumes them.
public enum CropperGeometry {

    // MARK: - Drag-to-create

    /// Build a normalized (positive-extent) `CGRect` from an arbitrary pair
    /// of corner points. Either point can be the anchor; the rect is the
    /// minimum bounding box that contains both.
    public static func rect(from anchor: CGPoint, to current: CGPoint) -> CGRect {
        let x = min(anchor.x, current.x)
        let y = min(anchor.y, current.y)
        let w = abs(current.x - anchor.x)
        let h = abs(current.y - anchor.y)
        return CGRect(x: x, y: y, width: w, height: h)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter CropperGeometryTests`
Expected: 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/SnatchKit/UI/Cropper/CropperGeometry.swift \
        Tests/SnatchKitTests/CropperGeometryTests.swift
git commit -m "feat(cropper): add CropperGeometry.rect(from:to:) for drag-to-create"
```

---

### Task 3: `CropperGeometry.handleFrames(for:handleSize:)` + tests

Compute the on-screen frame of each of the 8 resize handles, given the rectangle and a handle size. Used by both rendering (where to draw the grip) and hit-testing (which grip was clicked).

**Files:**
- Modify: `Sources/SnatchKit/UI/Cropper/CropperGeometry.swift`
- Modify: `Tests/SnatchKitTests/CropperGeometryTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `Tests/SnatchKitTests/CropperGeometryTests.swift` (inside the same class):

```swift
    // MARK: - handleFrames(for:handleSize:)

    func test_handleFrames_returnsAllEightResizeHandles() {
        let r = CGRect(x: 100, y: 100, width: 200, height: 100)
        let frames = CropperGeometry.handleFrames(for: r, handleSize: 12)
        XCTAssertEqual(Set(frames.keys), Set(CropperHandle.resizeCases))
    }

    func test_handleFrames_topLeftHandle_isCenteredOnRectTopLeftCorner() {
        let r = CGRect(x: 100, y: 100, width: 200, height: 100)
        let frames = CropperGeometry.handleFrames(for: r, handleSize: 12)
        // Handle is 12×12 centered on (100,100) → origin (94,94)
        XCTAssertEqual(frames[.topLeft], CGRect(x: 94, y: 94, width: 12, height: 12))
    }

    func test_handleFrames_bottomRightHandle_isCenteredOnRectBottomRightCorner() {
        let r = CGRect(x: 100, y: 100, width: 200, height: 100)
        let frames = CropperGeometry.handleFrames(for: r, handleSize: 12)
        // Bottom-right corner of r is (300, 200) → handle origin (294, 194)
        XCTAssertEqual(frames[.bottomRight], CGRect(x: 294, y: 194, width: 12, height: 12))
    }

    func test_handleFrames_topEdgeHandle_isCenteredOnTopMidpoint() {
        let r = CGRect(x: 100, y: 100, width: 200, height: 100)
        let frames = CropperGeometry.handleFrames(for: r, handleSize: 12)
        // Top midpoint is (200, 100) → handle origin (194, 94)
        XCTAssertEqual(frames[.top], CGRect(x: 194, y: 94, width: 12, height: 12))
    }

    func test_handleFrames_doesNotIncludeBodyCase() {
        let r = CGRect(x: 100, y: 100, width: 200, height: 100)
        let frames = CropperGeometry.handleFrames(for: r, handleSize: 12)
        XCTAssertNil(frames[.body])
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter CropperGeometryTests`
Expected: build error — `handleFrames(for:handleSize:)` is not defined.

- [ ] **Step 3: Implement `handleFrames(for:handleSize:)`**

Append to `Sources/SnatchKit/UI/Cropper/CropperGeometry.swift` (inside `enum CropperGeometry`):

```swift

    // MARK: - Handle frames

    /// Frame (origin + size) of each resize handle on `rect`, keyed by the
    /// handle case. Each handle is `handleSize × handleSize` and centered on
    /// the corresponding corner / edge midpoint of `rect`. The `.body` case
    /// has no rendered handle and is intentionally absent from the result.
    public static func handleFrames(
        for rect: CGRect,
        handleSize: CGFloat
    ) -> [CropperHandle: CGRect] {
        let half = handleSize / 2
        let cx = rect.midX
        let cy = rect.midY

        func frame(centeredAt p: CGPoint) -> CGRect {
            CGRect(x: p.x - half, y: p.y - half, width: handleSize, height: handleSize)
        }

        return [
            .topLeft:     frame(centeredAt: CGPoint(x: rect.minX, y: rect.minY)),
            .top:         frame(centeredAt: CGPoint(x: cx,        y: rect.minY)),
            .topRight:    frame(centeredAt: CGPoint(x: rect.maxX, y: rect.minY)),
            .left:        frame(centeredAt: CGPoint(x: rect.minX, y: cy)),
            .right:       frame(centeredAt: CGPoint(x: rect.maxX, y: cy)),
            .bottomLeft:  frame(centeredAt: CGPoint(x: rect.minX, y: rect.maxY)),
            .bottom:      frame(centeredAt: CGPoint(x: cx,        y: rect.maxY)),
            .bottomRight: frame(centeredAt: CGPoint(x: rect.maxX, y: rect.maxY)),
        ]
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter CropperGeometryTests`
Expected: all CropperGeometry tests pass (4 from Task 2 + 5 new = 9 total).

- [ ] **Step 5: Commit**

```bash
git add Sources/SnatchKit/UI/Cropper/CropperGeometry.swift \
        Tests/SnatchKitTests/CropperGeometryTests.swift
git commit -m "feat(cropper): add CropperGeometry.handleFrames for resize-grip layout"
```

---

### Task 4: `CropperGeometry.hitTest(point:in:handleSize:)` + tests

Decide which handle (if any) a click point lands on. Resize handles take precedence over `.body` — clicking the corner handle of a small rect would otherwise hit the body, which would degrade the UX.

**Files:**
- Modify: `Sources/SnatchKit/UI/Cropper/CropperGeometry.swift`
- Modify: `Tests/SnatchKitTests/CropperGeometryTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `Tests/SnatchKitTests/CropperGeometryTests.swift`:

```swift
    // MARK: - hitTest(point:in:handleSize:)

    func test_hitTest_pointFarOutsideRect_returnsNil() {
        let r = CGRect(x: 100, y: 100, width: 200, height: 100)
        XCTAssertNil(CropperGeometry.hitTest(point: CGPoint(x: 0, y: 0), in: r, handleSize: 12))
    }

    func test_hitTest_pointDeepInsideRect_returnsBody() {
        let r = CGRect(x: 100, y: 100, width: 200, height: 100)
        XCTAssertEqual(
            CropperGeometry.hitTest(point: CGPoint(x: 200, y: 150), in: r, handleSize: 12),
            .body
        )
    }

    func test_hitTest_pointOnTopLeftCorner_returnsTopLeftHandle() {
        let r = CGRect(x: 100, y: 100, width: 200, height: 100)
        XCTAssertEqual(
            CropperGeometry.hitTest(point: CGPoint(x: 100, y: 100), in: r, handleSize: 12),
            .topLeft
        )
    }

    func test_hitTest_pointOnBottomRightCorner_returnsBottomRightHandle() {
        let r = CGRect(x: 100, y: 100, width: 200, height: 100)
        XCTAssertEqual(
            CropperGeometry.hitTest(point: CGPoint(x: 300, y: 200), in: r, handleSize: 12),
            .bottomRight
        )
    }

    func test_hitTest_pointOnRightEdgeMidpoint_returnsRightHandle() {
        let r = CGRect(x: 100, y: 100, width: 200, height: 100)
        // Right midpoint is (300, 150)
        XCTAssertEqual(
            CropperGeometry.hitTest(point: CGPoint(x: 300, y: 150), in: r, handleSize: 12),
            .right
        )
    }

    func test_hitTest_handlesTakePrecedenceOverBody_whenRectIsLargerThanHandle() {
        // Inside the rect AND inside the top-left handle frame. Should resolve
        // to .topLeft (the more specific intent).
        let r = CGRect(x: 100, y: 100, width: 200, height: 100)
        XCTAssertEqual(
            CropperGeometry.hitTest(point: CGPoint(x: 102, y: 102), in: r, handleSize: 12),
            .topLeft
        )
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter CropperGeometryTests`
Expected: build error — `hitTest(point:in:handleSize:)` is not defined.

- [ ] **Step 3: Implement `hitTest(point:in:handleSize:)`**

Append to `Sources/SnatchKit/UI/Cropper/CropperGeometry.swift` (inside `enum CropperGeometry`):

```swift

    // MARK: - Hit-testing

    /// Decide which handle (if any) `point` lands on for a rectangle `rect`
    /// drawn with `handleSize`-pt grips. Resolution order:
    ///   1. The 8 resize-handle frames take precedence (more specific intent).
    ///   2. The rectangle interior maps to `.body` (whole-rect drag).
    ///   3. Anywhere else returns `nil` (fresh drag, replaces the rect).
    public static func hitTest(
        point: CGPoint,
        in rect: CGRect,
        handleSize: CGFloat
    ) -> CropperHandle? {
        let frames = handleFrames(for: rect, handleSize: handleSize)
        for handle in CropperHandle.resizeCases {
            if let f = frames[handle], f.contains(point) {
                return handle
            }
        }
        if rect.contains(point) {
            return .body
        }
        return nil
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter CropperGeometryTests`
Expected: all CropperGeometry tests pass (9 + 6 new = 15 total).

- [ ] **Step 5: Commit**

```bash
git add Sources/SnatchKit/UI/Cropper/CropperGeometry.swift \
        Tests/SnatchKitTests/CropperGeometryTests.swift
git commit -m "feat(cropper): add CropperGeometry.hitTest with handles-over-body precedence"
```

---

### Task 5: `CropperGeometry.resize(_:handle:dragDelta:)` + tests

Apply a drag offset to a rectangle, anchoring per the handle. Top-left drag pulls the top-left corner; right-edge drag moves only the right edge; body drag translates the whole rect. Negative deltas that would invert the rect produce a normalized rect (positive extent) — same convention as `rect(from:to:)`.

**Files:**
- Modify: `Sources/SnatchKit/UI/Cropper/CropperGeometry.swift`
- Modify: `Tests/SnatchKitTests/CropperGeometryTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `Tests/SnatchKitTests/CropperGeometryTests.swift`:

```swift
    // MARK: - resize(_:handle:dragDelta:)

    func test_resize_topLeftHandle_movesOriginAndShrinksFromTopLeft() {
        let r = CGRect(x: 100, y: 100, width: 200, height: 100)
        let out = CropperGeometry.resize(r, handle: .topLeft, dragDelta: CGSize(width: 20, height: 30))
        // top-left moves to (120,130); bottom-right stays at (300,200)
        XCTAssertEqual(out, CGRect(x: 120, y: 130, width: 180, height: 70))
    }

    func test_resize_rightHandle_extendsWidthOnly() {
        let r = CGRect(x: 100, y: 100, width: 200, height: 100)
        let out = CropperGeometry.resize(r, handle: .right, dragDelta: CGSize(width: 50, height: 999))
        // dy is ignored for an edge-handle drag
        XCTAssertEqual(out, CGRect(x: 100, y: 100, width: 250, height: 100))
    }

    func test_resize_bottomHandle_extendsHeightOnly() {
        let r = CGRect(x: 100, y: 100, width: 200, height: 100)
        let out = CropperGeometry.resize(r, handle: .bottom, dragDelta: CGSize(width: 999, height: 25))
        XCTAssertEqual(out, CGRect(x: 100, y: 100, width: 200, height: 125))
    }

    func test_resize_bottomRightHandle_extendsBothAxes() {
        let r = CGRect(x: 100, y: 100, width: 200, height: 100)
        let out = CropperGeometry.resize(r, handle: .bottomRight, dragDelta: CGSize(width: 50, height: 30))
        XCTAssertEqual(out, CGRect(x: 100, y: 100, width: 250, height: 130))
    }

    func test_resize_body_translatesWholeRect() {
        let r = CGRect(x: 100, y: 100, width: 200, height: 100)
        let out = CropperGeometry.resize(r, handle: .body, dragDelta: CGSize(width: -40, height: 60))
        XCTAssertEqual(out, CGRect(x: 60, y: 160, width: 200, height: 100))
    }

    func test_resize_topLeftHandle_draggedPastBottomRight_normalizesToPositiveExtent() {
        // Drag the top-left corner so far down-and-right that it crosses the
        // bottom-right corner. Result should still be a positive-extent rect.
        let r = CGRect(x: 100, y: 100, width: 200, height: 100)
        let out = CropperGeometry.resize(r, handle: .topLeft, dragDelta: CGSize(width: 250, height: 150))
        // top-left moves to (350, 250); bottom-right stays at (300, 200).
        // Normalized: origin (300, 200), size (50, 50).
        XCTAssertEqual(out, CGRect(x: 300, y: 200, width: 50, height: 50))
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter CropperGeometryTests`
Expected: build error — `resize(_:handle:dragDelta:)` is not defined.

- [ ] **Step 3: Implement `resize(_:handle:dragDelta:)`**

Append to `Sources/SnatchKit/UI/Cropper/CropperGeometry.swift` (inside `enum CropperGeometry`):

```swift

    // MARK: - Resize

    /// Apply `dragDelta` to `original`, anchoring per `handle`. Corner handles
    /// move both adjacent edges; edge handles move only one edge; `.body`
    /// translates the whole rect. The result is always a positive-extent
    /// (normalized) rect — if a corner drag crosses past the opposite corner,
    /// the rect flips and stays normalized, matching `rect(from:to:)` semantics.
    public static func resize(
        _ original: CGRect,
        handle: CropperHandle,
        dragDelta: CGSize
    ) -> CGRect {
        if handle == .body {
            return original.offsetBy(dx: dragDelta.width, dy: dragDelta.height)
        }

        var minX = original.minX
        var minY = original.minY
        var maxX = original.maxX
        var maxY = original.maxY
        let dx = dragDelta.width
        let dy = dragDelta.height

        switch handle {
        case .topLeft:     minX += dx; minY += dy
        case .top:                     minY += dy
        case .topRight:    maxX += dx; minY += dy
        case .left:        minX += dx
        case .right:       maxX += dx
        case .bottomLeft:  minX += dx; maxY += dy
        case .bottom:                  maxY += dy
        case .bottomRight: maxX += dx; maxY += dy
        case .body:        fatalError("unreachable — handled above")
        }

        let nx = min(minX, maxX)
        let ny = min(minY, maxY)
        let nw = abs(maxX - minX)
        let nh = abs(maxY - minY)
        return CGRect(x: nx, y: ny, width: nw, height: nh)
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter CropperGeometryTests`
Expected: all CropperGeometry tests pass (15 + 6 new = 21 total).

- [ ] **Step 5: Commit**

```bash
git add Sources/SnatchKit/UI/Cropper/CropperGeometry.swift \
        Tests/SnatchKitTests/CropperGeometryTests.swift
git commit -m "feat(cropper): add CropperGeometry.resize for handle-anchored drag math"
```

---

### Task 6: `CropperState` — drag/resize state machine + tests

Bind the geometry helpers into a small state value type that drives the view. Inputs: mouse events (down/dragged/up). Outputs: a `displayRect` to draw, and (on mouse-up) the rectangle the user "owns". Tests cover every transition.

The state machine has four modes:
- `.idle` — no rectangle exists yet. Mouse-down anywhere starts a fresh drag.
- `.have(CGRect)` — a rectangle is committed (either from `RegionStore.lastRegion` or from a previous drag). Mouse-down hit-tests against handles.
- `.dragging(anchor, current)` — user is drawing a fresh rect from scratch.
- `.resizing(handle, original, anchor, current)` — user is resizing or moving an existing rect.

**Files:**
- Create: `Sources/SnatchKit/UI/Cropper/CropperState.swift`
- Create: `Tests/SnatchKitTests/CropperStateTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/SnatchKitTests/CropperStateTests.swift`:

```swift
import XCTest
import CoreGraphics
@testable import SnatchKit

final class CropperStateTests: XCTestCase {

    private let handleSize: CGFloat = 12

    // MARK: - Initial state

    func test_initialState_withNoRect_isIdleAndDisplayRectIsNil() {
        let s = CropperState(initial: nil)
        XCTAssertEqual(s.mode, .idle)
        XCTAssertNil(s.displayRect)
    }

    func test_initialState_withRect_isHaveAndDisplayRectMatches() {
        let r = CGRect(x: 100, y: 100, width: 200, height: 100)
        let s = CropperState(initial: r)
        XCTAssertEqual(s.mode, .have(r))
        XCTAssertEqual(s.displayRect, r)
    }

    // MARK: - Idle: any mouse-down starts a fresh drag

    func test_mouseDown_fromIdle_startsDragging() {
        var s = CropperState(initial: nil)
        s = s.applyMouseDown(at: CGPoint(x: 50, y: 60), handleSize: handleSize)
        XCTAssertEqual(s.mode, .dragging(anchor: CGPoint(x: 50, y: 60), current: CGPoint(x: 50, y: 60)))
        XCTAssertEqual(s.displayRect, CGRect(x: 50, y: 60, width: 0, height: 0))
    }

    // MARK: - Have-rect: mouse-down hit-tests handles vs body vs outside

    func test_mouseDown_fromHaveRect_outsideRect_startsFreshDrag() {
        let r = CGRect(x: 100, y: 100, width: 200, height: 100)
        var s = CropperState(initial: r)
        s = s.applyMouseDown(at: CGPoint(x: 0, y: 0), handleSize: handleSize)
        XCTAssertEqual(s.mode, .dragging(anchor: CGPoint(x: 0, y: 0), current: CGPoint(x: 0, y: 0)))
    }

    func test_mouseDown_fromHaveRect_onCornerHandle_startsResizing() {
        let r = CGRect(x: 100, y: 100, width: 200, height: 100)
        var s = CropperState(initial: r)
        s = s.applyMouseDown(at: CGPoint(x: 100, y: 100), handleSize: handleSize)
        XCTAssertEqual(
            s.mode,
            .resizing(
                handle: .topLeft,
                original: r,
                anchor: CGPoint(x: 100, y: 100),
                current: CGPoint(x: 100, y: 100)
            )
        )
    }

    func test_mouseDown_fromHaveRect_insideBody_startsBodyDrag() {
        let r = CGRect(x: 100, y: 100, width: 200, height: 100)
        var s = CropperState(initial: r)
        s = s.applyMouseDown(at: CGPoint(x: 200, y: 150), handleSize: handleSize)
        XCTAssertEqual(
            s.mode,
            .resizing(
                handle: .body,
                original: r,
                anchor: CGPoint(x: 200, y: 150),
                current: CGPoint(x: 200, y: 150)
            )
        )
    }

    // MARK: - Dragging: mouse-dragged updates displayRect, mouse-up commits

    func test_mouseDragged_fromDragging_updatesDisplayRect() {
        var s = CropperState(initial: nil)
        s = s.applyMouseDown(at: CGPoint(x: 50, y: 60), handleSize: handleSize)
        s = s.applyMouseDragged(at: CGPoint(x: 150, y: 120))
        XCTAssertEqual(s.displayRect, CGRect(x: 50, y: 60, width: 100, height: 60))
    }

    func test_mouseUp_fromDragging_commitsToHaveRect() {
        var s = CropperState(initial: nil)
        s = s.applyMouseDown(at: CGPoint(x: 50, y: 60), handleSize: handleSize)
        s = s.applyMouseDragged(at: CGPoint(x: 150, y: 120))
        s = s.applyMouseUp(at: CGPoint(x: 150, y: 120))
        XCTAssertEqual(s.mode, .have(CGRect(x: 50, y: 60, width: 100, height: 60)))
    }

    func test_mouseUp_fromDragging_zeroSizeRect_revertsToIdle() {
        // A click-without-drag should not commit a 0×0 rect.
        var s = CropperState(initial: nil)
        s = s.applyMouseDown(at: CGPoint(x: 50, y: 60), handleSize: handleSize)
        s = s.applyMouseUp(at: CGPoint(x: 50, y: 60))
        XCTAssertEqual(s.mode, .idle)
    }

    // MARK: - Resizing: mouse-dragged updates displayRect, mouse-up commits

    func test_mouseDragged_fromResizing_updatesDisplayRect() {
        let r = CGRect(x: 100, y: 100, width: 200, height: 100)
        var s = CropperState(initial: r)
        s = s.applyMouseDown(at: CGPoint(x: 300, y: 200), handleSize: handleSize) // bottom-right
        s = s.applyMouseDragged(at: CGPoint(x: 350, y: 230))
        XCTAssertEqual(s.displayRect, CGRect(x: 100, y: 100, width: 250, height: 130))
    }

    func test_mouseUp_fromResizing_commitsResizedRect() {
        let r = CGRect(x: 100, y: 100, width: 200, height: 100)
        var s = CropperState(initial: r)
        s = s.applyMouseDown(at: CGPoint(x: 300, y: 200), handleSize: handleSize)
        s = s.applyMouseDragged(at: CGPoint(x: 350, y: 230))
        s = s.applyMouseUp(at: CGPoint(x: 350, y: 230))
        XCTAssertEqual(s.mode, .have(CGRect(x: 100, y: 100, width: 250, height: 130)))
    }

    func test_mouseUp_fromResizing_body_commitsTranslatedRect() {
        let r = CGRect(x: 100, y: 100, width: 200, height: 100)
        var s = CropperState(initial: r)
        s = s.applyMouseDown(at: CGPoint(x: 200, y: 150), handleSize: handleSize)
        s = s.applyMouseDragged(at: CGPoint(x: 220, y: 180))
        s = s.applyMouseUp(at: CGPoint(x: 220, y: 180))
        XCTAssertEqual(s.mode, .have(CGRect(x: 120, y: 130, width: 200, height: 100)))
    }

    // MARK: - Stray events are no-ops

    func test_mouseDragged_fromIdle_isNoOp() {
        var s = CropperState(initial: nil)
        s = s.applyMouseDragged(at: CGPoint(x: 50, y: 60))
        XCTAssertEqual(s.mode, .idle)
    }

    func test_mouseUp_fromHaveRect_isNoOp() {
        let r = CGRect(x: 100, y: 100, width: 200, height: 100)
        var s = CropperState(initial: r)
        s = s.applyMouseUp(at: CGPoint(x: 200, y: 150))
        XCTAssertEqual(s.mode, .have(r))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter CropperStateTests`
Expected: build error — `CropperState` is not defined.

- [ ] **Step 3: Create `CropperState`**

Create `Sources/SnatchKit/UI/Cropper/CropperState.swift`:

```swift
import Foundation
import CoreGraphics

/// Drag/resize state for the cropper view, expressed as a value type so it
/// can be unit-tested in isolation from AppKit. The view owns one instance,
/// rebinds it on each mouse / key event, and reads `displayRect` to drive
/// drawing.
///
/// The four modes:
/// - `.idle`         — no rectangle yet; any mouse-down starts a fresh drag.
/// - `.have(rect)`   — committed rectangle; mouse-down hit-tests handles.
/// - `.dragging(…)`  — user is drawing a fresh rect from scratch.
/// - `.resizing(…)`  — user is resizing or moving an existing rect.
public struct CropperState: Equatable, Sendable {

    public enum Mode: Equatable, Sendable {
        case idle
        case have(CGRect)
        case dragging(anchor: CGPoint, current: CGPoint)
        case resizing(handle: CropperHandle, original: CGRect, anchor: CGPoint, current: CGPoint)
    }

    public var mode: Mode

    /// Initial state. `initial` is the persisted region from `RegionStore`,
    /// or nil on first launch.
    public init(initial: CGRect?) {
        if let r = initial {
            self.mode = .have(r)
        } else {
            self.mode = .idle
        }
    }

    /// The rectangle the view should draw right now. Nil while `.idle`.
    public var displayRect: CGRect? {
        switch mode {
        case .idle:
            return nil
        case .have(let r):
            return r
        case .dragging(let anchor, let current):
            return CropperGeometry.rect(from: anchor, to: current)
        case .resizing(let handle, let original, let anchor, let current):
            let delta = CGSize(width: current.x - anchor.x, height: current.y - anchor.y)
            return CropperGeometry.resize(original, handle: handle, dragDelta: delta)
        }
    }

    /// The committed rectangle, if any (i.e., when not mid-drag).
    public var committedRect: CGRect? {
        if case .have(let r) = mode { return r }
        return nil
    }

    // MARK: - Transitions

    public func applyMouseDown(at point: CGPoint, handleSize: CGFloat) -> CropperState {
        switch mode {
        case .idle:
            return Self(mode: .dragging(anchor: point, current: point))
        case .have(let r):
            if let h = CropperGeometry.hitTest(point: point, in: r, handleSize: handleSize) {
                return Self(mode: .resizing(handle: h, original: r, anchor: point, current: point))
            } else {
                return Self(mode: .dragging(anchor: point, current: point))
            }
        case .dragging, .resizing:
            return self // already mid-gesture; ignore stray downs
        }
    }

    public func applyMouseDragged(at point: CGPoint) -> CropperState {
        switch mode {
        case .dragging(let anchor, _):
            return Self(mode: .dragging(anchor: anchor, current: point))
        case .resizing(let h, let original, let anchor, _):
            return Self(mode: .resizing(handle: h, original: original, anchor: anchor, current: point))
        case .idle, .have:
            return self // no gesture in progress
        }
    }

    public func applyMouseUp(at point: CGPoint) -> CropperState {
        switch mode {
        case .dragging(let anchor, _):
            let r = CropperGeometry.rect(from: anchor, to: point)
            // Reject zero-size commits so a click-without-drag doesn't
            // produce a degenerate region.
            if r.width == 0 && r.height == 0 {
                return Self(mode: .idle)
            }
            return Self(mode: .have(r))
        case .resizing(let h, let original, let anchor, _):
            let delta = CGSize(width: point.x - anchor.x, height: point.y - anchor.y)
            let r = CropperGeometry.resize(original, handle: h, dragDelta: delta)
            return Self(mode: .have(r))
        case .idle, .have:
            return self
        }
    }

    // MARK: - Private

    private init(mode: Mode) {
        self.mode = mode
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter CropperStateTests`
Expected: all 14 CropperStateTests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/SnatchKit/UI/Cropper/CropperState.swift \
        Tests/SnatchKitTests/CropperStateTests.swift
git commit -m "feat(cropper): add CropperState drag/resize state machine

Pure value type wrapping CropperGeometry. Owns mode (idle/have/dragging/
resizing) and exposes displayRect for the view. Rejects zero-size commits
so click-without-drag doesn't produce degenerate regions."
```

---

### Task 7: `RegionStore` — last-region persistence + tests

UserDefaults-backed `CGRect` persistence. Encoded as `[Double]` (4-element x,y,w,h) under a single key. Tests use a per-test `UserDefaults(suiteName:)` to stay isolated, matching the pattern called for in spec §9.

**Files:**
- Create: `Sources/SnatchKit/System/RegionStore.swift`
- Create: `Tests/SnatchKitTests/RegionStoreTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/SnatchKitTests/RegionStoreTests.swift`:

```swift
import XCTest
import CoreGraphics
@testable import SnatchKit

final class RegionStoreTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "co.snatch.tests.RegionStore.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults?.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func test_lastRegion_isNil_whenNothingPersisted() {
        let store = RegionStore(defaults: defaults)
        XCTAssertNil(store.lastRegion)
    }

    func test_persist_thenLastRegion_returnsTheSameRect() {
        let store = RegionStore(defaults: defaults)
        let r = CGRect(x: 120.5, y: 240, width: 800, height: 600)
        store.persist(r)
        XCTAssertEqual(store.lastRegion, r)
    }

    func test_persist_overwritesPreviousValue() {
        let store = RegionStore(defaults: defaults)
        store.persist(CGRect(x: 0, y: 0, width: 100, height: 100))
        store.persist(CGRect(x: 50, y: 50, width: 200, height: 150))
        XCTAssertEqual(store.lastRegion, CGRect(x: 50, y: 50, width: 200, height: 150))
    }

    func test_persistedValue_survivesNewStoreInstanceOnSameDefaults() {
        // Simulates "next launch": new RegionStore over the same UserDefaults.
        RegionStore(defaults: defaults).persist(CGRect(x: 10, y: 20, width: 30, height: 40))
        let next = RegionStore(defaults: defaults)
        XCTAssertEqual(next.lastRegion, CGRect(x: 10, y: 20, width: 30, height: 40))
    }

    func test_lastRegion_returnsNil_whenStoredValueIsMalformed() {
        // Corrupt the defaults under the hood — a 3-element array isn't a
        // valid CGRect encoding. RegionStore should return nil rather than
        // crash or trust the bogus data.
        defaults.set([10.0, 20.0, 30.0], forKey: "lastRegion")
        let store = RegionStore(defaults: defaults)
        XCTAssertNil(store.lastRegion)
    }

    func test_clear_removesPersistedValue() {
        let store = RegionStore(defaults: defaults)
        store.persist(CGRect(x: 1, y: 2, width: 3, height: 4))
        store.clear()
        XCTAssertNil(store.lastRegion)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter RegionStoreTests`
Expected: build error — `RegionStore` is not defined.

- [ ] **Step 3: Create `RegionStore`**

Create `Sources/SnatchKit/System/RegionStore.swift`:

```swift
import Foundation
import CoreGraphics

/// UserDefaults-backed persistence for the last-recorded region. Stores the
/// rect as `[Double]` of length 4 (x, y, w, h) under a single key. Reading a
/// malformed value returns nil — the stored format is private to this file
/// and any divergence is treated as "no persisted region", not a crash.
public final class RegionStore {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "lastRegion") {
        self.defaults = defaults
        self.key = key
    }

    public var lastRegion: CGRect? {
        guard let raw = defaults.array(forKey: key) as? [Double], raw.count == 4 else {
            return nil
        }
        return CGRect(x: raw[0], y: raw[1], width: raw[2], height: raw[3])
    }

    public func persist(_ region: CGRect) {
        let encoded: [Double] = [
            Double(region.origin.x),
            Double(region.origin.y),
            Double(region.size.width),
            Double(region.size.height),
        ]
        defaults.set(encoded, forKey: key)
    }

    public func clear() {
        defaults.removeObject(forKey: key)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter RegionStoreTests`
Expected: 6 RegionStoreTests pass.

- [ ] **Step 5: Run the full pure-logic test suite — sanity check**

Run: `swift test`
Expected: all M1 + M2 + M3-pure tests pass. No live-capture tests run unless `SNATCH_LIVE_CAPTURE=1` is set.

- [ ] **Step 6: Commit**

```bash
git add Sources/SnatchKit/System/RegionStore.swift \
        Tests/SnatchKitTests/RegionStoreTests.swift
git commit -m "feat(system): add RegionStore for last-region persistence

UserDefaults-backed [Double; 4] encoding. Injectable defaults for tests;
malformed values return nil rather than crash."
```

---

### Task 8: Add `SnatchCropperCLI` SPM target — entry point + AppDelegate skeleton

The SPM-side scaffold for the runnable cropper. After this task, `swift run snatch-cropper-cli` builds and exits cleanly (the cropper window itself comes in Task 9). The target imports `AppKit` and `SnatchKit`; it's the only place in the repo that depends on AppKit.

**Files:**
- Modify: `Package.swift`
- Create: `Sources/SnatchCropperCLI/main.swift`
- Create: `Sources/SnatchCropperCLI/AppDelegate.swift`

- [ ] **Step 1: Add the executable target to `Package.swift`**

In `Package.swift`, add a new product entry alongside `snatch-cli` and `snatch-record-cli`, and a corresponding `.executableTarget` after the `SnatchRecordCLI` target. The diff is:

```swift
// In `products:`
.executable(name: "snatch-cropper-cli", targets: ["SnatchCropperCLI"]),
```

```swift
// In `targets:`, after the SnatchRecordCLI target:
.executableTarget(
    name: "SnatchCropperCLI",
    dependencies: ["SnatchKit"],
    path: "Sources/SnatchCropperCLI"
),
```

After the edit the file should declare four products (the `SnatchKit` library plus three executables `snatch-cli` / `snatch-record-cli` / `snatch-cropper-cli`) and six targets (`CGifski`, `SnatchKit`, `SnatchKitTests`, `SnatchCLI`, `SnatchRecordCLI`, `SnatchCropperCLI`).

- [ ] **Step 2: Create the entry point**

Create `Sources/SnatchCropperCLI/main.swift`:

```swift
// Sources/SnatchCropperCLI/main.swift
//
// snatch-cropper-cli — full-screen cropper UI smoke harness for M3.
//
// On launch, presents the transparent cropper overlay. On Record (button or
// Space/Enter), writes the chosen region to stdout in the form:
//
//     RECORD region=(x,y,w,h)
//
// then persists it via RegionStore and exits 0. On Esc, writes:
//
//     CANCELLED
//
// and exits 0.
//
// Run:
//   swift run snatch-cropper-cli
//
// Note (M3 build-system decision, see plan): this is an SPM executable, not
// a bundled .app. It runs a normal NSApplication; macOS will give it a Dock
// icon and a default app menu. M5 will lift these files into the new
// Snatch.xcodeproj when LSUIElement / hotkey / notifications all need a
// bundle simultaneously.

import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

// Foreground the process so the cropper window is key + frontmost. Without
// this, an SPM executable launches as a "background" .Background process
// and the window may not become key.
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)

app.run()
```

- [ ] **Step 3: Create the AppDelegate skeleton**

Create `Sources/SnatchCropperCLI/AppDelegate.swift`:

```swift
// Sources/SnatchCropperCLI/AppDelegate.swift
import AppKit
import SnatchKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    // Wired up in Tasks 9–13.
    private var cropperWindow: NSWindow?
    private let regionStore = RegionStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Cropper window construction lands in Task 9.
        // For now we exit immediately so the SPM target builds and runs end-
        // to-end without a hang, proving the wiring.
        Self.emitCancelledAndExit()
    }

    // Called by the cropper view in Task 13 / 14.
    func cropperRecordRequested(region: CGRect) {
        regionStore.persist(region)
        let x = Int(region.origin.x.rounded())
        let y = Int(region.origin.y.rounded())
        let w = Int(region.size.width.rounded())
        let h = Int(region.size.height.rounded())
        print("RECORD region=(\(x),\(y),\(w),\(h))")
        NSApplication.shared.terminate(nil)
    }

    // Called by the cropper view in Task 13.
    func cropperCancelled() {
        Self.emitCancelledAndExit()
    }

    private static func emitCancelledAndExit() {
        print("CANCELLED")
        NSApplication.shared.terminate(nil)
    }
}
```

- [ ] **Step 4: Build and run end-to-end**

Run: `swift build`
Expected: clean build, all four products compile.

Run: `swift run snatch-cropper-cli`
Expected: stdout prints `CANCELLED`; the process exits with status 0; no window appears (window construction is Task 9).

- [ ] **Step 5: Commit**

```bash
git add Package.swift \
        Sources/SnatchCropperCLI/main.swift \
        Sources/SnatchCropperCLI/AppDelegate.swift
git commit -m "feat(cropper-cli): add SnatchCropperCLI SPM target with AppDelegate skeleton

Empty harness that prints CANCELLED and exits. Full cropper window comes
in Task 9 of the M3 plan; this commit proves the SPM scaffolding."
```

---

### Task 9: `CropperWindow` — transparent borderless overlay at screen-saver level

`NSWindow` subclass configured per spec §6: borderless, transparent background, `screenSaver` window level, sized to the active screen, `canBecomeKey = true`. No content yet — the view comes in Task 10.

**Files:**
- Create: `Sources/SnatchCropperCLI/CropperWindow.swift`
- Modify: `Sources/SnatchCropperCLI/AppDelegate.swift`

- [ ] **Step 1: Create the window class**

Create `Sources/SnatchCropperCLI/CropperWindow.swift`:

```swift
// Sources/SnatchCropperCLI/CropperWindow.swift
import AppKit

/// Transparent borderless overlay window at `NSWindow.Level.screenSaver`,
/// sized to fill `screen`. Configured per spec §6.
///
/// `canBecomeKey` is overridden to true because borderless windows default
/// to false — without this, keyboard events (Esc, Space, Enter) would never
/// reach the view's responder chain.
final class CropperWindow: NSWindow {

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )

        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.level = .screenSaver
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
```

- [ ] **Step 2: Wire the window into AppDelegate**

Update `Sources/SnatchCropperCLI/AppDelegate.swift` `applicationDidFinishLaunching` to construct and show the window:

```swift
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let screen = NSScreen.main else {
            // No screens means we can't show a cropper. Bail.
            Self.emitCancelledAndExit()
            return
        }

        let w = CropperWindow(screen: screen)
        self.cropperWindow = w
        w.makeKeyAndOrderFront(nil)
        // Mouse / keyboard handlers are wired up in Tasks 11–13.
    }
```

- [ ] **Step 3: Smoke-run the executable**

Run: `swift run snatch-cropper-cli`

Expected:
- The process foregrounds (Dock icon flashes).
- A transparent overlay covers your main display. Because it has no content yet, the screen looks visually unchanged. You may notice the menu bar is slightly tinted because the overlay sits above everything.
- The process **does not exit on its own** — there's no Esc handler yet.
- Quit it with `⌘Q` from the menu, or kill it from the terminal (`Ctrl+C`).

This is the M3 first visual smoke. Confirm you see the Dock icon + the app menu while the overlay is up.

- [ ] **Step 4: Commit**

```bash
git add Sources/SnatchCropperCLI/CropperWindow.swift \
        Sources/SnatchCropperCLI/AppDelegate.swift
git commit -m "feat(cropper): show transparent screenSaver-level overlay window

CropperWindow is borderless, transparent, fills the main screen, and is
key-eligible. No content yet (CropperView arrives in the next task);
quit with ⌘Q for now."
```

---

### Task 10: `CropperView` — renders the dim, the rectangle, the handles, and the dimensions label

`NSView` subclass that owns a `CropperState` and draws four things, in z-order from back to front:
1. Full-view dim (40% black) **except** inside the display rect, which is left clear so the user sees what they'll capture.
2. The rectangle outline (1 pt white stroke).
3. The 8 resize handles (filled white squares, 12×12 each), drawn only when in `.have` or `.resizing` mode (not while drawing a fresh rect — which has no committed handles yet).
4. The `W × H` dimensions label, positioned just outside the rectangle's top-left corner.

**Files:**
- Create: `Sources/SnatchCropperCLI/CropperView.swift`
- Modify: `Sources/SnatchCropperCLI/AppDelegate.swift`
- Modify: `Sources/SnatchCropperCLI/CropperWindow.swift`

- [ ] **Step 1: Create `CropperView`**

Create `Sources/SnatchCropperCLI/CropperView.swift`:

```swift
// Sources/SnatchCropperCLI/CropperView.swift
import AppKit
import SnatchKit

/// Renders the cropper overlay for a single screen. Owns a `CropperState`
/// (mutated by Task 11/12 mouse/key handlers), and draws the dim + rect +
/// handles + dimensions label every time the state changes.
final class CropperView: NSView {

    /// Click-target diameter of each resize handle, in points.
    static let handleSize: CGFloat = 12

    /// Mutated by the Task 11/12 event handlers. `didSet` triggers a redraw.
    var state: CropperState {
        didSet { needsDisplay = true }
    }

    init(frame: NSRect, initialRegion: CGRect?) {
        // `initialRegion` is supplied in view-local coords. The AppDelegate
        // (Task 12) does the screen-space → view-local translation by
        // subtracting `screen.frame.origin` before constructing the window.
        // For M3 we only support the primary display, where screen.frame
        // origin is (0, 0) and the conversion is a no-op — explicit
        // translation lives in AppDelegate so multi-display support (a
        // documented M5 carry-over) only requires touching the AppDelegate
        // seam, not the view.
        self.state = CropperState(initial: initialRegion)
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }

    /// Use a flipped coordinate system so y-down matches CG / spec §6 region
    /// semantics. Without this, the math in CropperGeometry would need a
    /// y-flip every time we crossed the AppKit boundary.
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // 1. Full-view dim, with the displayRect cut out.
        NSColor.black.withAlphaComponent(0.4).setFill()
        if let rect = state.displayRect {
            let path = NSBezierPath(rect: bounds)
            path.append(NSBezierPath(rect: rect).reversed)
            path.fill()
        } else {
            bounds.fill()
        }

        guard let rect = state.displayRect else { return }

        // 2. Rectangle outline.
        NSColor.white.setStroke()
        let outline = NSBezierPath(rect: rect)
        outline.lineWidth = 1
        outline.stroke()

        // 3. Resize handles (only when committed or while resizing — not
        //    during a fresh drag).
        if shouldShowHandles {
            NSColor.white.setFill()
            for (_, frame) in CropperGeometry.handleFrames(for: rect, handleSize: Self.handleSize) {
                NSBezierPath(rect: frame).fill()
            }
        }

        // 4. Dimensions label, rendered just outside the rect's top-left.
        let w = Int(rect.width.rounded())
        let h = Int(rect.height.rounded())
        let label = "\(w) × \(h)"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black.withAlphaComponent(0.6),
        ]
        let size = (label as NSString).size(withAttributes: attrs)
        let labelOrigin = CGPoint(
            x: rect.minX,
            y: max(0, rect.minY - size.height - 2)
        )
        (label as NSString).draw(at: labelOrigin, withAttributes: attrs)
    }

    private var shouldShowHandles: Bool {
        switch state.mode {
        case .have, .resizing: return true
        case .idle, .dragging: return false
        }
    }
}
```

- [ ] **Step 2: Install the view inside the window**

Update `Sources/SnatchCropperCLI/CropperWindow.swift` to expose a typed accessor for the cropper view (we'll read it back from the AppDelegate to wire events in later tasks):

```swift
final class CropperWindow: NSWindow {

    let cropperView: CropperView

    init(screen: NSScreen, initialRegion: CGRect?) {
        let frame = screen.frame
        self.cropperView = CropperView(frame: NSRect(origin: .zero, size: frame.size), initialRegion: initialRegion)

        super.init(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )

        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.level = .screenSaver
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true

        self.contentView = cropperView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
```

Note the constructor signature changed from `init(screen:)` to `init(screen:initialRegion:)`.

- [ ] **Step 3: Update the AppDelegate to pass the persisted region (screen-space → view-local)**

In `Sources/SnatchCropperCLI/AppDelegate.swift`, replace the single-line `let w = CropperWindow(screen: screen)` from Task 9 Step 2 with the conversion + construction:

```swift
        let initialViewLocal = regionStore.lastRegion.map { region -> CGRect in
            CGRect(
                x: region.origin.x - screen.frame.origin.x,
                y: region.origin.y - screen.frame.origin.y,
                width: region.size.width,
                height: region.size.height
            )
        }
        let w = CropperWindow(screen: screen, initialRegion: initialViewLocal)
```

For the primary display this conversion is a no-op (origin (0,0)). It's correct on secondary displays even though M3 only smokes against the primary — keeping the seam clean now means M5's multi-display work doesn't have to retrofit here.

- [ ] **Step 4: Smoke-run the executable**

Run `swift run snatch-cropper-cli`.

Expected on **first run** (RegionStore empty):
- Screen turns 40% dim with no rectangle visible.
- No mouse interaction yet (handlers come in Task 11) — quit with `⌘Q`.

Expected on **second run** (only after Task 14 wires up persistence — for now this case won't trigger):
- The previously-recorded rectangle is pre-drawn with handles visible. (We can't actually verify this until Task 14 — note here that the persisted-region path is plumbed but won't fill until then.)

- [ ] **Step 5: Commit**

```bash
git add Sources/SnatchCropperCLI/CropperView.swift \
        Sources/SnatchCropperCLI/CropperWindow.swift \
        Sources/SnatchCropperCLI/AppDelegate.swift
git commit -m "feat(cropper): render dim + rectangle + handles + dimensions label

CropperView consumes CropperState.displayRect each frame. Flipped coords
to match CG semantics. No mouse/keyboard yet — that lands in next tasks."
```

---

### Task 11: Mouse handling — drag-to-create, drag-handle-to-resize, drag-body-to-move

Forward AppKit mouse events into `CropperState`. The view becomes the first responder for mouse events; each event maps 1:1 to a `CropperState` transition.

**Files:**
- Modify: `Sources/SnatchCropperCLI/CropperView.swift`

- [ ] **Step 1: Add mouse event handlers to `CropperView`**

Append to `CropperView` (inside the class body, after `draw`):

```swift

    // MARK: - Mouse handling

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        state = state.applyMouseDown(at: p, handleSize: Self.handleSize)
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        state = state.applyMouseDragged(at: p)
    }

    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        state = state.applyMouseUp(at: p)
    }
```

- [ ] **Step 2: Smoke-run and exercise the cropper**

Run: `swift run snatch-cropper-cli`

Walk through these by hand:
1. **Click and drag** anywhere → a white rectangle is drawn, dim is cut out where the rect is, dimensions label shows live `W × H`. On release, handles appear at the 8 perimeter points.
2. **Click and drag a corner handle** → the rect resizes, anchored at the opposite corner.
3. **Click and drag an edge handle** → only one edge moves; the perpendicular axis is preserved.
4. **Click and drag inside the rectangle (away from handles)** → the rectangle translates whole-cloth.
5. **Click outside the rectangle** → starts a fresh drag, replacing the existing rect.

Quit with `⌘Q` (Esc handling lands in Task 12).

- [ ] **Step 3: Commit**

```bash
git add Sources/SnatchCropperCLI/CropperView.swift
git commit -m "feat(cropper): wire mouse handlers into CropperState transitions"
```

---

### Task 12: Keyboard handling — Esc cancels, Space/Enter records

Make `CropperView` first responder for key events and dispatch:
- **Esc** → invoke the cancel callback (AppDelegate prints `CANCELLED` and exits).
- **Space / Enter / Return** → invoke the record callback with the committed rect (AppDelegate persists, prints `RECORD …`, and exits). If there's no committed rect (`.idle` or mid-drag), the key is ignored.

The callbacks are closures injected at construction so the view stays decoupled from the AppDelegate.

**Files:**
- Modify: `Sources/SnatchCropperCLI/CropperView.swift`
- Modify: `Sources/SnatchCropperCLI/CropperWindow.swift`
- Modify: `Sources/SnatchCropperCLI/AppDelegate.swift`

- [ ] **Step 1: Inject callbacks and override key handling in `CropperView`**

Update the `CropperView` declaration in `Sources/SnatchCropperCLI/CropperView.swift`:

Add stored properties near the top of the class (above `state`):

```swift
    /// Called when the user confirms the region (Record button, Space, or Return).
    var onRecord: ((CGRect) -> Void)?

    /// Called when the user cancels (Esc).
    var onCancel: (() -> Void)?
```

Then override responder semantics and key handling. Append inside the class:

```swift

    // MARK: - First-responder + keys

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // Esc
            onCancel?()
        case 49, 36, 76: // Space (49), Return (36), Enter (76 — keypad)
            if let rect = state.committedRect {
                onRecord?(rect)
            }
            // No-op while .idle / .dragging / .resizing — the user has not
            // settled on a rectangle yet.
        default:
            super.keyDown(with: event)
        }
    }
```

- [ ] **Step 2: Make the view first responder when the window becomes key**

In `Sources/SnatchCropperCLI/CropperWindow.swift`, append:

```swift

    override func becomeKey() {
        super.becomeKey()
        self.makeFirstResponder(cropperView)
    }
```

- [ ] **Step 3: Wire the callbacks in AppDelegate**

In `Sources/SnatchCropperCLI/AppDelegate.swift`, update `applicationDidFinishLaunching` to install the callbacks before showing the window:

```swift
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let screen = NSScreen.main else {
            Self.emitCancelledAndExit()
            return
        }

        // Inbound: screen-space (persisted region) → view-local.
        let initialViewLocal = regionStore.lastRegion.map { region -> CGRect in
            CGRect(
                x: region.origin.x - screen.frame.origin.x,
                y: region.origin.y - screen.frame.origin.y,
                width: region.size.width,
                height: region.size.height
            )
        }

        let w = CropperWindow(screen: screen, initialRegion: initialViewLocal)
        w.cropperView.onRecord = { [weak self] viewRect in
            // Outbound: view-local (cropper hands us a 0,0-origin rect) → screen-space.
            let screenRect = CGRect(
                x: viewRect.origin.x + screen.frame.origin.x,
                y: viewRect.origin.y + screen.frame.origin.y,
                width: viewRect.size.width,
                height: viewRect.size.height
            )
            self?.cropperRecordRequested(region: screenRect)
        }
        w.cropperView.onCancel = { [weak self] in
            self?.cropperCancelled()
        }
        self.cropperWindow = w
        w.makeKeyAndOrderFront(nil)
    }
```

- [ ] **Step 4: Smoke-run end-to-end**

Run: `swift run snatch-cropper-cli`

Walk through:
1. **Press Esc** with no rectangle → stdout prints `CANCELLED`; the app exits.
2. **Run again, drag a rect, press Space** → stdout prints `RECORD region=(x,y,w,h)` with the dragged region; the app exits.
3. **Run again, drag a rect, press Return** → same as Space.
4. **Run again, drag a rect, press Esc** → `CANCELLED`; nothing persisted.
5. **Run again, before drawing any rect, press Space** → no-op (key is ignored). Then drag a rect and press Esc to exit cleanly.

- [ ] **Step 5: Commit**

```bash
git add Sources/SnatchCropperCLI/CropperView.swift \
        Sources/SnatchCropperCLI/CropperWindow.swift \
        Sources/SnatchCropperCLI/AppDelegate.swift
git commit -m "feat(cropper): wire Esc/Space/Return keys to cancel/record callbacks

CropperView becomes first responder on becomeKey; keys are dispatched
through onCancel/onRecord closures that the AppDelegate installs."
```

---

### Task 13: Record button — floating NSButton next to the rectangle

When the cropper is in `.have` mode (rectangle committed), show a floating "Record" button near the rectangle's bottom-right corner. Click → invokes `onRecord` with the committed rect (same path as Space/Return).

The button is an `NSButton` added as a subview of `CropperView`; its frame is recomputed on every `layout()` to track the rectangle. Hidden in any mode other than `.have`.

**Files:**
- Create: `Sources/SnatchCropperCLI/CropperRecordButton.swift`
- Modify: `Sources/SnatchCropperCLI/CropperView.swift`

- [ ] **Step 1: Create a small NSButton subclass for styling**

Create `Sources/SnatchCropperCLI/CropperRecordButton.swift`:

```swift
// Sources/SnatchCropperCLI/CropperRecordButton.swift
import AppKit

/// Pill-shaped "Record" button rendered next to the cropper rectangle.
/// Subclassed only to centralize styling — behavior is plain NSButton.
final class CropperRecordButton: NSButton {

    static let preferredSize = CGSize(width: 88, height: 28)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.title = "Record"
        self.bezelStyle = .rounded
        self.isBordered = true
        self.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        self.keyEquivalent = "" // Space/Return are owned by the view; don't fight.
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }
}
```

- [ ] **Step 2: Add the button as a subview of `CropperView`**

In `Sources/SnatchCropperCLI/CropperView.swift`, add a property for the button and create it during init. Inside the class, add:

```swift
    private let recordButton = CropperRecordButton(
        frame: NSRect(origin: .zero, size: CropperRecordButton.preferredSize)
    )
```

In the `init(frame:initialRegion:)` body, after `super.init(frame:)`, append:

```swift
        recordButton.target = self
        recordButton.action = #selector(recordButtonClicked(_:))
        recordButton.isHidden = true
        addSubview(recordButton)
```

Add the action method and a layout helper. Append inside the class:

```swift

    @objc private func recordButtonClicked(_ sender: Any?) {
        if let rect = state.committedRect {
            onRecord?(rect)
        }
    }

    override func layout() {
        super.layout()
        layoutRecordButton()
    }

    private func layoutRecordButton() {
        guard case .have(let rect) = state.mode else {
            recordButton.isHidden = true
            return
        }
        recordButton.isHidden = false
        let btnSize = CropperRecordButton.preferredSize
        // Placement: just below the rectangle's bottom-right, tucked back
        // inside the screen if the rect is near the bottom edge.
        var x = rect.maxX - btnSize.width
        var y = rect.maxY + 8
        if y + btnSize.height > bounds.height {
            // Fall back to inside the rect at the bottom-right.
            y = rect.maxY - btnSize.height - 8
        }
        x = max(0, min(x, bounds.width - btnSize.width))
        recordButton.frame = NSRect(x: x, y: y, width: btnSize.width, height: btnSize.height)
    }
```

Update the `state` property's `didSet` to also re-lay out the button:

```swift
    var state: CropperState {
        didSet {
            needsDisplay = true
            needsLayout = true
        }
    }
```

- [ ] **Step 3: Smoke-run end-to-end**

Run: `swift run snatch-cropper-cli`

Walk through:
1. Drag out a rectangle. On release, the **Record** button appears just below the rectangle's bottom-right corner, alongside the 8 handles.
2. Click **Record** → stdout prints `RECORD region=(…)`; app exits.
3. Run again. Drag a small rect near the bottom of the screen. The Record button repositions to stay inside the screen (overlapping the rect rather than spilling off).
4. Run again. Drag a rect, then drag a handle to resize. While resizing, the Record button is hidden (mode is `.resizing`); on release it returns.
5. Run again. While dragging out a fresh rect, the Record button is hidden (`.dragging` mode). On release it appears.

- [ ] **Step 4: Commit**

```bash
git add Sources/SnatchCropperCLI/CropperRecordButton.swift \
        Sources/SnatchCropperCLI/CropperView.swift
git commit -m "feat(cropper): floating Record button repositioned with the rectangle

NSButton subview, shown only in .have mode. Click → onRecord callback,
mirroring Space/Return. Repositions to stay on-screen when the rect
is near the bottom edge."
```

---

### Task 14: Region persistence round-trip — verify pre-draw on next launch

Region persistence has been wired through since Task 7 (`RegionStore`) and Task 12 (AppDelegate calls `regionStore.persist(region)` on Record). This task is the smoke test that closes the loop: drag → record → relaunch → expect the same rectangle pre-drawn with handles + Record button visible.

**Files:**
- *None.* This task is verification-only. If the test reveals a bug, fix it in the relevant file from Tasks 7/10/12 and add a regression test under `Tests/SnatchKitTests/` if it lands in the pure-logic layer.

- [ ] **Step 1: Establish a clean baseline**

The SPM-launched executable writes to a `UserDefaults` domain whose name depends on how the binary is invoked (typically the executable name, but it can vary). Find it before testing:

```bash
ls ~/Library/Preferences/ | grep -i snatch
```

If the file `snatch-cropper-cli.plist` (or similar) exists from a previous run, delete it to start clean:

```bash
rm -f ~/Library/Preferences/snatch-cropper-cli.plist
```

If nothing matches, the slate is already clean — proceed.

- [ ] **Step 2: First run — drag, record, exit**

Run: `swift run snatch-cropper-cli`
- Drag out a rectangle (any size). Note the rough region from the dimensions label.
- Click **Record** (or press Space).
- Expected: stdout prints `RECORD region=(x,y,w,h)` and the app exits.

- [ ] **Step 3: Confirm a defaults file now exists**

```bash
ls ~/Library/Preferences/ | grep -i snatch
```

Expected: a `snatch-cropper-cli.plist` (or similarly-named) file exists. The exact filename depends on the SPM launcher; it's the visual second-launch behavior in Step 4 that's authoritative.

- [ ] **Step 4: Second run — pre-draw**

Run: `swift run snatch-cropper-cli` again.

Expected:
- The previously-recorded rectangle is **already drawn** with handles + Record button visible. The dim has the cutout in the right place.
- No further mouse interaction needed: pressing Space / Return / clicking Record fires the same region back out.
- Esc cancels and exits without changing the persisted region.

If the rectangle is *not* pre-drawn on second launch, the bug is most likely in:
- `RegionStore.lastRegion` read path (Task 7) — re-run `swift test --filter RegionStoreTests`.
- `AppDelegate` not passing `regionStore.lastRegion` to `CropperWindow` (Task 9 / 10).
- `CropperView` init not converting screen-space → view-local coords correctly (Task 10).

- [ ] **Step 5: Drag a fresh rect over the pre-drawn one — confirm replacement**

With the pre-drawn rect visible from Step 4:
- Click-and-drag from a point **outside** the pre-drawn rect.
- Expected: the existing rect disappears mid-drag and a fresh one is drawn in its place. On release, the new rect is committed with handles + button.
- Press Record → new region prints to stdout.
- Run a third time → the third region is pre-drawn (overwrite confirmed).

- [ ] **Step 6: Clear and commit (no code changes expected; this is a verification gate)**

If no fix was needed, no commit. If you fixed something:

```bash
git add <fixed files>
git commit -m "fix(cropper): <specific issue> — exposed by Task 14 persistence smoke"
```

---

### Task 15: Manual smoke checklist + tag M3

Final integration smoke per spec §9, scoped to M3-relevant rows. Tag the milestone, update CLAUDE.md.

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Run the full test suite**

Run: `swift test`
Expected: all M1 + M2 + M3 tests green. M3 adds:
- `CropperHandleTests` (3)
- `CropperGeometryTests` (21 — 4 + 5 + 6 + 6)
- `CropperStateTests` (14)
- `RegionStoreTests` (6)

Total new from M3: **44 tests**. Combined with M2's 28 default + 1 gated, the full default-on count should be **~72 tests**, all green.

- [ ] **Step 2: Manual smoke checklist (per spec §9)**

Walk through each of these by hand. Each line must produce the expected behavior; if any fails, fix-and-retest before tagging.

- [ ] Drag a fresh rectangle from any corner direction (top-left → bottom-right, bottom-right → top-left, etc.). Live `W × H` label updates in real time.
- [ ] On release, 8 handles + Record button appear.
- [ ] Drag each of the 8 handles in turn; rect resizes correctly per spec §6 semantics. Edge handles move only one axis; corner handles move both.
- [ ] Drag inside the rectangle (not on a handle) — whole rect translates.
- [ ] Drag a corner handle past its opposite corner — rect normalizes (no negative-extent flicker).
- [ ] Click outside the rectangle — fresh drag replaces it.
- [ ] Click without drag from `.idle` (mouse-down + immediate mouse-up at the same point) — does **not** create a 0×0 rect; the cropper stays empty and dim.
- [ ] Click without drag *inside* a committed rect — no-op; the rect stays unchanged (mode briefly enters `.resizing(.body, …)` and exits via zero-delta mouseUp back to `.have`).
- [ ] Click without drag *outside* a committed rect — discards the rect and returns to empty dim. (Spec §6 specifies "click-and-drag" to replace; bare clicks taking the same path is the M3 behavior — flagged for M5 UX polish if jarring in practice.)
- [ ] Press Esc with no rect → stdout: `CANCELLED`; exits 0.
- [ ] Press Esc with a rect → stdout: `CANCELLED`; exits 0; persisted region from a previous run is **not** overwritten (verify by relaunching: the previously-recorded rect should still pre-draw, not the discarded one).
- [ ] Press Space with a committed rect → stdout: `RECORD region=(x,y,w,h)`.
- [ ] Press Return / Enter with a committed rect → same as Space.
- [ ] Press Space with no committed rect (`.idle`) → no-op; the cropper stays open.
- [ ] Click the **Record** button → stdout: `RECORD region=(x,y,w,h)`; exits 0.
- [ ] Relaunch after a successful Record → previous rect is pre-drawn.

- [ ] **Step 3: Update CLAUDE.md Status section**

In `CLAUDE.md`, replace the existing Status block with:

```markdown
## Status

- **M1 — Encoder smoke test ✅ Complete** (tag `m1-encoder-smoke-test`, commit `c4e53d7`). 11/11 unit tests pass; CLI produces a valid GIF.
- **M2 — Capture pipeline ✅ Complete** (tag `m2-capture-pipeline`). `SCStreamWrapper` + `FrameConverter` + `BridgeQueue` + `GifskiEncoder` end-to-end. `snatch-record-cli` records a region for a fixed duration and writes a GIF. Stop-latency measured well under the 500 ms target on M-series hardware.
- **M3 — Cropper UI ✅ Complete** (tag `m3-cropper-ui`). Pure cropper logic (`CropperHandle`, `CropperGeometry`, `CropperState`, `RegionStore`) lives in `SnatchKit` with full unit coverage. AppKit shell (`CropperWindow`, `CropperView`, `CropperRecordButton`, `AppDelegate`) lives in the new `SnatchCropperCLI` SPM target. Drag-to-create, 8 resize handles, body-drag-to-move, dimensions label, Record button, Space/Enter/Esc handling, region persistence across launches — all working.
- **M4 — Coordinator wiring** is next. `RecordingSession` state machine integrates Cropper + Capture + Encoder. Click Record → records → click stop → GIF saved. Hotkey not yet hooked up; menubar minimal.

We're on Swift Package Manager (`Package.swift`) for M1–M3. Xcode project transition was deferred from M3 to M5 — see `docs/superpowers/plans/2026-04-30-m3-cropper-ui.md` "Build system" rationale.
```

- [ ] **Step 4: Commit and tag**

```bash
git add CLAUDE.md
git commit -m "docs: M3 cropper UI complete"
git tag m3-cropper-ui
```

---

## Done criteria

M3 ships when ALL of the following hold:

1. `swift build` succeeds, no warnings.
2. `swift test` shows green for the full default suite, including the 44 new M3 tests:
   - `CropperHandleTests` (3)
   - `CropperGeometryTests` (21: `rect_*` ×4, `handleFrames_*` ×5, `hitTest_*` ×6, `resize_*` ×6)
   - `CropperStateTests` (14)
   - `RegionStoreTests` (6)
3. `swift run snatch-cropper-cli` opens a transparent overlay covering the main display. Esc → `CANCELLED` to stdout. Drag + Space/Return/click-Record → `RECORD region=(x,y,w,h)` to stdout.
4. Persisted region survives across runs: a successful Record on one launch causes the rectangle to be pre-drawn (with handles + Record button) on the next launch.
5. The full manual smoke checklist (Task 15 Step 2) passes.
6. The git tag `m3-cropper-ui` exists.
7. `CLAUDE.md` Status section reflects M3 done and notes the Xcode-deferred-to-M5 decision.

## Carry-overs to M4

These aren't bugs — they're known seams M4 will need to close:

- **`SnatchCropperCLI` is a stub harness, not the product.** M4's `RecordingSession` will use the same `CropperWindow` + `CropperView` + `RegionStore` files (lifted into the eventual app target), but the `AppDelegate.applicationDidFinishLaunching` flow that "show window → on Record print → exit" is M3-specific. M4's flow is "show cropper → on Record start `SCStreamWrapper` and `GifskiEncoder` → wait for stop signal → finish + save". The cropper view itself does not change; only its consumer.
- **Cropper does not yet exclude itself from `SCStream` capture.** Spec §6 says `CropperWindow` is added to the `SCContentFilter` exclusion list. M3 doesn't capture, so this is moot. M4 must pass the cropper window's `windowID` (or its `windowNumber`) to `SCStreamWrapper.start(...)` for exclusion. This may require `SCStreamWrapper.start` to grow an `excludingWindows: [SCWindow]` parameter, which is currently hardcoded to `[]` (see `Sources/SnatchKit/Capture/SCStreamWrapper.swift:88`).
- **No multi-display support.** M3 sizes the cropper to `NSScreen.main.frame`. M5 (per spec §5 pre-warm) will refresh display info on `NSApplication.didChangeScreenParametersNotification`; M3 does not handle reconfigure mid-session.
- **No pre-warm.** M5 will instantiate the cropper hidden at launch and `orderOut` it; M3 instantiates lazily in `applicationDidFinishLaunching` and immediately shows it. The latency target in spec §1 (< 100 ms hotkey → cropper-ready) is an M5 concern.
- **No Xcode project / `.app` bundle yet.** Documented above. M5 will lift `App/AppDelegate.swift` + `UI/Cropper/*` + `System/RegionStore.swift` into the new `Snatch.xcodeproj`. The file layout already matches spec §5; only the build system changes.
