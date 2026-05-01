# M5 Menubar App + Hotkey + Pre-warm Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the M4 cropper-driven CLI into a real macOS menubar app — `Snatch.app` — with a global ⇧⌘6 hotkey, pre-warmed cropper for sub-100ms hotkey-to-paint, partial-file sweep on launch, full Screen Recording permission flow with NSAlert + System Settings deep-link, post-stop chain (notification + clipboard + recents), Carbon Esc cancel-during-recording, and an Xcode project that produces a development-signed `.app` bundle.

**Architecture:** Mixed build — `Package.swift` keeps `SnatchKit` (pure logic + ScreenCaptureKit) and gains a new `SnatchAppKit` library target for the AppKit-bound cropper / overlay shells; `Snatch.xcodeproj` is added with one `App` target that depends on `SnatchAppKit` via Xcode's "Local Swift Package" mechanism. The three CLIs (`snatch-cli`, `snatch-record-cli`, `snatch-session-cli`) stay in SPM as headless dev tools. Backpressure refactor lands first (Lane A) — `ScreenRecordingPipeline` becomes a real producer/consumer with an independent encoder-side drain loop, clearing the existing `CMSampleBuffer` Sendable warning.

**Tech Stack:** Swift 5.10, macOS 14+, SwiftPM + Xcode (mixed), AppKit (NSStatusItem, NSWindow, NSAlert, NSPasteboard), SwiftUI (sparingly, for SF Symbols), ScreenCaptureKit, UserNotifications, Carbon (RegisterEventHotKey), gifski C-FFI (already vendored).

**Spec:** `docs/superpowers/specs/2026-05-01-m5-menubar-app-design.md`

**Workflow constraints (from prior sessions, do not deviate):**
- Work directly on `main`. **No git worktree.**
- Subagents must NOT run `git checkout`, `git switch`, `git reset --hard`, `git stash`, or any other destructive git command. Read-only inspection (`git log`, `git diff`, `git show`, `git status`) only. If a state recovery is needed, surface it to the human; do not self-heal.
- Manual smoke gates require a human at the keyboard.
- Suggested model assignments noted at the end of the plan.

---

## Pre-flight verification

Before starting any task, the executing agent (or human) must verify clean baseline state:

- [ ] **Verify branch.** Run: `git rev-parse --abbrev-ref HEAD`
  - Expected: `main`
- [ ] **Verify clean tree.** Run: `git status --porcelain`
  - Expected: empty output (no modified or untracked files)
- [ ] **Verify M4 baseline tag exists.** Run: `git tag --list m4-coordinator-wiring`
  - Expected: prints `m4-coordinator-wiring`
- [ ] **Verify HEAD matches the M4 commit.** Run: `git log -1 --oneline`
  - Expected: `810f366 docs: M4 coordinator wiring complete`
- [ ] **Verify tests are green.** Run: `swift test 2>&1 | tail -3`
  - Expected: `Test Suite 'All tests' passed at ...` (live-capture tests skipped without permission is OK)
- [ ] **Read the spec end-to-end.** Open `docs/superpowers/specs/2026-05-01-m5-menubar-app-design.md` and read sections 1–14 before Task 1. The spec is the authoritative source for *what* and *why*; this plan is the authoritative source for *how* and *in what order*.

---

## File structure

### New files in `SnatchKit` (Lane B/C/E components)

| Path | Responsibility |
|---|---|
| `Sources/SnatchKit/System/ScalePresetStore.swift` | UserDefaults persistence for `ScalePreset` |
| `Sources/SnatchKit/System/RecentRecordingsStore.swift` | UserDefaults persistence for last 5 saved-GIF URLs |
| `Sources/SnatchKit/System/PathProvider.swift` | Pure function for `~/Desktop/snatch-YYYY-MM-DD-HH-mm-ss.gif` |
| `Sources/SnatchKit/System/PermissionsCoordinator.swift` | TCC state machine (granted/denied/notDetermined) over `CGScreenCapturePermissionAdapter` |
| `Sources/SnatchKit/System/CGScreenCapturePermissionAdapter.swift` | Protocol + production impl wrapping `CGPreflightScreenCaptureAccess` / `CGRequestScreenCaptureAccess` (test seam) |
| `Sources/SnatchKit/System/PartialFileSweeper.swift` | Globs `~/Desktop/snatch-*.gif.partial` and unlinks on launch |
| `Sources/SnatchKit/System/ShareableContentCache.swift` | Cached `[SCDisplay]` + tracked overlay `SCWindow`s; reactive refresh |

### Modified files in `SnatchKit`

| Path | Change |
|---|---|
| `Sources/SnatchKit/Capture/BridgeQueue.swift` | Add `dequeueBlocking()`, `close()`, `drainAndDiscard()` |
| `Sources/SnatchKit/Coordinator/RecordingSession.swift` | Add `.cropping` state + `beginCropping()` + `cancelCropping()` |
| `Sources/SnatchKit/Coordinator/ScreenRecordingPipeline.swift` | Producer/consumer rewrite |
| `Sources/SnatchKit/Logging/Log.swift` | Add `menubar` + `permissions` categories |

### New SPM library target: `SnatchAppKit`

| Path | Source (moved-from) |
|---|---|
| `Sources/SnatchAppKit/CropperWindow.swift` | `Sources/SnatchSessionCLI/CropperWindow.swift` |
| `Sources/SnatchAppKit/CropperView.swift` | `Sources/SnatchSessionCLI/CropperView.swift` |
| `Sources/SnatchAppKit/CropperRecordButton.swift` | `Sources/SnatchSessionCLI/CropperRecordButton.swift` |
| `Sources/SnatchAppKit/RecordingOverlayWindow.swift` | `Sources/SnatchSessionCLI/RecordingOverlayWindow.swift` |
| `Sources/SnatchAppKit/RecordingStopButton.swift` | `Sources/SnatchSessionCLI/RecordingStopButton.swift` |

`Package.swift` gains the `SnatchAppKit` library target. `SnatchSessionCLI` switches its dependency from `["SnatchKit"]` to `["SnatchKit", "SnatchAppKit"]`. Xcode App target depends on `SnatchAppKit` via Xcode's "Local Swift Package" reference at the repo root (which transitively pulls SnatchKit + CGifski).

### Modified `SnatchSessionCLI` (CLI dev tool, simplified)

| Path | Change |
|---|---|
| `Sources/SnatchSessionCLI/AppDelegate.swift` | Rewritten: minimal headless harness — cropper → record → save (no menubar/hotkey/permission/pre-warm) |
| `Sources/SnatchSessionCLI/Args.swift` | Remove dead-code `ArgsError` enum; default `--output` to `PathProvider.nextOutputURL()` |
| `Sources/SnatchSessionCLI/main.swift` | Unchanged in shape; smaller after AppDelegate slims down |

### New: `Snatch.xcodeproj` + `App/` target sources

| Path | Responsibility |
|---|---|
| `Snatch.xcodeproj/` | Xcode project file (single `App` target) |
| `App/SnatchApp.swift` | `@main` entry point; instantiates `AppDelegate` |
| `App/AppDelegate.swift` | Full menubar lifecycle (sweep + component graph + pre-warm + subscriptions) |
| `App/MenubarCoordinator.swift` | Subscribes to `RecordingSession.$state`; drives cropper + overlay show/hide; permission alerts |
| `App/Info.plist` | `LSUIElement = YES`, `NSScreenCaptureUsageDescription` |
| `App/Snatch.entitlements` | Hardened-runtime + screen-capture entitlement |
| `App/Assets.xcassets/AppIcon.appiconset/` | Bundle icon (Dock-stub; never visible since LSUIElement) |
| `App/UI/Menubar/MenubarController.swift` | `NSStatusItem` + dropdown menu builder |
| `App/UI/Menubar/MenubarIconState.swift` | Pure mapping function `(PermissionState, SessionState) -> NSImage` (TDD'able) |
| `App/UI/Permission/PermissionAlertPresenter.swift` | `NSAlert` wrappers for denied + relaunch flows |
| `App/UI/System/HotkeyRegistrar.swift` | Carbon ⇧⌘6 + dynamic Esc registration |
| `App/UI/System/PasteboardWriter.swift` | `NSPasteboard.general` writer for file URLs |
| `App/UI/System/NotificationPresenter.swift` | `UNUserNotificationCenter` save + failure notifications |

(The 5 system adapters in the App target's `App/UI/System/` could equally live in `App/System/`; nesting under `UI/` is fine for now since they're consumed by UI code.)

### New tests (all in `Tests/SnatchKitTests/`)

| Path | Coverage |
|---|---|
| `BridgeQueueBlockingTests.swift` | Blocking dequeue, close, drainAndDiscard |
| `ScalePresetStoreTests.swift` | Round-trip, default, malformed-data fallback |
| `RecentRecordingsStoreTests.swift` | Add/cap/filter-missing-files/persistence |
| `PathProviderTests.swift` | Format string, locale, injectable home |
| `PermissionsCoordinatorTests.swift` | All TCC branches, cache, revocation observer |
| `PartialFileSweeperTests.swift` | Pattern matching, untouched non-matching, empty dir |

### Extended tests

| Path | Change |
|---|---|
| `Tests/SnatchKitTests/RecordingSessionTests.swift` | +6 tests for `beginCropping` / `cancelCropping` / `start` from `.cropping` |
| `Tests/SnatchKitTests/BridgeQueueTests.swift` | Existing tests stay; new tests in `BridgeQueueBlockingTests.swift` |

### Tests for App target (run via `xcodebuild test`)

| Path | Coverage |
|---|---|
| `Tests/AppTests/MenubarIconStateTests.swift` | Pure mapping function; 15 cells |

### Smoke-only (no unit tests)

`HotkeyRegistrar`, `MenubarController` (NSStatusItem + dropdown UI), `PasteboardWriter`, `NotificationPresenter`, `ShareableContentCache` (the `SCShareableContent.current` integration), `App/AppDelegate`, `App/MenubarCoordinator`, `PermissionAlertPresenter`, `Snatch.xcodeproj` build settings, end-to-end menubar app.

---

## Phase 1 — Backpressure refactor (Lane A)

This phase lands FIRST. It's an internal refactor of `ScreenRecordingPipeline` with no public-API changes. Subsequent phases build on the cleaner shape.

### Task 1: BridgeQueue blocking primitives

**Files:**
- Modify: `Sources/SnatchKit/Capture/BridgeQueue.swift`
- Test: `Tests/SnatchKitTests/BridgeQueueBlockingTests.swift` (new)

- [ ] **Step 1: Read the existing BridgeQueue.**

Read `Sources/SnatchKit/Capture/BridgeQueue.swift` end to end so you understand the existing locking discipline (single `NSLock`, all paths go through `lock.withLock`).

- [ ] **Step 2: Write failing tests for blocking primitives.**

Create `Tests/SnatchKitTests/BridgeQueueBlockingTests.swift`:

```swift
import XCTest
@testable import SnatchKit

final class BridgeQueueBlockingTests: XCTestCase {

    func test_dequeueBlocking_returnsItem_whenAlreadyAvailable() {
        let q = BridgeQueue<Int>(capacity: 4)
        q.enqueue(42)

        let result = q.dequeueBlocking()

        XCTAssertEqual(result, 42)
    }

    func test_dequeueBlocking_blocksUntilEnqueue() {
        let q = BridgeQueue<Int>(capacity: 4)
        let exp = expectation(description: "dequeueBlocking returns")

        DispatchQueue.global(qos: .userInitiated).async {
            let r = q.dequeueBlocking()
            XCTAssertEqual(r, 7)
            exp.fulfill()
        }

        // Enqueue from a different thread after a short delay — proves the
        // dequeueBlocking call was actually waiting.
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.05) {
            q.enqueue(7)
        }

        wait(for: [exp], timeout: 1.0)
    }

    func test_dequeueBlocking_returnsNil_afterClose() {
        let q = BridgeQueue<Int>(capacity: 4)
        let exp = expectation(description: "dequeueBlocking returns nil")

        DispatchQueue.global(qos: .userInitiated).async {
            let r = q.dequeueBlocking()
            XCTAssertNil(r)
            exp.fulfill()
        }

        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.05) {
            q.close()
        }

        wait(for: [exp], timeout: 1.0)
    }

    func test_dequeueBlocking_drainsRemainingItems_afterClose() {
        let q = BridgeQueue<Int>(capacity: 4)
        q.enqueue(1)
        q.enqueue(2)
        q.enqueue(3)
        q.close()

        XCTAssertEqual(q.dequeueBlocking(), 1)
        XCTAssertEqual(q.dequeueBlocking(), 2)
        XCTAssertEqual(q.dequeueBlocking(), 3)
        XCTAssertNil(q.dequeueBlocking())   // empty + closed
    }

    func test_drainAndDiscard_clearsItemsWithoutDelivering() {
        let q = BridgeQueue<Int>(capacity: 4)
        q.enqueue(10)
        q.enqueue(20)

        q.drainAndDiscard()

        XCTAssertEqual(q.count, 0)
        // After drainAndDiscard + close, dequeueBlocking returns nil immediately.
        q.close()
        XCTAssertNil(q.dequeueBlocking())
    }

    func test_enqueueAfterClose_isRejected_silently() {
        let q = BridgeQueue<Int>(capacity: 4)
        q.close()
        q.enqueue(99)

        // dequeueBlocking should return nil, not 99.
        XCTAssertNil(q.dequeueBlocking())
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail.**

Run: `swift test --filter BridgeQueueBlockingTests 2>&1 | tail -20`
Expected: compilation errors — `dequeueBlocking`, `close`, `drainAndDiscard` don't exist yet.

- [ ] **Step 4: Implement blocking primitives.**

Modify `Sources/SnatchKit/Capture/BridgeQueue.swift`. Add a `DispatchSemaphore` and an `isClosed` flag, alongside the existing lock-protected buffer:

```swift
import Foundation

public final class BridgeQueue<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: [T] = []
    private var _droppedCount: Int = 0
    private var _isClosed: Bool = false
    /// Counts items available for dequeue. `signal()` once per enqueue and
    /// once per `close()` to wake any waiting dequeuer.
    private let availability = DispatchSemaphore(value: 0)
    public let capacity: Int

    public init(capacity: Int) {
        self.capacity = max(0, capacity)
        self.buffer.reserveCapacity(self.capacity)
    }

    public var droppedCount: Int { lock.withLock { _droppedCount } }
    public var count: Int        { lock.withLock { buffer.count } }
    public var isClosed: Bool    { lock.withLock { _isClosed } }

    @discardableResult
    public func enqueue(_ item: T) -> Int {
        let shouldSignal = lock.withLock { () -> Bool in
            if _isClosed { return false }
            if capacity == 0 {
                _droppedCount += 1
                return false
            }
            if buffer.count >= capacity {
                buffer.removeFirst()
                _droppedCount += 1
            }
            buffer.append(item)
            return true
        }
        if shouldSignal { availability.signal() }
        return droppedCount
    }

    public func dequeue() -> T? {
        lock.withLock { buffer.isEmpty ? nil : buffer.removeFirst() }
    }

    public func drain() -> [T] {
        lock.withLock {
            let out = buffer
            buffer.removeAll(keepingCapacity: true)
            return out
        }
    }

    /// Blocks until an item is available, or returns nil after `close()`
    /// has been called and the queue has drained.
    public func dequeueBlocking() -> T? {
        availability.wait()
        return lock.withLock { () -> T? in
            if !buffer.isEmpty {
                return buffer.removeFirst()
            }
            // Closed + empty: re-signal so any other waiters also wake.
            if _isClosed { availability.signal() }
            return nil
        }
    }

    /// Marks the queue closed. Any blocked dequeuers wake; subsequent
    /// `enqueue` calls are silently rejected. Items already in the buffer
    /// are still delivered by `dequeueBlocking` until the buffer drains.
    public func close() {
        let wasClosed = lock.withLock { () -> Bool in
            if _isClosed { return true }
            _isClosed = true
            return false
        }
        if !wasClosed { availability.signal() }
    }

    /// Empties the buffer without delivering. Call before `close()` for
    /// the cancel path where in-flight items must not reach the consumer.
    public func drainAndDiscard() {
        lock.withLock {
            buffer.removeAll(keepingCapacity: true)
        }
    }
}
```

- [ ] **Step 5: Run all BridgeQueue tests.**

Run: `swift test --filter BridgeQueue 2>&1 | tail -20`
Expected: all `BridgeQueueTests` (existing) and `BridgeQueueBlockingTests` (new) pass.

- [ ] **Step 6: Run full test suite to ensure no regression.**

Run: `swift test 2>&1 | tail -5`
Expected: `Test Suite 'All tests' passed`.

- [ ] **Step 7: Commit.**

```bash
git add Sources/SnatchKit/Capture/BridgeQueue.swift Tests/SnatchKitTests/BridgeQueueBlockingTests.swift
git commit -m "feat(bridge): add dequeueBlocking, close, drainAndDiscard primitives"
```

---

### Task 2: ScreenRecordingPipeline producer/consumer rewrite

**Files:**
- Modify: `Sources/SnatchKit/Coordinator/ScreenRecordingPipeline.swift`
- Test (regression guard): existing `Tests/SnatchKitTests/RecordingSessionTests.swift`, `Tests/SnatchKitTests/ScreenRecordingPipelineTests.swift`, `Tests/SnatchKitTests/ScreenRecordingPipelineLiveTests.swift`

This is a refactor — no new tests. The M4 test suite is the regression guard.

- [ ] **Step 1: Re-read the current pipeline and the spec §6.**

Read `Sources/SnatchKit/Coordinator/ScreenRecordingPipeline.swift` (specifically the `start` body lines 44–105 and `stop`/`cancel`). Re-read spec §6 "Backpressure refactor" subsections "Target shape" and "Stop / cancel rewiring."

- [ ] **Step 2: Rewrite `ScreenRecordingPipeline.swift`.**

Replace the entire file with:

```swift
import Foundation
import CoreMedia
import CoreGraphics
import ScreenCaptureKit

/// Production `RecordingPipeline` impl. Producer/consumer over
/// `BridgeQueue`: the consume Task converts CMSampleBuffer → RGBAFrame and
/// enqueues; an independent encoder-side drain loop running on
/// `encoderQueue` dequeues blocking and calls `gifski_add_frame_rgba`.
///
/// Threading: `@unchecked Sendable`. Mutable state (`active`) is mutated
/// only inside `start`/`stop`/`cancel`, which `RecordingSession`'s state
/// machine serializes. Per-recording structures are owned by the
/// `ActiveSession` value and torn down before `active` is cleared.
public final class ScreenRecordingPipeline: RecordingPipeline, @unchecked Sendable {

    private let captureQueue = DispatchQueue(label: "co.snatch.capture", qos: .userInteractive)
    private let encoderQueue = DispatchQueue(label: "co.snatch.encoder", qos: .userInitiated)

    private struct ActiveSession {
        let wrapper: SCStreamWrapper
        let bridge: BridgeQueue<(RGBAFrame, TimeInterval)>
        let encoder: GifskiEncoder
        let outputURL: URL
        let consumeTask: Task<Void, Never>
        let consumerHandle: Task<Void, Never>
    }

    private var active: ActiveSession?

    public init() {}

    public var droppedFrames: Int {
        active?.bridge.droppedCount ?? 0
    }

    public func start(region: CGRect,
                      scale: ScalePreset,
                      fps: Int,
                      outputURL: URL,
                      excludingWindows: [SCWindow]) async throws {
        precondition(active == nil, "ScreenRecordingPipeline.start called while already active")

        let wrapper = SCStreamWrapper()
        let converter = FrameConverter()
        let bridge = BridgeQueue<(RGBAFrame, TimeInterval)>(capacity: 60)
        let encoder = try GifskiEncoder(outputURL: outputURL, quality: 90)
        let ptsAnchor = PTSAnchor()

        let stream = try await wrapper.start(
            region: region,
            scale: scale,
            fps: fps,
            queue: captureQueue,
            excludingWindows: excludingWindows
        )

        // Producer: consumes CMSampleBuffer from the SCStream's AsyncStream,
        // converts to RGBAFrame inside this Task body (so CMSampleBuffer
        // never crosses an actor boundary as a stored value), enqueues
        // into the bridge.
        let consumeTask = Task {
            for await sample in stream {
                guard let frame = converter.convert(sample) else { continue }
                let pts = sample.presentationTimeStamp.seconds
                let base = ptsAnchor.anchor(pts)
                bridge.enqueue((frame, pts - base))
            }
        }

        // Consumer: independent drain loop on encoderQueue. Honors
        // GifskiEncoder's "single serial queue" contract by running
        // synchronously on encoderQueue. Exits when bridge.close() is
        // called and the buffer drains.
        let consumerHandle = Task.detached(priority: .userInitiated) { [encoderQueue, bridge, encoder] in
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                encoderQueue.async {
                    while let (frame, pts) = bridge.dequeueBlocking() {
                        do {
                            try encoder.addFrame(frame, presentationTime: pts)
                        } catch {
                            Log.encoder.error("addFrame failed: \(String(describing: error), privacy: .public)")
                        }
                    }
                    cont.resume()
                }
            }
        }

        active = ActiveSession(
            wrapper: wrapper,
            bridge: bridge,
            encoder: encoder,
            outputURL: outputURL,
            consumeTask: consumeTask,
            consumerHandle: consumerHandle
        )
    }

    public func stop() async throws -> URL {
        guard let s = active else {
            preconditionFailure("ScreenRecordingPipeline.stop called with no active session")
        }
        await s.wrapper.stop()
        await s.consumeTask.value           // producer drains naturally
        s.bridge.close()                    // wakes consumer; remaining buffer drains
        await s.consumerHandle.value        // consumer exits

        defer { active = nil }

        let finishTask = Task.detached(priority: .userInitiated) { [encoder = s.encoder] in
            try await encoder.finish()
        }
        try await finishTask.value
        return s.outputURL
    }

    public func cancel() async {
        guard let s = active else { return }
        defer { active = nil }
        await s.wrapper.stop()
        await s.consumeTask.value
        s.bridge.drainAndDiscard()          // discard in-flight items
        s.bridge.close()
        await s.consumerHandle.value

        let cancelTask = Task.detached(priority: .userInitiated) { [encoder = s.encoder] in
            encoder.cancel()
        }
        await cancelTask.value
    }
}

private final class PTSAnchor: @unchecked Sendable {
    private let lock = NSLock()
    private var value: TimeInterval?
    func anchor(_ pts: TimeInterval) -> TimeInterval {
        lock.withLock {
            if value == nil { value = pts }
            return value!
        }
    }
}
```

- [ ] **Step 3: Run the M4 regression-guard test suite.**

Run: `swift test --filter "RecordingSession|ScreenRecordingPipeline" 2>&1 | tail -10`
Expected: all green except the live tests that require screen-recording permission (those skip).

- [ ] **Step 4: Run full test suite.**

Run: `swift test 2>&1 | tail -5`
Expected: `Test Suite 'All tests' passed`.

- [ ] **Step 5: Verify the CMSampleBuffer Sendable warning is gone.**

Run: `swift build 2>&1 | grep -i sendable | grep -i CMSampleBuffer`
Expected: empty output. (If a different file still has Sendable warnings about CMSampleBuffer, that's fine — only the `ScreenRecordingPipeline.swift` warning is in scope for this task.)

- [ ] **Step 6: Commit.**

```bash
git add Sources/SnatchKit/Coordinator/ScreenRecordingPipeline.swift
git commit -m "refactor(pipeline): producer/consumer with independent drain loop

Replaces the 1:1 capture-dispatches-encoder coupling with a real
producer/consumer over BridgeQueue. Producer Task converts
CMSampleBuffer to RGBAFrame inside its body (clearing the Sendable
warning); consumer is an independent drain loop on encoderQueue that
exits when bridge.close() is called.

Public API unchanged; M4 regression suite green."
```

---

### Task 3: Backpressure manual smoke test

This is a human-at-keyboard gate. The output of this task is a recorded smoke result; the agent doesn't pass/fail on its own.

**Files:** none (read-only verification)

- [ ] **Step 1: Build the SPM CLIs.**

Run: `swift build -c release 2>&1 | tail -3`
Expected: `Build complete!`

- [ ] **Step 2: Run a short recording smoke (sanity).**

Run: `swift run -c release snatch-record-cli --duration 5 --output /tmp/m5-task3-short.gif --region 0,0,1280,720`
Expected: `✅ Wrote /tmp/m5-task3-short.gif`, drops printed, latency under 500 ms. Open in QuickLook — animation plays.

- [ ] **Step 3: Run a sustained Retina-scale recording.**

Run: `swift run -c release snatch-record-cli --duration 30 --output /tmp/m5-task3-long.gif --region 0,0,2560,1440 --scale retina`
Expected: completes in ≈30 s + finish latency; final `bridge drops:` count is bounded (typically <50 on M-series); GIF is playable in QuickLook with no obvious encoder hangs.

- [ ] **Step 4: Verify no orphan partial files.**

Run: `ls /tmp/*.partial 2>&1`
Expected: no matches (or "No such file or directory").

- [ ] **Step 5: Record the smoke result in the commit message.**

Make a no-op commit (or amend the prior one) noting smoke results, e.g.:

```bash
git commit --allow-empty -m "smoke: backpressure refactor verified

- 5s @ 1280x720 standard: $XX ms stop-latency, $YY drops
- 30s @ 2560x1440 retina: $XX ms stop-latency, $YY drops
- No .partial orphans"
```

---

## Phase 2 — Persistence stores (Lane B)

All TDD. Tasks 4–6 are independent and can run in parallel if dispatched as subagents.

### Task 4: ScalePresetStore

**Files:**
- Create: `Sources/SnatchKit/System/ScalePresetStore.swift`
- Test: `Tests/SnatchKitTests/ScalePresetStoreTests.swift`

- [ ] **Step 1: Write failing tests.**

Create `Tests/SnatchKitTests/ScalePresetStoreTests.swift`:

```swift
import XCTest
@testable import SnatchKit

final class ScalePresetStoreTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "co.snatch.tests.ScalePresetStore.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults?.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func test_current_isStandard_byDefault() {
        let store = ScalePresetStore(defaults: defaults)
        XCTAssertEqual(store.current, .standard)
    }

    func test_current_returnsPersistedValue() {
        let store = ScalePresetStore(defaults: defaults)
        store.persist(.retina)
        XCTAssertEqual(store.current, .retina)
    }

    func test_persistedValue_survivesNewStoreInstance() {
        ScalePresetStore(defaults: defaults).persist(.compact)
        XCTAssertEqual(ScalePresetStore(defaults: defaults).current, .compact)
    }

    func test_current_returnsStandard_whenStoredValueIsMalformed() {
        defaults.set("not-a-preset", forKey: "scalePreset")
        XCTAssertEqual(ScalePresetStore(defaults: defaults).current, .standard)
    }

    func test_ScalePresetStore_isSendable() {
        let store = ScalePresetStore(defaults: defaults)
        Self._requireSendable(store)
    }

    private static func _requireSendable<T: Sendable>(_ value: T) {}
}
```

- [ ] **Step 2: Run tests; expect compile failure.**

Run: `swift test --filter ScalePresetStoreTests 2>&1 | tail -10`
Expected: `Cannot find 'ScalePresetStore' in scope`.

- [ ] **Step 3: Implement.**

Create `Sources/SnatchKit/System/ScalePresetStore.swift`:

```swift
import Foundation

/// UserDefaults-backed persistence for the user-selected `ScalePreset`.
/// Returns `.standard` for malformed or missing values — same forgiving
/// shape as `RegionStore`.
public final class ScalePresetStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "scalePreset") {
        self.defaults = defaults
        self.key = key
    }

    public var current: ScalePreset {
        guard let raw = defaults.string(forKey: key),
              let preset = ScalePreset(rawValue: raw) else {
            return .standard
        }
        return preset
    }

    public func persist(_ preset: ScalePreset) {
        defaults.set(preset.rawValue, forKey: key)
    }
}
```

- [ ] **Step 4: Run tests; expect green.**

Run: `swift test --filter ScalePresetStoreTests 2>&1 | tail -5`
Expected: all 5 tests pass.

- [ ] **Step 5: Commit.**

```bash
git add Sources/SnatchKit/System/ScalePresetStore.swift Tests/SnatchKitTests/ScalePresetStoreTests.swift
git commit -m "feat(system): ScalePresetStore (UserDefaults persistence)"
```

---

### Task 5: RecentRecordingsStore

**Files:**
- Create: `Sources/SnatchKit/System/RecentRecordingsStore.swift`
- Test: `Tests/SnatchKitTests/RecentRecordingsStoreTests.swift`

- [ ] **Step 1: Write failing tests.**

Create `Tests/SnatchKitTests/RecentRecordingsStoreTests.swift`:

```swift
import XCTest
@testable import SnatchKit

final class RecentRecordingsStoreTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        suiteName = "co.snatch.tests.RecentRecordings.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("snatch-recents-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        defaults?.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: tempDir)
        defaults = nil
        suiteName = nil
        tempDir = nil
        super.tearDown()
    }

    private func writeFile(_ name: String) -> URL {
        let url = tempDir.appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: Data())
        return url
    }

    func test_recents_isEmpty_byDefault() {
        let store = RecentRecordingsStore(defaults: defaults)
        XCTAssertEqual(store.recents(), [])
    }

    func test_add_prependsNewURL() {
        let store = RecentRecordingsStore(defaults: defaults)
        let a = writeFile("a.gif")
        let b = writeFile("b.gif")
        store.add(a)
        store.add(b)
        XCTAssertEqual(store.recents(), [b, a])
    }

    func test_add_capsAtFive_evictingOldest() {
        let store = RecentRecordingsStore(defaults: defaults)
        let urls = (1...6).map { writeFile("r\($0).gif") }
        for u in urls { store.add(u) }
        let recents = store.recents()
        XCTAssertEqual(recents.count, 5)
        XCTAssertEqual(recents.first, urls[5])  // most recent
        XCTAssertFalse(recents.contains(urls[0]))  // oldest evicted
    }

    func test_recents_filtersOutMissingFiles() {
        let store = RecentRecordingsStore(defaults: defaults)
        let kept = writeFile("keep.gif")
        let gone = writeFile("gone.gif")
        store.add(gone)
        store.add(kept)
        try? FileManager.default.removeItem(at: gone)

        XCTAssertEqual(store.recents(), [kept])
    }

    func test_persistedRecents_surviveNewStoreInstance() {
        let url = writeFile("persisted.gif")
        RecentRecordingsStore(defaults: defaults).add(url)
        XCTAssertEqual(RecentRecordingsStore(defaults: defaults).recents(), [url])
    }

    func test_RecentRecordingsStore_isSendable() {
        let store = RecentRecordingsStore(defaults: defaults)
        Self._requireSendable(store)
    }

    private static func _requireSendable<T: Sendable>(_ value: T) {}
}
```

- [ ] **Step 2: Run tests; expect compile failure.**

Run: `swift test --filter RecentRecordingsStoreTests 2>&1 | tail -10`
Expected: `Cannot find 'RecentRecordingsStore' in scope`.

- [ ] **Step 3: Implement.**

Create `Sources/SnatchKit/System/RecentRecordingsStore.swift`:

```swift
import Foundation

/// UserDefaults-backed list of the most recent saved recordings, capped at
/// 5. `recents()` filters out URLs whose file no longer exists at read
/// time — the menubar's Recent Recordings ▸ submenu rebuilds on every
/// `menuWillOpen`, so the filter cost is paid only when the user looks.
public final class RecentRecordingsStore: @unchecked Sendable {
    public static let cap = 5

    private let defaults: UserDefaults
    private let key: String
    private let fileManager: FileManager

    public init(defaults: UserDefaults = .standard,
                key: String = "recentRecordings",
                fileManager: FileManager = .default) {
        self.defaults = defaults
        self.key = key
        self.fileManager = fileManager
    }

    /// Returns last-saved-first. Filters out missing files at read time.
    public func recents() -> [URL] {
        guard let raw = defaults.array(forKey: key) as? [String] else { return [] }
        return raw.compactMap { URL(fileURLWithPath: $0) }
            .filter { fileManager.fileExists(atPath: $0.path) }
    }

    /// Prepends `url`. Trims to `cap`. Duplicate URLs are de-duplicated
    /// (the new entry wins).
    public func add(_ url: URL) {
        var existing = (defaults.array(forKey: key) as? [String]) ?? []
        existing.removeAll { $0 == url.path }
        existing.insert(url.path, at: 0)
        if existing.count > Self.cap {
            existing = Array(existing.prefix(Self.cap))
        }
        defaults.set(existing, forKey: key)
    }
}
```

- [ ] **Step 4: Run tests; expect green.**

Run: `swift test --filter RecentRecordingsStoreTests 2>&1 | tail -5`
Expected: all 6 tests pass.

- [ ] **Step 5: Commit.**

```bash
git add Sources/SnatchKit/System/RecentRecordingsStore.swift Tests/SnatchKitTests/RecentRecordingsStoreTests.swift
git commit -m "feat(system): RecentRecordingsStore with missing-file filter"
```

---

### Task 6: PathProvider

**Files:**
- Create: `Sources/SnatchKit/System/PathProvider.swift`
- Test: `Tests/SnatchKitTests/PathProviderTests.swift`

- [ ] **Step 1: Write failing tests.**

Create `Tests/SnatchKitTests/PathProviderTests.swift`:

```swift
import XCTest
@testable import SnatchKit

final class PathProviderTests: XCTestCase {

    func test_nextOutputURL_producesDesktopPathWithTimestampedFilename() {
        let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)
        let provider = PathProvider(home: home, timeZone: TimeZone(identifier: "UTC")!)
        // 2026-05-01 14:30:22 UTC
        let date = Date(timeIntervalSince1970: 1_777_465_822)

        let url = provider.nextOutputURL(now: date)

        XCTAssertEqual(url.path, "/Users/test/Desktop/snatch-2026-05-01-14-30-22.gif")
    }

    func test_nextOutputURL_isLocaleStable() {
        let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)
        let provider = PathProvider(home: home, timeZone: TimeZone(identifier: "UTC")!)
        let date = Date(timeIntervalSince1970: 0)  // 1970-01-01 00:00:00 UTC

        let url = provider.nextOutputURL(now: date)

        XCTAssertTrue(url.lastPathComponent.hasPrefix("snatch-1970-01-01-00-00-00"))
    }

    func test_nextOutputURL_defaultsToHomeDirectoryWhenInitWithoutArgs() {
        let provider = PathProvider()
        let url = provider.nextOutputURL()

        // Path always starts with the user's home, ends with .gif under Desktop.
        XCTAssertTrue(url.path.contains("/Desktop/snatch-"))
        XCTAssertEqual(url.pathExtension, "gif")
    }
}
```

- [ ] **Step 2: Run tests; expect compile failure.**

Run: `swift test --filter PathProviderTests 2>&1 | tail -10`
Expected: `Cannot find 'PathProvider' in scope`.

- [ ] **Step 3: Implement.**

Create `Sources/SnatchKit/System/PathProvider.swift`:

```swift
import Foundation

/// Pure function over `Date` and the user's home directory. Produces
/// `~/Desktop/snatch-YYYY-MM-DD-HH-mm-ss.gif`. Locale fixed to en_US_POSIX
/// to keep filenames consistent across user locale settings.
public struct PathProvider: Sendable {
    private let home: URL
    private let timeZone: TimeZone

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                timeZone: TimeZone = .current) {
        self.home = home
        self.timeZone = timeZone
    }

    public func nextOutputURL(now: Date = Date()) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        let stamp = formatter.string(from: now)
        return home
            .appendingPathComponent("Desktop", isDirectory: true)
            .appendingPathComponent("snatch-\(stamp).gif")
    }
}
```

- [ ] **Step 4: Run tests; expect green.**

Run: `swift test --filter PathProviderTests 2>&1 | tail -5`
Expected: all 3 tests pass.

- [ ] **Step 5: Commit.**

```bash
git add Sources/SnatchKit/System/PathProvider.swift Tests/SnatchKitTests/PathProviderTests.swift
git commit -m "feat(system): PathProvider for Desktop GIF auto-naming"
```

---

## Phase 3 — RecordingSession state extension (Lane D)

### Task 7: Add `.cropping` state, `beginCropping()`, `cancelCropping()`

**Files:**
- Modify: `Sources/SnatchKit/Coordinator/RecordingSession.swift`
- Test: `Tests/SnatchKitTests/RecordingSessionTests.swift` (extend)

- [ ] **Step 1: Read current RecordingSession.**

Read `Sources/SnatchKit/Coordinator/RecordingSession.swift` and `Tests/SnatchKitTests/RecordingSessionTests.swift` so you understand the existing 4-state machine and the FakeRecordingPipeline test fixture.

- [ ] **Step 2: Add failing tests at the end of RecordingSessionTests.swift.**

Append the following tests to `Tests/SnatchKitTests/RecordingSessionTests.swift` (don't replace existing tests; add to the same class):

```swift
    // MARK: - .cropping state (M5)

    func test_beginCropping_fromIdle_transitionsToCropping() async {
        let pipeline = FakeRecordingPipeline()
        let store = makeIsolatedRegionStore()
        let session = await RecordingSession(pipeline: pipeline, regionStore: store)

        await session.beginCropping()

        let state = await session.state
        XCTAssertEqual(state, .cropping)
    }

    func test_beginCropping_isIgnored_fromOtherStates() async throws {
        let pipeline = FakeRecordingPipeline()
        let store = makeIsolatedRegionStore()
        let session = await RecordingSession(pipeline: pipeline, regionStore: store)

        await session.beginCropping()
        await session.beginCropping()  // second call — already cropping
        XCTAssertEqual(await session.state, .cropping)

        try await session.start(region: r, scale: .standard, fps: 30,
                                outputURL: outURL, excludingWindows: [])
        await session.beginCropping()  // ignored — already recording
        XCTAssertEqual(await session.state, .recording)
    }

    func test_cancelCropping_fromCropping_transitionsToIdle() async {
        let pipeline = FakeRecordingPipeline()
        let store = makeIsolatedRegionStore()
        let session = await RecordingSession(pipeline: pipeline, regionStore: store)

        await session.beginCropping()
        await session.cancelCropping()

        XCTAssertEqual(await session.state, .idle)
        XCTAssertEqual(pipeline.cancelCalls, 0)  // no pipeline involved
    }

    func test_cancelCropping_fromIdle_isNoOp() async {
        let pipeline = FakeRecordingPipeline()
        let store = makeIsolatedRegionStore()
        let session = await RecordingSession(pipeline: pipeline, regionStore: store)

        await session.cancelCropping()

        XCTAssertEqual(await session.state, .idle)
    }

    func test_start_fromCropping_transitionsToRecording() async throws {
        let pipeline = FakeRecordingPipeline()
        let store = makeIsolatedRegionStore()
        let session = await RecordingSession(pipeline: pipeline, regionStore: store)

        await session.beginCropping()
        try await session.start(region: r, scale: .standard, fps: 30,
                                outputURL: outURL, excludingWindows: [])

        XCTAssertEqual(await session.state, .recording)
        XCTAssertEqual(pipeline.startCalls, 1)
    }

    func test_cancel_fromCropping_aliasesToCancelCropping() async {
        let pipeline = FakeRecordingPipeline()
        let store = makeIsolatedRegionStore()
        let session = await RecordingSession(pipeline: pipeline, regionStore: store)

        await session.beginCropping()
        await session.cancel()

        XCTAssertEqual(await session.state, .idle)
        XCTAssertEqual(pipeline.cancelCalls, 0)  // no pipeline.cancel; cropping has no pipeline
    }
```

If `r` and `outURL` aren't already declared at the top of the test class, add them next to the existing test fixtures (consult the existing tests for the established patterns — e.g., `private let r = CGRect(x: 0, y: 0, width: 100, height: 100)` and `private var outURL: URL!` initialized in setUp).

- [ ] **Step 3: Run new tests; expect failure.**

Run: `swift test --filter RecordingSessionTests 2>&1 | tail -20`
Expected: compilation errors — `beginCropping`, `cancelCropping`, `.cropping` don't exist.

- [ ] **Step 4: Modify RecordingSession.**

Edit `Sources/SnatchKit/Coordinator/RecordingSession.swift`. Add `.cropping` to the State enum and the two new methods. The existing `start` method needs to also accept `.cropping` as a valid origin state.

Specifically:

In the `State` enum:

```swift
public enum State: Equatable {
    case idle
    case cropping       // NEW
    case recording
    case finalizing
    case cancelling
}
```

Add the two new methods (place them near the existing `start` method):

```swift
/// Idle → Cropping. UI substate signaling region selection in progress.
/// No pipeline involved.
public func beginCropping() {
    guard state == .idle else {
        Log.coordinator.info("beginCropping ignored from state \(String(describing: self.state), privacy: .public)")
        return
    }
    Log.coordinator.info("beginCropping: .idle → .cropping")
    state = .cropping
}

/// Cropping → Idle. No-op from any other state. No pipeline involved.
public func cancelCropping() async {
    guard state == .cropping else {
        if state != .idle {
            Log.coordinator.info("cancelCropping ignored from state \(String(describing: self.state), privacy: .public)")
        }
        return
    }
    Log.coordinator.info("cancelCropping: .cropping → .idle")
    state = .idle
}
```

Modify the existing `start` method's guard so it accepts both `.idle` and `.cropping`:

```swift
public func start(...) async throws {
    guard state == .idle || state == .cropping else {
        Log.coordinator.info("start ignored from state \(String(describing: self.state), privacy: .public)")
        return
    }
    let from = state
    Log.coordinator.info("start: \(String(describing: from), privacy: .public) → .recording")
    // ...rest of body unchanged...
}
```

Modify the existing `cancel` method to handle `.cropping` as an alias for `cancelCropping`:

```swift
public func cancel() async {
    if state == .cropping {
        await cancelCropping()
        return
    }
    // ...existing recording-cancel logic unchanged...
}
```

- [ ] **Step 5: Run all RecordingSession tests; expect green.**

Run: `swift test --filter RecordingSessionTests 2>&1 | tail -10`
Expected: all M4 tests pass + the 6 new `.cropping` tests pass.

- [ ] **Step 6: Run full test suite.**

Run: `swift test 2>&1 | tail -5`
Expected: `Test Suite 'All tests' passed`.

- [ ] **Step 7: Commit.**

```bash
git add Sources/SnatchKit/Coordinator/RecordingSession.swift Tests/SnatchKitTests/RecordingSessionTests.swift
git commit -m "feat(coordinator): add .cropping state + beginCropping/cancelCropping

Promotes 'collecting a region' from an AppDelegate-local UI mode to a
real session state. start(region:) is callable from both .idle (CLI
path) and .cropping (menubar-app path); cancel() from .cropping aliases
to cancelCropping for symmetry. Purely additive — M4 tests still pass."
```

---

## Phase 4 — PermissionsCoordinator (Lane C, TDD-able portion)

### Task 8: PermissionsCoordinator + adapter seam

**Files:**
- Create: `Sources/SnatchKit/System/CGScreenCapturePermissionAdapter.swift`
- Create: `Sources/SnatchKit/System/PermissionsCoordinator.swift`
- Test: `Tests/SnatchKitTests/PermissionsCoordinatorTests.swift`

- [ ] **Step 1: Write failing tests.**

Create `Tests/SnatchKitTests/PermissionsCoordinatorTests.swift`:

```swift
import XCTest
@testable import SnatchKit

final class PermissionsCoordinatorTests: XCTestCase {

    final class FakeAdapter: CGScreenCapturePermissionAdapter, @unchecked Sendable {
        var preflightResult: Bool = false
        var requestResult: Bool = false
        var preflightCallCount = 0
        var requestCallCount = 0

        func preflight() -> Bool {
            preflightCallCount += 1
            return preflightResult
        }
        func request() -> Bool {
            requestCallCount += 1
            return requestResult
        }
    }

    func test_preflight_grantedAdapter_yieldsGrantedState() {
        let a = FakeAdapter(); a.preflightResult = true
        let coord = PermissionsCoordinator(adapter: a)
        let state = coord.preflight()
        XCTAssertEqual(state, .granted)
        XCTAssertEqual(coord.cachedState, .granted)
    }

    func test_preflight_falseAdapter_yieldsNotDeterminedInitially() {
        let a = FakeAdapter(); a.preflightResult = false
        let coord = PermissionsCoordinator(adapter: a)
        XCTAssertEqual(coord.preflight(), .notDetermined)
    }

    func test_request_grantsThenStateIsGranted() async {
        let a = FakeAdapter(); a.preflightResult = false; a.requestResult = true
        let coord = PermissionsCoordinator(adapter: a)
        _ = coord.preflight()
        let result = await coord.request()
        XCTAssertEqual(result, .granted)
        XCTAssertEqual(coord.cachedState, .granted)
        XCTAssertEqual(a.requestCallCount, 1)
    }

    func test_request_deniedThenStateIsDenied() async {
        let a = FakeAdapter(); a.preflightResult = false; a.requestResult = false
        let coord = PermissionsCoordinator(adapter: a)
        _ = coord.preflight()
        let result = await coord.request()
        XCTAssertEqual(result, .denied)
        XCTAssertEqual(coord.cachedState, .denied)
    }

    func test_grantedCache_shortCircuitsSubsequentPreflights() {
        let a = FakeAdapter(); a.preflightResult = true
        let coord = PermissionsCoordinator(adapter: a)
        _ = coord.preflight()
        a.preflightResult = false  // adapter changes underneath; cache should win

        XCTAssertEqual(coord.preflight(), .granted)
        XCTAssertEqual(a.preflightCallCount, 1)  // second call short-circuits
    }

    func test_revocationObserver_transitionsGrantedToDenied() {
        let a = FakeAdapter(); a.preflightResult = true
        let coord = PermissionsCoordinator(adapter: a)
        _ = coord.preflight()
        XCTAssertEqual(coord.cachedState, .granted)

        a.preflightResult = false
        coord.observeRevocation()  // simulates didBecomeActive re-check

        XCTAssertEqual(coord.cachedState, .denied)
    }

    func test_PermissionsCoordinator_publishesStateChanges() {
        let a = FakeAdapter(); a.preflightResult = false
        let coord = PermissionsCoordinator(adapter: a)
        var observed: [PermissionsCoordinator.PermissionState] = []
        let cancellable = coord.$state.sink { observed.append($0) }
        defer { cancellable.cancel() }

        _ = coord.preflight()
        a.preflightResult = true
        coord.observeRevocation()

        // Initial value, then after preflight (.notDetermined), then granted.
        XCTAssertTrue(observed.contains(.notDetermined))
        XCTAssertTrue(observed.contains(.granted))
    }
}
```

- [ ] **Step 2: Run tests; expect compile failure.**

Run: `swift test --filter PermissionsCoordinatorTests 2>&1 | tail -10`
Expected: `Cannot find 'PermissionsCoordinator' in scope`.

- [ ] **Step 3: Implement the adapter.**

Create `Sources/SnatchKit/System/CGScreenCapturePermissionAdapter.swift`:

```swift
import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Test seam over CoreGraphics's screen-capture permission API.
/// Production uses `LiveCGScreenCapturePermissionAdapter`; tests inject
/// `FakeAdapter` (defined in tests) implementing this protocol.
public protocol CGScreenCapturePermissionAdapter: Sendable {
    /// Returns true if the process currently has Screen Recording permission
    /// (per `CGPreflightScreenCaptureAccess`).
    func preflight() -> Bool

    /// Fires the system permission prompt if not yet asked; returns true
    /// after the user grants.
    func request() -> Bool
}

public struct LiveCGScreenCapturePermissionAdapter: CGScreenCapturePermissionAdapter {
    public init() {}

    public func preflight() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    public func request() -> Bool {
        CGRequestScreenCaptureAccess()
    }
}
```

- [ ] **Step 4: Implement PermissionsCoordinator.**

Create `Sources/SnatchKit/System/PermissionsCoordinator.swift`:

```swift
import Foundation
import Combine

/// Tracks Screen Recording permission state across the process lifetime.
/// Caches `.granted` (since once true, the running process can use it
/// freely). `.denied` and `.notDetermined` are differentiated by whether
/// `request()` has been called.
@MainActor
public final class PermissionsCoordinator: ObservableObject {

    public enum PermissionState: Equatable {
        case granted
        case denied
        case notDetermined
    }

    @Published public private(set) var state: PermissionState = .notDetermined

    public var cachedState: PermissionState { state }

    private let adapter: CGScreenCapturePermissionAdapter

    public init(adapter: CGScreenCapturePermissionAdapter = LiveCGScreenCapturePermissionAdapter()) {
        self.adapter = adapter
    }

    /// Synchronously checks the current TCC state. Once we've cached
    /// `.granted`, subsequent calls short-circuit (subsequent CG checks
    /// can return false intermittently in process; we trust our cache).
    @discardableResult
    public func preflight() -> PermissionState {
        if state == .granted { return .granted }
        let granted = adapter.preflight()
        if granted {
            state = .granted
        } else if state != .denied {
            // Don't downgrade from .denied → .notDetermined; deny is sticky.
            state = .notDetermined
        }
        Log.permissions.info("preflight → \(String(describing: self.state), privacy: .public)")
        return state
    }

    /// Fires the system prompt if not yet asked. After the user responds,
    /// state collapses to `.granted` or `.denied` for the rest of the
    /// process lifetime.
    public func request() async -> PermissionState {
        let granted = adapter.request()
        state = granted ? .granted : .denied
        Log.permissions.info("request → \(String(describing: self.state), privacy: .public)")
        return state
    }

    /// Re-runs preflight to detect revocation (e.g., user toggled off in
    /// System Settings). Call from `NSApplication.didBecomeActive` after
    /// returning from a background. Transitions `.granted → .denied` if
    /// the system now says false.
    public func observeRevocation() {
        let liveValue = adapter.preflight()
        if state == .granted && !liveValue {
            state = .denied
            Log.permissions.info("revoked: .granted → .denied")
        } else if state == .denied && liveValue {
            state = .granted
            Log.permissions.info("re-granted: .denied → .granted")
        }
    }
}
```

- [ ] **Step 5: Run tests; expect green.**

Run: `swift test --filter PermissionsCoordinatorTests 2>&1 | tail -10`
Expected: all 7 tests pass.

- [ ] **Step 6: Commit.**

```bash
git add Sources/SnatchKit/System/CGScreenCapturePermissionAdapter.swift \
        Sources/SnatchKit/System/PermissionsCoordinator.swift \
        Tests/SnatchKitTests/PermissionsCoordinatorTests.swift
git commit -m "feat(system): PermissionsCoordinator over CG adapter seam

Three TCC states (granted/denied/notDetermined). Caches .granted for
process lifetime; deny is sticky. observeRevocation() lets the menubar
app detect System-Settings-toggled changes on didBecomeActive."
```

---

## Phase 5 — Lifecycle utilities (Lane E)

### Task 9: PartialFileSweeper

**Files:**
- Create: `Sources/SnatchKit/System/PartialFileSweeper.swift`
- Test: `Tests/SnatchKitTests/PartialFileSweeperTests.swift`

- [ ] **Step 1: Write failing tests.**

Create `Tests/SnatchKitTests/PartialFileSweeperTests.swift`:

```swift
import XCTest
@testable import SnatchKit

final class PartialFileSweeperTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("snatch-sweeper-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
        super.tearDown()
    }

    private func write(_ name: String) -> URL {
        let url = tempDir.appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: Data())
        return url
    }

    private func exists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: tempDir.appendingPathComponent(name).path)
    }

    func test_sweep_deletesMatchingPartialFiles() {
        _ = write("snatch-2026-05-01-14-30-22.gif.partial")
        _ = write("snatch-2025-01-01-00-00-00.gif.partial")

        let result = PartialFileSweeper.sweep(directory: tempDir)

        XCTAssertEqual(result.count, 2)
        XCTAssertFalse(exists("snatch-2026-05-01-14-30-22.gif.partial"))
        XCTAssertFalse(exists("snatch-2025-01-01-00-00-00.gif.partial"))
    }

    func test_sweep_leavesNonMatchingFilesAlone() {
        _ = write("snatch-2026-05-01-14-30-22.gif.partial")
        _ = write("important.gif")
        _ = write("snatch-bad-name.partial")  // not the timestamped pattern
        _ = write("snatch-2026-05-01-14-30-22.gif")  // not .partial

        _ = PartialFileSweeper.sweep(directory: tempDir)

        XCTAssertFalse(exists("snatch-2026-05-01-14-30-22.gif.partial"))
        XCTAssertTrue(exists("important.gif"))
        XCTAssertTrue(exists("snatch-bad-name.partial"))
        XCTAssertTrue(exists("snatch-2026-05-01-14-30-22.gif"))
    }

    func test_sweep_emptyDirectory_returnsEmpty() {
        let result = PartialFileSweeper.sweep(directory: tempDir)
        XCTAssertEqual(result, [])
    }

    func test_sweep_nonexistentDirectory_returnsEmpty() {
        let bogus = tempDir.appendingPathComponent("does-not-exist", isDirectory: true)
        let result = PartialFileSweeper.sweep(directory: bogus)
        XCTAssertEqual(result, [])
    }
}
```

- [ ] **Step 2: Run tests; expect compile failure.**

Run: `swift test --filter PartialFileSweeperTests 2>&1 | tail -10`
Expected: `Cannot find 'PartialFileSweeper' in scope`.

- [ ] **Step 3: Implement.**

Create `Sources/SnatchKit/System/PartialFileSweeper.swift`:

```swift
import Foundation

/// Synchronously deletes orphaned `~/Desktop/snatch-YYYY-MM-DD-HH-mm-ss.gif.partial`
/// files left behind by previous crashes. Pattern is private to Snatch:
/// only `snatch-<10 hyphen-separated digits>.gif.partial` is deleted.
public enum PartialFileSweeper {
    /// Regex source: `^snatch-\d{4}-\d{2}-\d{2}-\d{2}-\d{2}-\d{2}\.gif\.partial$`
    private static let pattern = #"^snatch-\d{4}-\d{2}-\d{2}-\d{2}-\d{2}-\d{2}\.gif\.partial$"#

    /// Returns the list of URLs deleted. Best-effort: errors per-file are
    /// logged and skipped, not surfaced.
    @discardableResult
    public static func sweep(directory: URL,
                             fileManager: FileManager = .default) -> [URL] {
        guard let entries = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]) else {
            return []
        }
        let regex = try? NSRegularExpression(pattern: pattern)
        var deleted: [URL] = []
        for url in entries {
            let name = url.lastPathComponent
            guard let regex,
                  regex.numberOfMatches(in: name, range: NSRange(name.startIndex..., in: name)) == 1 else {
                continue
            }
            do {
                try fileManager.removeItem(at: url)
                deleted.append(url)
                Log.system.info("swept partial: \(name, privacy: .public)")
            } catch {
                Log.system.error("sweep failed for \(name, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }
        return deleted
    }
}
```

- [ ] **Step 4: Run tests; expect green.**

Run: `swift test --filter PartialFileSweeperTests 2>&1 | tail -10`
Expected: all 4 tests pass.

- [ ] **Step 5: Commit.**

```bash
git add Sources/SnatchKit/System/PartialFileSweeper.swift Tests/SnatchKitTests/PartialFileSweeperTests.swift
git commit -m "feat(system): PartialFileSweeper for crash-orphan cleanup"
```

---

### Task 10: ShareableContentCache

**Files:**
- Create: `Sources/SnatchKit/System/ShareableContentCache.swift`

This component is mostly smoke-tested (it integrates with `SCShareableContent.current`). It exposes a small synchronous read API and an async refresh.

- [ ] **Step 1: Implement.**

Create `Sources/SnatchKit/System/ShareableContentCache.swift`:

```swift
import Foundation
import AppKit
import ScreenCaptureKit

/// Caches `SCShareableContent.current` results so the hotkey path can
/// query exclusion windows without paying the 50–200 ms per-call cost.
/// Refreshes are triggered explicitly by the menubar app on launch and
/// in response to `didChangeScreenParametersNotification` /
/// `didActivateApplicationNotification`.
@MainActor
public final class ShareableContentCache {

    /// `SCWindow`s for our own overlay NSWindows that should be excluded
    /// from capture. Indexed by `NSWindow.windowNumber` (the Int we get
    /// from AppKit) so we can re-resolve after refreshes.
    public private(set) var ourWindowNumbers: Set<Int> = []
    public private(set) var lastRefreshError: Error?

    private var cachedContent: SCShareableContent?

    public init() {}

    /// Returns the cached `[SCWindow]` filtered to our registered
    /// overlay windowNumbers. May return empty if the cache hasn't been
    /// populated yet — callers must tolerate that and accept that
    /// overlays may appear in 1-2 frames before the pre-flight refresh.
    public func excludingWindows() -> [SCWindow] {
        guard let cachedContent else { return [] }
        return cachedContent.windows.filter {
            ourWindowNumbers.contains(Int($0.windowID))
        }
    }

    /// Register an NSWindow as an overlay to exclude from capture. Must
    /// be called AFTER the NSWindow has been ordered onscreen at least
    /// once so its windowNumber is valid.
    public func addOurWindow(_ window: NSWindow) {
        let n = window.windowNumber
        guard n > 0 else {
            Log.system.error("addOurWindow with invalid windowNumber \(n, privacy: .public)")
            return
        }
        ourWindowNumbers.insert(n)
    }

    public func contains(_ window: NSWindow) -> Bool {
        ourWindowNumbers.contains(window.windowNumber)
    }

    /// Async refresh from `SCShareableContent.current`. Errors are
    /// captured on `lastRefreshError`; the cache retains its previous
    /// value on failure (stale-but-usable).
    public func refresh() async {
        do {
            let content = try await SCShareableContent.current
            cachedContent = content
            lastRefreshError = nil
        } catch {
            lastRefreshError = error
            Log.system.error("ShareableContentCache.refresh failed: \(String(describing: error), privacy: .public)")
        }
    }
}
```

- [ ] **Step 2: Verify SnatchKit still compiles.**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`. (Adding AppKit import to `Sources/SnatchKit/System/ShareableContentCache.swift` is fine; SnatchKit already transitively links AppKit-bearing frameworks via SCKit.)

- [ ] **Step 3: Run full test suite.**

Run: `swift test 2>&1 | tail -5`
Expected: `Test Suite 'All tests' passed`.

- [ ] **Step 4: Commit.**

```bash
git add Sources/SnatchKit/System/ShareableContentCache.swift
git commit -m "feat(system): ShareableContentCache for hotkey-path excludingWindows"
```

---

## Phase 6 — Logging additions

### Task 11: Add Log.menubar and Log.permissions categories

**Files:**
- Modify: `Sources/SnatchKit/Logging/Log.swift`

This is a one-line change but lands here so the components in Tasks 8–10 (which already reference these categories in this plan) compile cleanly. **If you're executing strictly in order, do this task BEFORE running the test suites in Tasks 8 and 9** — otherwise `Log.permissions` and `Log.system` references will break compile. The plan ordering here assumes `Log.system` already exists (it does; it's used by existing M4 code) and only `Log.permissions` and `Log.menubar` are new. Task 8 references `Log.permissions`, so this task should land alongside Task 8 in practice.

**Recommended ordering**: do Task 11 first, then Tasks 8/9.

- [ ] **Step 1: Modify Log.swift.**

Replace the file's enum body to add two categories:

```swift
import Foundation
import os

public enum Log {
    private static let subsystem = "co.snatch.app"

    public static let capture     = Logger(subsystem: subsystem, category: "capture")
    public static let encoder     = Logger(subsystem: subsystem, category: "encoder")
    public static let coordinator = Logger(subsystem: subsystem, category: "coordinator")
    public static let ui          = Logger(subsystem: subsystem, category: "ui")
    public static let system      = Logger(subsystem: subsystem, category: "system")
    public static let menubar     = Logger(subsystem: subsystem, category: "menubar")
    public static let permissions = Logger(subsystem: subsystem, category: "permissions")
}
```

- [ ] **Step 2: Build.**

Run: `swift build 2>&1 | tail -3`
Expected: `Build complete!`.

- [ ] **Step 3: Commit.**

```bash
git add Sources/SnatchKit/Logging/Log.swift
git commit -m "feat(logging): add menubar + permissions categories"
```

---

## Phase 7 — SPM library split for AppKit shells

### Task 12: Introduce SnatchAppKit library target

**Files:**
- Modify: `Package.swift`
- Move (via `git mv`): five files from `Sources/SnatchSessionCLI/` to `Sources/SnatchAppKit/`

**Why this task:** Spec §7 says the AppKit-bound cropper / overlay shells move to `App/UI/` for the Xcode target. SPM target paths can't span directories, so leaving them only in `App/UI/` would break `snatch-session-cli`. The SnatchAppKit library target gives both the CLI (via SPM) and the Xcode App (via Local Swift Package) a shared owner.

- [ ] **Step 1: Read current Package.swift.**

Read `Package.swift` so you understand the existing target definitions and dependency graph.

- [ ] **Step 2: Move the AppKit shells via git mv.**

Run each command in order:

```bash
mkdir -p Sources/SnatchAppKit
git mv Sources/SnatchSessionCLI/CropperWindow.swift          Sources/SnatchAppKit/CropperWindow.swift
git mv Sources/SnatchSessionCLI/CropperView.swift            Sources/SnatchAppKit/CropperView.swift
git mv Sources/SnatchSessionCLI/CropperRecordButton.swift    Sources/SnatchAppKit/CropperRecordButton.swift
git mv Sources/SnatchSessionCLI/RecordingOverlayWindow.swift Sources/SnatchAppKit/RecordingOverlayWindow.swift
git mv Sources/SnatchSessionCLI/RecordingStopButton.swift    Sources/SnatchAppKit/RecordingStopButton.swift
```

- [ ] **Step 3: Update Package.swift to add the new target.**

Replace the contents of `Package.swift` with:

```swift
// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Snatch",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SnatchKit",    targets: ["SnatchKit"]),
        .library(name: "SnatchAppKit", targets: ["SnatchAppKit"]),
        .executable(name: "snatch-cli",         targets: ["SnatchCLI"]),
        .executable(name: "snatch-record-cli",  targets: ["SnatchRecordCLI"]),
        .executable(name: "snatch-session-cli", targets: ["SnatchSessionCLI"]),
    ],
    targets: [
        .systemLibrary(
            name: "CGifski",
            path: "vendor/gifski"
        ),
        .target(
            name: "SnatchKit",
            dependencies: ["CGifski"],
            path: "Sources/SnatchKit",
            linkerSettings: [
                .unsafeFlags(["-L", "vendor/gifski", "-lgifski"]),
            ]
        ),
        .target(
            name: "SnatchAppKit",
            dependencies: ["SnatchKit"],
            path: "Sources/SnatchAppKit"
        ),
        .testTarget(
            name: "SnatchKitTests",
            dependencies: ["SnatchKit"],
            path: "Tests/SnatchKitTests",
            resources: [.copy("Fixtures")]
        ),
        .executableTarget(
            name: "SnatchCLI",
            dependencies: ["SnatchKit"],
            path: "Sources/SnatchCLI"
        ),
        .executableTarget(
            name: "SnatchRecordCLI",
            dependencies: ["SnatchKit"],
            path: "Sources/SnatchRecordCLI"
        ),
        .executableTarget(
            name: "SnatchSessionCLI",
            dependencies: ["SnatchKit", "SnatchAppKit"],
            path: "Sources/SnatchSessionCLI"
        ),
    ]
)
```

- [ ] **Step 4: Update imports in moved files.**

The moved files previously imported only `SnatchKit` (or AppKit + SnatchKit). They now live in a new module — the `import SnatchKit` lines stay (they need types like `CropperState`, `CropperHandle` from SnatchKit).

For each file in `Sources/SnatchAppKit/`, verify the top imports look like:

```swift
import AppKit
import SnatchKit
```

(Some may have only `import AppKit` — add `import SnatchKit` if they reference any type defined in SnatchKit; the build will tell you.)

- [ ] **Step 5: Update Sources/SnatchSessionCLI/AppDelegate.swift imports.**

The AppDelegate imports the shells; add `import SnatchAppKit` at the top:

```swift
import AppKit
import SnatchKit
import SnatchAppKit  // NEW
```

- [ ] **Step 6: Build.**

Run: `swift build 2>&1 | tail -10`
Expected: `Build complete!`. If there are compile errors about unresolved types, add `import SnatchAppKit` or `import SnatchKit` to the file mentioned.

- [ ] **Step 7: Run full test suite.**

Run: `swift test 2>&1 | tail -5`
Expected: `Test Suite 'All tests' passed`.

- [ ] **Step 8: Run snatch-session-cli briefly to verify the CLI still launches.**

Run: `swift run snatch-session-cli --output /tmp/m5-task12-smoke.gif 2>&1 &
SCLI=$!; sleep 2; kill $SCLI 2>/dev/null; wait $SCLI 2>/dev/null; echo "$?"`

Expected: cropper appears briefly, then the kill stops the process. Exit code may be non-zero (we killed it) — that's fine; we're verifying it loads.

- [ ] **Step 9: Commit.**

```bash
git add Package.swift Sources/SnatchAppKit/ Sources/SnatchSessionCLI/AppDelegate.swift
git commit -m "refactor(spm): split AppKit shells into SnatchAppKit library

CropperWindow, CropperView, CropperRecordButton, RecordingOverlayWindow,
RecordingStopButton move from SnatchSessionCLI/ to a new SnatchAppKit
library target. Both snatch-session-cli (SPM) and the upcoming
Snatch.app (Xcode) consume them via this shared module."
```

---

### Task 13: SnatchSessionCLI default to PathProvider; remove ArgsError

**Files:**
- Modify: `Sources/SnatchSessionCLI/Args.swift`
- Modify: `Sources/SnatchSessionCLI/main.swift` (only if Args API changes are visible there)

- [ ] **Step 1: Read current Args.swift.**

Read `Sources/SnatchSessionCLI/Args.swift` and `Sources/SnatchSessionCLI/main.swift`. Note where `ArgsError` is referenced (per the spec it's never thrown) and where the `--output` default is set.

- [ ] **Step 2: Modify Args.swift.**

Remove the `ArgsError` enum entirely. Change the `--output` default to use `PathProvider.nextOutputURL()`. The exact diff depends on the existing code shape; the principle is:

- Delete the `enum ArgsError: Error { case ... }` declaration.
- Where `Args.output` is initialized to `URL(fileURLWithPath: "/tmp/snatch-session.gif")` or similar, change to `PathProvider().nextOutputURL()`.

If Args.swift's initializer takes a `default:` parameter, propagate the change there. If it parses argv inline, change the fallback expression directly.

After editing, the file should compile cleanly with no `ArgsError` references anywhere in `Sources/SnatchSessionCLI/`.

- [ ] **Step 3: Verify removal is complete.**

Run: `grep -rn 'ArgsError' Sources/ Tests/`
Expected: empty output.

- [ ] **Step 4: Build.**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`.

- [ ] **Step 5: Run full test suite.**

Run: `swift test 2>&1 | tail -5`
Expected: `Test Suite 'All tests' passed`.

- [ ] **Step 6: Commit.**

```bash
git add Sources/SnatchSessionCLI/Args.swift Sources/SnatchSessionCLI/main.swift
git commit -m "refactor(session-cli): default --output to PathProvider; drop dead ArgsError"
```

---

## Phase 8 — Xcode project setup

### Task 14: Create Snatch.xcodeproj with App target

**Files:**
- Create: `Snatch.xcodeproj/` (entire project bundle)
- Create: `App/SnatchApp.swift`
- Create: `App/AppDelegate.swift` (skeleton)
- Create: `App/Info.plist`
- Create: `App/Snatch.entitlements`
- Create: `App/Assets.xcassets/AppIcon.appiconset/Contents.json` (placeholder)

This task creates the Xcode project shell. Subsequent tasks fill in the real lifecycle. Most of this is by-hand setup in Xcode.

- [ ] **Step 1: Create the App/ directory and skeleton files.**

```bash
mkdir -p App/UI/Menubar App/UI/Permission App/UI/System App/Assets.xcassets/AppIcon.appiconset
```

- [ ] **Step 2: Create App/SnatchApp.swift.**

```swift
import AppKit

@main
final class SnatchApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)  // LSUIElement reinforcement
        app.run()
    }
}
```

- [ ] **Step 3: Create App/AppDelegate.swift skeleton.**

```swift
import AppKit
import SnatchKit
import SnatchAppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Tasks 15+ fill this in.
    }
}
```

- [ ] **Step 4: Create App/Info.plist.**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>Snatch</string>
    <key>CFBundleExecutable</key>
    <string>$(EXECUTABLE_NAME)</string>
    <key>CFBundleIdentifier</key>
    <string>co.snatch.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Snatch</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>© 2026 Snatch</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSScreenCaptureUsageDescription</key>
    <string>Snatch records GIFs of the screen regions you select.</string>
</dict>
</plist>
```

- [ ] **Step 5: Create App/Snatch.entitlements.**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.device.screen-capture</key>
    <true/>
</dict>
</plist>
```

- [ ] **Step 6: Create the Asset catalog placeholder.**

`App/Assets.xcassets/AppIcon.appiconset/Contents.json`:

```json
{
  "images" : [
    { "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

`App/Assets.xcassets/Contents.json`:

```json
{ "info" : { "author" : "xcode", "version" : 1 } }
```

(The AppIcon images themselves can be filled in later; macOS will use a generic icon as a fallback. Since `LSUIElement = YES` the icon doesn't appear in the Dock or app switcher anyway. This is a stub to keep the asset catalog valid.)

- [ ] **Step 7: Create Snatch.xcodeproj using Xcode (manual step).**

This step requires opening Xcode interactively. The agent should hand off to a human:

> **Human-in-the-loop step:** Open Xcode. File → New → Project → macOS → App. Configure:
> - Product Name: `Snatch`
> - Team: (your Apple Developer team)
> - Organization Identifier: `co.snatch`  (yields bundle id `co.snatch.app`)
> - Interface: AppKit App Delegate
> - Language: Swift
> - Storage: None (no Core Data)
> - Include Tests: yes (optional; leave unchecked for now to keep scope small)
>
> Save the project at the repo root so the path is `/Users/starship/src/snatch/Snatch.xcodeproj`. Xcode will create a `Snatch/` folder of starter sources — DELETE that folder after project creation; we'll replace it with our existing `App/` folder.
>
> Then in Xcode:
> 1. **Replace the auto-generated sources.** Drag `App/SnatchApp.swift`, `App/AppDelegate.swift`, `App/Info.plist`, `App/Snatch.entitlements`, `App/Assets.xcassets` into the project navigator under the `Snatch` group. Choose "Create folder references" if prompted (we want filesystem grouping). Remove the auto-generated `AppDelegate.swift`, `ContentView.swift`, `Snatch.entitlements`, `Info.plist`, `Assets.xcassets`, `SnatchApp.swift` (whatever the template generated) — keep only OUR files.
> 2. **Wire Info.plist.** Build Settings → Info.plist File → set to `App/Info.plist`. Disable "Generate Info.plist File" to use ours.
> 3. **Wire entitlements.** Build Settings → Code Signing Entitlements → set to `App/Snatch.entitlements`.
> 4. **Configure signing.** Signing & Capabilities tab on the App target → Team: select your team. Signing Certificate: Apple Development. Provisioning: Automatically managed.
> 5. **Add Hardened Runtime.** Signing & Capabilities → "+ Capability" → Hardened Runtime. Default settings.
> 6. **Add Local Swift Package.** File → Add Package Dependencies → Add Local… → select the repo root. Choose to add `SnatchAppKit` to the App target (this transitively pulls SnatchKit + CGifski).
> 7. **Verify deployment target.** Build Settings → Deployment Target → macOS 14.0.
> 8. **Verify the project builds.** Product → Build (⌘B). Should succeed with no errors.
>
> Commit the resulting `Snatch.xcodeproj/` directory and `App/` directory.

- [ ] **Step 8: Verify build from CLI.**

Run: `xcodebuild -project Snatch.xcodeproj -scheme App build 2>&1 | tail -10`
Expected: `** BUILD SUCCEEDED **`.

(If the scheme is named `Snatch` instead of `App`, adjust accordingly. If signing fails, the team ID isn't set — return to the Xcode setup step.)

- [ ] **Step 9: Verify the app launches.**

Run: `open $(xcodebuild -project Snatch.xcodeproj -scheme App -showBuildSettings 2>/dev/null | awk '/CODESIGNING_FOLDER_PATH/ {print $3}')`
Expected: app launches, nothing visible (LSUIElement, no AppDelegate body yet — empty AppDelegate.applicationDidFinishLaunching). Check Activity Monitor → Snatch is running. Quit via Activity Monitor or `pkill Snatch`.

- [ ] **Step 10: Commit.**

```bash
git add Snatch.xcodeproj App/
git commit -m "feat(xcode): add Snatch.xcodeproj with App target

Bundle id co.snatch.app, LSUIElement YES, hardened runtime + screen-
capture entitlement, app-sandbox off. Depends on SnatchAppKit via
Local Swift Package reference. Signing: Apple Development."
```

---

## Phase 9 — App lifecycle

### Task 15: AppDelegate component graph + cold launch sequence

**Files:**
- Modify: `App/AppDelegate.swift`
- Create: `App/MenubarCoordinator.swift`

This task wires up Phase 1 spec §4 launch sequence. The cropper/overlay show-hide observation is added in Task 17; permission flow in Task 18; menubar UI in Task 19. This task gives us a launchable shell that sweeps partials, builds the component graph, registers the hotkey, and shows a placeholder NSStatusItem.

- [ ] **Step 1: Implement AppDelegate.swift.**

Replace `App/AppDelegate.swift` with:

```swift
import AppKit
import Combine
import SnatchKit
import SnatchAppKit
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    // Component graph (allocated in applicationDidFinishLaunching).
    private var pipeline: ScreenRecordingPipeline!
    private var session: RecordingSession!
    private var regionStore: RegionStore!
    private var scaleStore: ScalePresetStore!
    private var recentsStore: RecentRecordingsStore!
    private var permissions: PermissionsCoordinator!
    private var pasteboard: PasteboardWriter!
    private var notifier: NotificationPresenter!
    private var pathProvider: PathProvider!
    private var shareableContent: ShareableContentCache!
    private var hotkeys: HotkeyRegistrar!
    private var cropperWindow: CropperWindow!
    private var recordingOverlay: RecordingOverlayWindow!
    private var menubar: MenubarController!
    private var coordinator: MenubarCoordinator!

    private var cancellables = Set<AnyCancellable>()
    private var statusItem: NSStatusItem!  // placeholder; real one in Task 19

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1) Sync sweep of partial files (spec §4 step 2)
        let desktop = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop", isDirectory: true)
        PartialFileSweeper.sweep(directory: desktop)

        // 2) Component graph (spec §4 step 3)
        regionStore      = RegionStore()
        scaleStore       = ScalePresetStore()
        recentsStore     = RecentRecordingsStore()
        permissions      = PermissionsCoordinator()
        pasteboard       = PasteboardWriter()
        notifier         = NotificationPresenter()
        pathProvider     = PathProvider()
        pipeline         = ScreenRecordingPipeline()
        session          = RecordingSession(pipeline: pipeline, regionStore: regionStore)
        shareableContent = ShareableContentCache()
        cropperWindow    = makeHiddenCropperWindow()
        recordingOverlay = makeHiddenRecordingOverlay()

        _ = permissions.preflight()

        coordinator = MenubarCoordinator(
            session: session,
            cropperWindow: cropperWindow,
            recordingOverlay: recordingOverlay,
            regionStore: regionStore,
            scaleStore: scaleStore,
            recentsStore: recentsStore,
            permissions: permissions,
            pasteboard: pasteboard,
            notifier: notifier,
            pathProvider: pathProvider,
            shareableContent: shareableContent
        )

        hotkeys = HotkeyRegistrar(handler: { [weak coordinator] in
            coordinator?.handleHotkey()
        })
        hotkeys.registerGlobal()

        // 3) Placeholder NSStatusItem so the user sees launch happened
        // (real MenubarController arrives in Task 19).
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "camera.viewfinder",
                                            accessibilityDescription: "Snatch")

        // 4) Async pre-warm
        Task.detached { [shareableContent] in
            await shareableContent?.refresh()
        }

        // 5) OS notification subscriptions
        NotificationCenter.default.addObserver(
            self, selector: #selector(displaysChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(workspaceActivated),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(appBecameActive),
            name: NSApplication.didBecomeActiveNotification, object: nil)

        Log.system.info("Snatch launched (sweep + graph + hotkey done)")
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeys?.unregisterAll()
        Task { await session?.cancel() }
    }

    @objc private func displaysChanged() {
        Task { await shareableContent?.refresh() }
    }

    @objc private func workspaceActivated() {
        Task { await shareableContent?.refresh() }
    }

    @objc private func appBecameActive() {
        permissions?.observeRevocation()
    }

    private func makeHiddenCropperWindow() -> CropperWindow {
        // Use a 1x1 frame at origin; resized on show in MenubarCoordinator.
        let win = CropperWindow(contentRect: NSRect(x: 0, y: 0, width: 1, height: 1))
        return win
    }

    private func makeHiddenRecordingOverlay() -> RecordingOverlayWindow {
        let win = RecordingOverlayWindow(contentRect: NSRect(x: 0, y: 0, width: 1, height: 1))
        return win
    }
}
```

(NB: `CropperWindow.init` and `RecordingOverlayWindow.init` shapes depend on what's in `Sources/SnatchAppKit/`. The above assumes a single-arg initializer taking `contentRect`. Adapt to whatever the existing M3+M4 code declares — read those files before writing this. If the existing initializers require a delegate/callback, pass placeholders and have `MenubarCoordinator` install the real callbacks.)

- [ ] **Step 2: Implement MenubarCoordinator.swift skeleton.**

Create `App/MenubarCoordinator.swift`:

```swift
import AppKit
import Combine
import SnatchKit
import SnatchAppKit

/// Mediates between the RecordingSession state machine and the AppKit
/// shells. Owns no business logic — just plumbing. Subsequent tasks
/// flesh out the show/hide and permission paths.
@MainActor
final class MenubarCoordinator {

    let session: RecordingSession
    let cropperWindow: CropperWindow
    let recordingOverlay: RecordingOverlayWindow
    let regionStore: RegionStore
    let scaleStore: ScalePresetStore
    let recentsStore: RecentRecordingsStore
    let permissions: PermissionsCoordinator
    let pasteboard: PasteboardWriter
    let notifier: NotificationPresenter
    let pathProvider: PathProvider
    let shareableContent: ShareableContentCache

    private var cancellables = Set<AnyCancellable>()
    private var lastCroppedRegion: CGRect = .zero

    init(session: RecordingSession,
         cropperWindow: CropperWindow,
         recordingOverlay: RecordingOverlayWindow,
         regionStore: RegionStore,
         scaleStore: ScalePresetStore,
         recentsStore: RecentRecordingsStore,
         permissions: PermissionsCoordinator,
         pasteboard: PasteboardWriter,
         notifier: NotificationPresenter,
         pathProvider: PathProvider,
         shareableContent: ShareableContentCache) {
        self.session = session
        self.cropperWindow = cropperWindow
        self.recordingOverlay = recordingOverlay
        self.regionStore = regionStore
        self.scaleStore = scaleStore
        self.recentsStore = recentsStore
        self.permissions = permissions
        self.pasteboard = pasteboard
        self.notifier = notifier
        self.pathProvider = pathProvider
        self.shareableContent = shareableContent

        installSubscriptions()
        installCropperCallbacks()
        installRecordingOverlayCallback()
    }

    func handleHotkey() {
        // Permission gate
        guard permissions.cachedState != .denied else {
            // PermissionAlertPresenter call lands in Task 18.
            return
        }
        if permissions.cachedState == .notDetermined {
            // Permission request flow lands in Task 18.
            return
        }
        Task { @MainActor in
            switch session.state {
            case .idle:                           session.beginCropping()
            case .cropping:                       await session.cancelCropping()
            case .recording:                      try? await session.stop()
            case .finalizing, .cancelling:        break
            }
        }
    }

    private func installSubscriptions() {
        // Task 17 fills this in.
    }

    private func installCropperCallbacks() {
        // Task 17 fills this in.
    }

    private func installRecordingOverlayCallback() {
        // Task 17 fills this in.
    }
}
```

- [ ] **Step 3: Stub HotkeyRegistrar so AppDelegate compiles.**

Create `App/UI/System/HotkeyRegistrar.swift`:

```swift
import AppKit
import Carbon.HIToolbox
import SnatchKit

/// Carbon-based global hotkey registration. ⇧⌘6 always; Esc dynamically
/// during recording. Real implementation lands in Task 20.
@MainActor
final class HotkeyRegistrar {
    private let handler: () -> Void

    init(handler: @escaping () -> Void) {
        self.handler = handler
    }

    func registerGlobal() {
        // Task 20.
    }

    func registerEsc() {
        // Task 20.
    }

    func unregisterEsc() {
        // Task 20.
    }

    func unregisterAll() {
        // Task 20.
    }
}
```

- [ ] **Step 4: Stub PasteboardWriter, NotificationPresenter, MenubarController.**

These are referenced by AppDelegate and will be implemented later. Stub them so the project compiles.

`App/UI/System/PasteboardWriter.swift`:

```swift
import AppKit

/// Writes a file URL to the general pasteboard so ⌘V pastes the file.
@MainActor
final class PasteboardWriter {
    init() {}

    func copy(fileURL: URL) {
        // Task 21.
    }
}
```

`App/UI/System/NotificationPresenter.swift`:

```swift
import Foundation
import UserNotifications

/// Presents save-success and failure notifications via UNUserNotificationCenter.
@MainActor
final class NotificationPresenter {
    init() {}

    func requestAuthorizationIfNeeded() async {
        // Task 21.
    }

    func present(savedURL: URL) {
        // Task 21.
    }

    func presentFailure(_ message: String) {
        // Task 21.
    }
}
```

(MenubarController stub will live alongside its real implementation in Task 19; for now, AppDelegate doesn't reference it directly — only the `coordinator` does. Skip until Task 19.)

- [ ] **Step 5: Build the App target.**

Run: `xcodebuild -project Snatch.xcodeproj -scheme App build 2>&1 | tail -10`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Run the app and verify launch behavior.**

Open the built `.app`. Expected:
- App icon appears in the menubar (placeholder camera-viewfinder).
- No Dock entry, no app-switcher entry.
- App stays running until quit via Activity Monitor.
- Console.app filter `subsystem == co.snatch.app` shows `Snatch launched (sweep + graph + hotkey done)`.

Quit the app.

- [ ] **Step 7: Commit.**

```bash
git add App/
git commit -m "feat(app): cold-launch component graph + partial-file sweep + status item

AppDelegate sweeps Desktop partials, builds the component graph, kicks
off async pre-warm of ShareableContentCache, installs OS notification
subscriptions for display/workspace/active changes. MenubarCoordinator
is the thin layer between RecordingSession and AppKit shells (filled
in by subsequent tasks). Stubs for HotkeyRegistrar / PasteboardWriter /
NotificationPresenter compile; behavior in Tasks 20-21."
```

---

### Task 16: MenubarIconState pure mapping function (TDD)

**Files:**
- Create: `App/UI/Menubar/MenubarIconState.swift`
- Create: `Tests/AppTests/MenubarIconStateTests.swift` (new test target — see step 1)

**Note on test target setup:** The App target uses xcodebuild for tests, not `swift test`. We add a test target inside `Snatch.xcodeproj` for this single test file (and any future App-target tests). If you skipped adding the test target during Task 14, do it now via Xcode UI: File → New → Target → macOS → Unit Testing Bundle, name `AppTests`, target the App. Add `Tests/AppTests/` as the source folder for the new target.

(If creating the test target is too much friction, an alternative is to host this test inside `Tests/SnatchKitTests/` by moving `MenubarIconState.swift` into SnatchKit's UI folder. But icon-state is App-specific; cleaner to keep it in App.)

- [ ] **Step 1: Add test target in Xcode (manual step).**

> **Human-in-the-loop step:** Open Xcode → File → New → Target → macOS → Unit Testing Bundle → Product Name `AppTests`, Target to be Tested: `App`. Set source path to `Tests/AppTests/`. Commit the project file change.

- [ ] **Step 2: Write failing tests.**

Create `Tests/AppTests/MenubarIconStateTests.swift`:

```swift
import XCTest
import AppKit
import SnatchKit
@testable import App

final class MenubarIconStateTests: XCTestCase {

    func test_denied_returnsExclamationIcon_regardlessOfSession() {
        for session in allSessionStates {
            let img = MenubarIconState.image(permission: .denied, session: session)
            XCTAssertEqual(img.systemSymbolName, "exclamationmark.triangle.fill",
                            "denied + \(session) should be exclamationmark, got \(String(describing: img.systemSymbolName))")
        }
    }

    func test_recording_withGrantedPermission_returnsRecordIcon() {
        let img = MenubarIconState.image(permission: .granted, session: .recording)
        XCTAssertEqual(img.systemSymbolName, "record.circle.fill")
    }

    func test_recording_withNotDeterminedPermission_returnsRecordIcon() {
        let img = MenubarIconState.image(permission: .notDetermined, session: .recording)
        XCTAssertEqual(img.systemSymbolName, "record.circle.fill")
    }

    func test_idleStates_returnCameraViewfinder() {
        let nonRecording: [RecordingSession.State] = [.idle, .cropping, .finalizing, .cancelling]
        for permission in [PermissionsCoordinator.PermissionState.granted, .notDetermined] {
            for session in nonRecording {
                let img = MenubarIconState.image(permission: permission, session: session)
                XCTAssertEqual(img.systemSymbolName, "camera.viewfinder",
                                "\(permission) + \(session) should be camera.viewfinder")
            }
        }
    }

    private let allSessionStates: [RecordingSession.State] = [
        .idle, .cropping, .recording, .finalizing, .cancelling
    ]
}

// Helper: NSImage from SF Symbols carries its symbol name; expose it for assertions.
private extension NSImage {
    var systemSymbolName: String? {
        let mirror = Mirror(reflecting: self)
        for child in mirror.children where child.label == "_systemSymbolName" {
            return child.value as? String
        }
        return nil
    }
}
```

(Note: NSImage doesn't publicly expose its symbol name. The tests above use a Mirror trick that relies on internal storage; if it doesn't work on your macOS version, switch to comparing image hashes or to an `enum MenubarIcon { case denied, recording, idle }` returned by the mapping function and constructing the NSImage at the call site. The latter is cleaner — see alternative implementation below.)

**Alternative: have the mapping return an enum, not an NSImage.** Replace the test body to assert against the enum:

```swift
import XCTest
import SnatchKit
@testable import App

final class MenubarIconStateTests: XCTestCase {

    func test_denied_returnsExclamation_regardlessOfSession() {
        for session in allSessionStates {
            XCTAssertEqual(MenubarIconState.icon(permission: .denied, session: session),
                           .permissionDenied)
        }
    }

    func test_recording_withGrantedOrNotDetermined_returnsRecording() {
        XCTAssertEqual(MenubarIconState.icon(permission: .granted, session: .recording), .recording)
        XCTAssertEqual(MenubarIconState.icon(permission: .notDetermined, session: .recording), .recording)
    }

    func test_idleStates_returnIdle() {
        let nonRecording: [RecordingSession.State] = [.idle, .cropping, .finalizing, .cancelling]
        for permission in [PermissionsCoordinator.PermissionState.granted, .notDetermined] {
            for session in nonRecording {
                XCTAssertEqual(MenubarIconState.icon(permission: permission, session: session), .idle)
            }
        }
    }

    private let allSessionStates: [RecordingSession.State] = [
        .idle, .cropping, .recording, .finalizing, .cancelling
    ]
}
```

Use the alternative (enum-based) form. It's robust and the NSImage construction lives at the call site in Task 19's `MenubarController`.

- [ ] **Step 3: Run test target; expect compile failure.**

Run: `xcodebuild -project Snatch.xcodeproj -scheme App test 2>&1 | tail -20`
Expected: errors about `MenubarIconState` not existing.

- [ ] **Step 4: Implement.**

Create `App/UI/Menubar/MenubarIconState.swift`:

```swift
import AppKit
import SnatchKit

enum MenubarIcon: Equatable {
    case idle
    case recording
    case permissionDenied
}

enum MenubarIconState {
    /// Pure mapping function. Permission denied takes priority; otherwise
    /// session.recording → recording icon; everything else → idle.
    static func icon(permission: PermissionsCoordinator.PermissionState,
                     session: RecordingSession.State) -> MenubarIcon {
        if permission == .denied { return .permissionDenied }
        return session == .recording ? .recording : .idle
    }

    /// Convenience NSImage producer for the mapping result.
    static func image(for icon: MenubarIcon) -> NSImage {
        switch icon {
        case .idle:
            let img = NSImage(systemSymbolName: "camera.viewfinder",
                              accessibilityDescription: "Snatch")!
            img.isTemplate = true
            return img
        case .recording:
            let cfg = NSImage.SymbolConfiguration(paletteColors: [.systemRed])
            let img = NSImage(systemSymbolName: "record.circle.fill",
                              accessibilityDescription: "Recording")!
                .withSymbolConfiguration(cfg)!
            return img
        case .permissionDenied:
            let cfg = NSImage.SymbolConfiguration(paletteColors: [.systemRed])
            let img = NSImage(systemSymbolName: "exclamationmark.triangle.fill",
                              accessibilityDescription: "Permission required")!
                .withSymbolConfiguration(cfg)!
            return img
        }
    }
}
```

- [ ] **Step 5: Run tests.**

Run: `xcodebuild -project Snatch.xcodeproj -scheme App test 2>&1 | tail -10`
Expected: tests pass.

- [ ] **Step 6: Commit.**

```bash
git add App/UI/Menubar/MenubarIconState.swift Tests/AppTests/MenubarIconStateTests.swift Snatch.xcodeproj
git commit -m "feat(menubar): MenubarIconState pure mapping (TDD)"
```

---

### Task 17: Cropper + RecordingOverlay show/hide via session.\$state

**Files:**
- Modify: `App/MenubarCoordinator.swift`

The cropper and overlay become visible based on `RecordingSession.state` transitions. This task installs the Combine subscription + cropper/overlay callbacks.

- [ ] **Step 1: Read CropperWindow + RecordingOverlayWindow init/callback signatures.**

Read `Sources/SnatchAppKit/CropperWindow.swift`, `Sources/SnatchAppKit/CropperView.swift`, `Sources/SnatchAppKit/RecordingOverlayWindow.swift`. Identify how the M4 SnatchSessionCLI hooks `onRecordRequested`, `onCancelled`, `onStop` callbacks. (These are public on the windows in M4.)

- [ ] **Step 2: Implement installSubscriptions / installCropperCallbacks / installRecordingOverlayCallback in MenubarCoordinator.**

Modify `App/MenubarCoordinator.swift`. Replace the three private methods with real implementations:

```swift
private func installSubscriptions() {
    session.$state
        .receive(on: RunLoop.main)
        .sink { [weak self] newState in
            self?.handleStateChange(newState)
        }
        .store(in: &cancellables)
}

private func handleStateChange(_ state: RecordingSession.State) {
    switch state {
    case .cropping:
        showCropper()
    case .recording:
        cropperWindow.orderOut(nil)
        showRecordingOverlay(region: lastCroppedRegion)
    case .finalizing, .cancelling:
        recordingOverlay.orderOut(nil)
    case .idle:
        cropperWindow.orderOut(nil)
        recordingOverlay.orderOut(nil)
    }
}

private func showCropper() {
    let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
        ?? NSScreen.main!
    cropperWindow.setFrame(screen.frame, display: false)

    if let last = regionStore.lastRegion {
        cropperWindow.preDrawRegion(last)  // M3 API; verify name in CropperWindow.swift
    } else {
        cropperWindow.clearPreDrawnRegion()  // verify or adapt to existing API
    }

    cropperWindow.orderFrontRegardless()
    cropperWindow.makeKey()
    if !shareableContent.contains(cropperWindow) {
        shareableContent.addOurWindow(cropperWindow)
    }
}

private func showRecordingOverlay(region: CGRect) {
    recordingOverlay.setFrame(region.insetBy(dx: -2, dy: -2), display: false)
    recordingOverlay.orderFrontRegardless()
    if !shareableContent.contains(recordingOverlay) {
        shareableContent.addOurWindow(recordingOverlay)
    }
}

private func installCropperCallbacks() {
    cropperWindow.onRecordRequested = { [weak self] region in
        guard let self else { return }
        Task { @MainActor in
            await self.handleRecordRequested(region: region)
        }
    }
    cropperWindow.onCancelled = { [weak self] in
        guard let self else { return }
        Task { @MainActor in
            await self.session.cancelCropping()
        }
    }
}

private func handleRecordRequested(region: CGRect) async {
    lastCroppedRegion = region
    let url = pathProvider.nextOutputURL()
    await shareableContent.refresh()
    let excluding = shareableContent.excludingWindows()
    do {
        try await session.start(
            region: region,
            scale: scaleStore.current,
            fps: 30,
            outputURL: url,
            excludingWindows: excluding
        )
    } catch {
        notifier.presentFailure("Recording failed to start: \(error.localizedDescription)")
        Log.coordinator.error("session.start failed: \(String(describing: error), privacy: .public)")
    }
}

private func installRecordingOverlayCallback() {
    recordingOverlay.onStop = { [weak self] in
        guard let self else { return }
        Task { @MainActor in
            await self.handleStopRequested()
        }
    }
}

private func handleStopRequested() async {
    do {
        let result = try await session.stop()
        pasteboard.copy(fileURL: result.outputURL)
        recentsStore.add(result.outputURL)
        notifier.present(savedURL: result.outputURL)
        Log.coordinator.info("saved \(result.outputURL.lastPathComponent, privacy: .public) drops=\(result.droppedFrames) latency=\(String(format: "%.1f", result.stopLatencyMs))ms")
    } catch {
        notifier.presentFailure("Recording failed: \(error.localizedDescription)")
        Log.coordinator.error("session.stop failed: \(String(describing: error), privacy: .public)")
    }
}
```

(API names like `onRecordRequested`, `preDrawRegion`, `clearPreDrawnRegion`, `onStop` are taken from spec/M4 design docs; verify against actual CropperWindow / RecordingOverlayWindow code and adjust to whatever the existing APIs expose. If `clearPreDrawnRegion` doesn't exist, adapt or add a one-line method.)

- [ ] **Step 3: Build.**

Run: `xcodebuild -project Snatch.xcodeproj -scheme App build 2>&1 | tail -10`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Run all tests.**

Run: `swift test 2>&1 | tail -3 && xcodebuild -project Snatch.xcodeproj -scheme App test 2>&1 | tail -3`
Expected: both green.

- [ ] **Step 5: Commit.**

```bash
git add App/MenubarCoordinator.swift
git commit -m "feat(coordinator): wire session.state to cropper + overlay show/hide"
```

---

### Task 18: Permission flow modals + relaunch

**Files:**
- Create: `App/UI/Permission/PermissionAlertPresenter.swift`
- Modify: `App/MenubarCoordinator.swift`

- [ ] **Step 1: Implement PermissionAlertPresenter.**

Create `App/UI/Permission/PermissionAlertPresenter.swift`:

```swift
import AppKit
import SnatchKit

@MainActor
final class PermissionAlertPresenter {
    /// Shown when the user triggers ⇧⌘6 / record while permission is denied.
    /// Returns true if the user clicked "Open System Settings".
    @discardableResult
    func showDeniedAlert() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Screen Recording permission required"
        alert.informativeText = """
        Snatch needs permission to capture your screen to make GIFs.

        You can grant this in System Settings → Privacy & Security → Screen Recording.
        """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string:
                "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
            return true
        }
        return false
    }

    /// Shown after the user grants permission via the system prompt. The
    /// process must relaunch for the new TCC state to take effect.
    func showRelaunchAlert() {
        let alert = NSAlert()
        alert.messageText = "Permission granted"
        alert.informativeText = """
        Snatch needs to relaunch once to start recording. Click below to quit and reopen.
        """
        alert.addButton(withTitle: "Quit & Relaunch")
        alert.addButton(withTitle: "Quit")
        alert.alertStyle = .informational
        NSApp.activate(ignoringOtherApps: true)

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            relaunchSelf()
        } else {
            NSApp.terminate(nil)
        }
    }

    private func relaunchSelf() {
        let bundleURL = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = false
        Task { @MainActor in
            do {
                try await NSWorkspace.shared.openApplication(at: bundleURL, configuration: config)
            } catch {
                Log.system.error("relaunch failed: \(String(describing: error), privacy: .public)")
            }
            NSApp.terminate(nil)
        }
    }
}
```

- [ ] **Step 2: Wire MenubarCoordinator to use it.**

Modify `App/MenubarCoordinator.swift`. Add a `permissionAlerts: PermissionAlertPresenter` stored property, instantiate it in init, and update `handleHotkey` to use it:

```swift
let permissionAlerts: PermissionAlertPresenter

init(...) {
    // existing ...
    self.permissionAlerts = PermissionAlertPresenter()
    // existing ...
}

func handleHotkey() {
    if permissions.cachedState == .denied {
        permissionAlerts.showDeniedAlert()
        return
    }
    if permissions.cachedState == .notDetermined {
        Task { @MainActor in
            let result = await permissions.request()
            switch result {
            case .granted:        self.permissionAlerts.showRelaunchAlert()
            case .denied:         self.permissionAlerts.showDeniedAlert()
            case .notDetermined:  self.permissionAlerts.showDeniedAlert()  // dismissed prompt
            }
        }
        return
    }
    // Permission OK — route by session state:
    Task { @MainActor in
        switch session.state {
        case .idle:                           session.beginCropping()
        case .cropping:                       await session.cancelCropping()
        case .recording:                      try? await session.stop()
        case .finalizing, .cancelling:        break
        }
    }
}
```

- [ ] **Step 3: Build.**

Run: `xcodebuild -project Snatch.xcodeproj -scheme App build 2>&1 | tail -10`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Manual smoke (will exercise more thoroughly in Task 25).**

Build and launch. The hotkey isn't wired yet (Task 20), so we can't trigger this flow from a keypress — but you can write a temporary debug test in MenubarCoordinator that calls `permissions.request()` and confirms the modals appear. Discard the debug code before committing.

- [ ] **Step 5: Commit.**

```bash
git add App/UI/Permission/PermissionAlertPresenter.swift App/MenubarCoordinator.swift
git commit -m "feat(permission): NSAlert-based denied + relaunch flow"
```

---

### Task 19: MenubarController — NSStatusItem + dropdown + state subscriptions

**Files:**
- Create: `App/UI/Menubar/MenubarController.swift`
- Modify: `App/AppDelegate.swift` (replace placeholder NSStatusItem with MenubarController)

- [ ] **Step 1: Implement MenubarController.**

Create `App/UI/Menubar/MenubarController.swift`:

```swift
import AppKit
import Combine
import SnatchKit

@MainActor
final class MenubarController: NSObject {

    private let session: RecordingSession
    private let scaleStore: ScalePresetStore
    private let recentsStore: RecentRecordingsStore
    private let permissions: PermissionsCoordinator
    private let onStartRecording: () -> Void

    private let statusItem: NSStatusItem
    private var cancellables = Set<AnyCancellable>()

    init(session: RecordingSession,
         scaleStore: ScalePresetStore,
         recentsStore: RecentRecordingsStore,
         permissions: PermissionsCoordinator,
         onStartRecording: @escaping () -> Void) {
        self.session = session
        self.scaleStore = scaleStore
        self.recentsStore = recentsStore
        self.permissions = permissions
        self.onStartRecording = onStartRecording
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked(_:))
        statusItem.button?.sendAction(on: [.leftMouseUp])

        installIconSubscription()
    }

    private func installIconSubscription() {
        permissions.$state
            .combineLatest(session.$state)
            .receive(on: RunLoop.main)
            .sink { [weak self] perm, sess in
                guard let self, let button = self.statusItem.button else { return }
                let icon = MenubarIconState.icon(permission: perm, session: sess)
                button.image = MenubarIconState.image(for: icon)
            }
            .store(in: &cancellables)
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        // While recording, click stops immediately — no menu.
        if session.state == .recording {
            Task { @MainActor in try? await session.stop() }
            return
        }
        // Otherwise show the dropdown.
        let menu = buildMenu()
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil  // detach so the next single-click works
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        let start = NSMenuItem(title: "Start Recording", action: #selector(startRecordingAction), keyEquivalent: "6")
        start.keyEquivalentModifierMask = [.shift, .command]
        start.target = self
        menu.addItem(start)

        menu.addItem(NSMenuItem.separator())

        // Scale ▸
        let scaleItem = NSMenuItem(title: "Scale", action: nil, keyEquivalent: "")
        let scaleSub = NSMenu()
        for preset in [ScalePreset.retina, .standard, .compact] {
            let item = NSMenuItem(title: scaleLabel(preset), action: #selector(setScaleAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset
            item.state = (scaleStore.current == preset) ? .on : .off
            scaleSub.addItem(item)
        }
        scaleItem.submenu = scaleSub
        menu.addItem(scaleItem)

        // Recent Recordings ▸  (built lazily in menuWillOpen via delegate)
        let recentItem = NSMenuItem(title: "Recent Recordings", action: nil, keyEquivalent: "")
        recentItem.submenu = NSMenu()
        recentItem.tag = MenubarController.recentsTag
        menu.addItem(recentItem)

        menu.addItem(NSMenuItem.separator())

        let about = NSMenuItem(title: "About Snatch", action: #selector(aboutAction), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        let quit = NSMenuItem(title: "Quit Snatch", action: #selector(quitAction), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    private func scaleLabel(_ preset: ScalePreset) -> String {
        switch preset {
        case .retina:   return "Retina (2×)"
        case .standard: return "Standard (1×)"
        case .compact:  return "Compact (0.5×)"
        }
    }

    private static let recentsTag = 4242

    @objc private func startRecordingAction() {
        onStartRecording()
    }

    @objc private func setScaleAction(_ sender: NSMenuItem) {
        guard let preset = sender.representedObject as? ScalePreset else { return }
        scaleStore.persist(preset)
    }

    @objc private func aboutAction() {
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func quitAction() {
        NSApp.terminate(nil)
    }

    @objc private func openRecentAction(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

extension MenubarController: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        // Rebuild Recent Recordings ▸ submenu from current store.
        guard let recentItem = menu.item(withTag: Self.recentsTag),
              let sub = recentItem.submenu else { return }
        sub.removeAllItems()

        let recents = recentsStore.recents()
        if recents.isEmpty {
            let none = NSMenuItem(title: "(none)", action: nil, keyEquivalent: "")
            none.isEnabled = false
            sub.addItem(none)
        } else {
            for url in recents {
                let it = NSMenuItem(title: url.lastPathComponent,
                                    action: #selector(openRecentAction(_:)),
                                    keyEquivalent: "")
                it.target = self
                it.representedObject = url
                sub.addItem(it)
            }
        }
    }
}
```

- [ ] **Step 2: Wire MenubarController into AppDelegate.**

Modify `App/AppDelegate.swift`:

Remove the placeholder `statusItem` lines:

```swift
// REMOVE these:
statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
statusItem.button?.image = NSImage(systemSymbolName: "camera.viewfinder", ...)
```

Replace with:

```swift
menubar = MenubarController(
    session: session,
    scaleStore: scaleStore,
    recentsStore: recentsStore,
    permissions: permissions,
    onStartRecording: { [weak coordinator] in
        coordinator?.handleHotkey()
    }
)
```

(Also remove the `private var statusItem: NSStatusItem!` property declaration; `MenubarController` owns its own status item.)

- [ ] **Step 3: Build.**

Run: `xcodebuild -project Snatch.xcodeproj -scheme App build 2>&1 | tail -10`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Manual smoke.**

Launch the app. Click the menubar icon → dropdown appears with Start Recording / Scale / Recent / About / Quit. Hover Scale → submenu shows three presets, current marked. Click About → standard about panel. Click Quit → app terminates.

- [ ] **Step 5: Commit.**

```bash
git add App/UI/Menubar/MenubarController.swift App/AppDelegate.swift
git commit -m "feat(menubar): NSStatusItem + dropdown + scale/recents/about/quit"
```

---

## Phase 10 — Hotkey integration

### Task 20: HotkeyRegistrar (Carbon ⇧⌘6 + dynamic Esc)

**Files:**
- Modify: `App/UI/System/HotkeyRegistrar.swift`
- Modify: `App/MenubarCoordinator.swift` (subscribe to .recording state to register Esc dynamically)

This is a smoke-only component. Carbon EventHotKey APIs are imperative and tricky to unit-test cleanly.

- [ ] **Step 1: Implement HotkeyRegistrar.**

Replace `App/UI/System/HotkeyRegistrar.swift`:

```swift
import AppKit
import Carbon.HIToolbox
import SnatchKit

/// Carbon-based global hotkey registration. Uses `RegisterEventHotKey`
/// (pre-routed; intercepts before the focused app sees the keypress)
/// rather than `NSEvent.addGlobalMonitorForEvents` (post-routed).
@MainActor
final class HotkeyRegistrar {
    private let handler: () -> Void
    private let escHandler: () -> Void
    private var globalHotKeyRef: EventHotKeyRef?
    private var escHotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    private static let globalHotKeyID: UInt32 = 1
    private static let escHotKeyID: UInt32 = 2
    private static let signature: OSType = OSType(0x534E4348)  // 'SNCH'

    /// Static dispatch table — Carbon callbacks can't capture `self`.
    private static var routes: [UInt32: () -> Void] = [:]

    init(onGlobal: @escaping () -> Void, onEsc: @escaping () -> Void) {
        self.handler = onGlobal
        self.escHandler = onEsc
    }

    /// Convenience init for the original single-callback shape used in
    /// AppDelegate; routes to onGlobal only. Esc is unused unless
    /// `registerEsc()` is called separately.
    convenience init(handler: @escaping () -> Void) {
        self.init(onGlobal: handler, onEsc: {})
    }

    func registerGlobal() {
        installEventHandlerOnce()
        Self.routes[Self.globalHotKeyID] = handler

        // ⇧⌘6 — keyCode 22 ('6' on US layout) + cmd + shift
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.signature, id: Self.globalHotKeyID)
        let modifiers: UInt32 = UInt32(cmdKey | shiftKey)
        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_6),
            modifiers,
            id,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status != noErr {
            Log.system.error("RegisterEventHotKey ⇧⌘6 failed: \(status, privacy: .public)")
            return
        }
        globalHotKeyRef = ref
    }

    func registerEsc() {
        installEventHandlerOnce()
        Self.routes[Self.escHotKeyID] = escHandler

        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.signature, id: Self.escHotKeyID)
        let status = RegisterEventHotKey(
            UInt32(kVK_Escape),
            0,                              // no modifiers
            id,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status != noErr {
            Log.system.error("RegisterEventHotKey Esc failed: \(status, privacy: .public)")
            return
        }
        escHotKeyRef = ref
    }

    func unregisterEsc() {
        if let ref = escHotKeyRef {
            UnregisterEventHotKey(ref)
            escHotKeyRef = nil
        }
        Self.routes[Self.escHotKeyID] = nil
    }

    func unregisterAll() {
        if let ref = globalHotKeyRef {
            UnregisterEventHotKey(ref)
            globalHotKeyRef = nil
        }
        unregisterEsc()
        Self.routes.removeAll()
    }

    private func installEventHandlerOnce() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, eventRef, _ in
            var hkID = EventHotKeyID()
            let err = GetEventParameter(
                eventRef,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hkID
            )
            if err == noErr {
                let id = hkID.id
                DispatchQueue.main.async {
                    HotkeyRegistrar.routes[id]?()
                }
            }
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &spec, nil, &eventHandler)
    }
}
```

- [ ] **Step 2: Update AppDelegate to pass both handlers.**

In `App/AppDelegate.swift`, change the HotkeyRegistrar instantiation to use the two-callback init:

```swift
hotkeys = HotkeyRegistrar(
    onGlobal: { [weak coordinator] in coordinator?.handleHotkey() },
    onEsc:    { [weak coordinator] in coordinator?.handleEscDuringRecording() }
)
hotkeys.registerGlobal()
```

- [ ] **Step 3: Add handleEscDuringRecording + dynamic Esc registration in MenubarCoordinator.**

Modify `App/MenubarCoordinator.swift`. Add:

```swift
func handleEscDuringRecording() {
    Task { @MainActor in
        await session.cancel()
    }
}

// Inside installSubscriptions, augment the state observer to register/
// unregister the Esc hotkey on .recording entry/exit:

private func installSubscriptions() {
    session.$state
        .receive(on: RunLoop.main)
        .sink { [weak self] newState in
            self?.handleStateChange(newState)
            self?.updateEscHotkey(for: newState)
        }
        .store(in: &cancellables)
}

private weak var hotkeyRegistrar: HotkeyRegistrar?

private func updateEscHotkey(for state: RecordingSession.State) {
    guard let hotkeyRegistrar else { return }
    if state == .recording {
        hotkeyRegistrar.registerEsc()
    } else {
        hotkeyRegistrar.unregisterEsc()
    }
}

func attach(hotkeyRegistrar: HotkeyRegistrar) {
    self.hotkeyRegistrar = hotkeyRegistrar
}
```

Then in AppDelegate after creating both `coordinator` and `hotkeys`:

```swift
coordinator.attach(hotkeyRegistrar: hotkeys)
```

- [ ] **Step 4: Build.**

Run: `xcodebuild -project Snatch.xcodeproj -scheme App build 2>&1 | tail -10`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Manual smoke (basic).**

Launch the app. Press ⇧⌘6 from any other app. Cropper should appear on the screen with the cursor. Press ⇧⌘6 again — cropper disappears. (Permission flow may interrupt if not already granted; that's OK.) Quit.

- [ ] **Step 6: Commit.**

```bash
git add App/UI/System/HotkeyRegistrar.swift App/AppDelegate.swift App/MenubarCoordinator.swift
git commit -m "feat(hotkey): Carbon ⇧⌘6 global + dynamic Esc during recording"
```

---

## Phase 11 — System adapters: real implementations

### Task 21: PasteboardWriter + NotificationPresenter

**Files:**
- Modify: `App/UI/System/PasteboardWriter.swift`
- Modify: `App/UI/System/NotificationPresenter.swift`
- Modify: `App/AppDelegate.swift` (delegate setup, authorization request)

- [ ] **Step 1: Implement PasteboardWriter.**

Replace `App/UI/System/PasteboardWriter.swift`:

```swift
import AppKit

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
```

- [ ] **Step 2: Implement NotificationPresenter.**

Replace `App/UI/System/NotificationPresenter.swift`:

```swift
import Foundation
import AppKit
import UserNotifications
import SnatchKit

@MainActor
final class NotificationPresenter: NSObject {
    static let revealActionId = "co.snatch.notification.reveal"
    static let savedCategoryId = "co.snatch.notification.saved"
    static let failureCategoryId = "co.snatch.notification.failure"

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self

        let revealAction = UNNotificationAction(
            identifier: Self.revealActionId,
            title: "Reveal in Finder",
            options: []
        )
        let savedCategory = UNNotificationCategory(
            identifier: Self.savedCategoryId,
            actions: [revealAction],
            intentIdentifiers: [],
            options: []
        )
        let failureCategory = UNNotificationCategory(
            identifier: Self.failureCategoryId,
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([savedCategory, failureCategory])
    }

    func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            Log.system.error("notification authorization failed: \(String(describing: error), privacy: .public)")
        }
    }

    func present(savedURL: URL) {
        let content = UNMutableNotificationContent()
        content.title = "GIF saved"
        content.body = savedURL.lastPathComponent
        content.sound = .default
        content.categoryIdentifier = Self.savedCategoryId
        content.userInfo = ["path": savedURL.path]

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                Log.system.error("notification add failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    func presentFailure(_ message: String) {
        let content = UNMutableNotificationContent()
        content.title = "Snatch — recording failed"
        content.body = message
        content.sound = .default
        content.categoryIdentifier = Self.failureCategoryId

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}

extension NotificationPresenter: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let path = response.notification.request.content.userInfo["path"] as? String
        let isReveal = response.actionIdentifier == Self.revealActionId
            || response.actionIdentifier == UNNotificationDefaultActionIdentifier
        if isReveal, let path {
            DispatchQueue.main.async {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            }
        }
        completionHandler()
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
```

- [ ] **Step 3: Wire authorization request in AppDelegate.**

In `App/AppDelegate.swift`'s `applicationDidFinishLaunching`, add after the `Task.detached` for shareableContent.refresh:

```swift
Task { await self.notifier.requestAuthorizationIfNeeded() }
```

- [ ] **Step 4: Build.**

Run: `xcodebuild -project Snatch.xcodeproj -scheme App build 2>&1 | tail -10`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Manual smoke.**

Launch the app. macOS should show a notification permission prompt the first time. Grant it. Trigger a recording (⇧⌘6 → drag → Record → Stop). Notification should appear. Click "Reveal in Finder" → Finder shows the saved GIF. ⌘V into TextEdit (or Slack) → the GIF file pastes.

- [ ] **Step 6: Commit.**

```bash
git add App/UI/System/PasteboardWriter.swift App/UI/System/NotificationPresenter.swift App/AppDelegate.swift
git commit -m "feat(system): real PasteboardWriter + NotificationPresenter

Notification has Reveal in Finder action; clicking the body or the
button selects the file in Finder. Authorization requested on first
launch; failures are non-fatal."
```

---

## Phase 12 — Smoke + ship

### Task 22: M5 manual smoke checklist

This is the M5 done gate (spec §13). Run by a human at the keyboard.

**Files:** none (verification only)

For each item, mark complete only after observing the expected behavior:

- [ ] **Item 1: Build & basic tests.**
  Run: `xcodebuild -project Snatch.xcodeproj -scheme App build 2>&1 | tail -3 && swift test 2>&1 | tail -3 && xcodebuild -project Snatch.xcodeproj -scheme App test 2>&1 | tail -3`
  Expected: BUILD SUCCEEDED + Test Suite passed (×2). No warnings in build output.

- [ ] **Item 2: Cold launch.**
  Open `Snatch.app`. Menubar icon appears within ~1s. No Dock entry. No app-switcher entry. Run `ls ~/Desktop/snatch-*.gif.partial 2>/dev/null` — no matches.

- [ ] **Item 3: First-record system prompt.**
  Run `tccutil reset ScreenCapture co.snatch.app` then relaunch the app. Press ⇧⌘6. System prompt fires. Click Allow. Relaunch alert appears. Click Quit & Relaunch. App comes back. ⇧⌘6 records successfully.

- [ ] **Item 4: Hotkey latency.**
  With the app running and idle, press ⇧⌘6. Cropper paints visibly within ~100 ms (subjective: feels instant). Use Console.app filtered by `subsystem == co.snatch.app` to spot-check log timestamps for hotkey → state-change. Optionally use Instruments → Logging → os_signpost (signposts can be added in a follow-up if formal measurement is desired).

- [ ] **Item 5: Stop latency.**
  Record for 5 seconds, press Stop. Notification appears within ~500 ms. Visual check: feels immediate.

- [ ] **Item 6: Cropper.**
  Drag a region; resize via 8 handles; observe W×H label; click Record / Space / Enter / Esc — all behave correctly. Trigger ⇧⌘6 again — pre-drawn last-region appears.

- [ ] **Item 7: Hotkey from foreign contexts.**
  ⇧⌘6 while focused in: Safari, Slack, fullscreen video (any video player), an open dialog. Cropper appears in all cases.

- [ ] **Item 8: Stop paths.**
  Hotkey-stop, menubar-icon-click-stop, Stop-button-click, Carbon-Esc-cancel. Each produces correct end state — first three save (notification + clipboard + recents update); Esc cancels (no notification, no clipboard, no recents update, `.partial` cleaned).

- [ ] **Item 9: Notification.**
  Saves trigger a notification within budget. Click body → Finder reveals the file. Click "Reveal in Finder" action → same.

- [ ] **Item 10: Clipboard.**
  ⌘V into Slack, Discord, Finder, Notes, Mail, Messages. Animation preserved (file-URL paste; some apps show as attachment).

- [ ] **Item 11: Scale presets.**
  Set Scale ▸ Retina; record; verify GIF is at physical-pixel resolution. Set Standard; record; verify 1× logical. Set Compact; record; verify 0.5×.

- [ ] **Item 12: Recents menu.**
  Make 6 recordings. Open dropdown → Recent Recordings ▸ shows 5 items, oldest evicted. Delete one of the 5 from Desktop. Open dropdown again — that one no longer appears.

- [ ] **Item 13: Permission revoked mid-session.**
  System Settings → Privacy & Security → Screen Recording → toggle Snatch off → return to app → menubar icon turns red `exclamationmark.triangle.fill`. Press ⇧⌘6 → denied alert. Toggle back on → return to app → icon back to camera; ⇧⌘6 records successfully without relaunch.

- [ ] **Item 14: Crash hygiene.**
  Start a recording. `pkill -9 Snatch`. Relaunch. Run `ls ~/Desktop/snatch-*.gif.partial 2>/dev/null` — no matches.

- [ ] **Item 15: Pre-warm under load.**
  Open Xcode + a busy browser tab + a video player. Press ⇧⌘6 — cropper still feels instant.

- [ ] **Item 16: Backpressure (post-refactor smoke).**
  Run the snatch-record-cli sustained-Retina test from Task 3 again: `swift run -c release snatch-record-cli --duration 30 --output /tmp/m5-item16.gif --region 0,0,2560,1440 --scale retina`. Output GIF is playable; final drop count is bounded; encoder didn't deadlock.

- [ ] **Item 17: About + Quit.**
  About panel shows correct version + bundle id (`co.snatch.app`). Quit cleanly terminates (menubar icon disappears).

- [ ] **Item 18: Tag.**
  After all of the above pass, tag the commit:
  ```bash
  git tag m5-menubar-app
  ```

- [ ] **Item 19: CLAUDE.md.**
  Update `CLAUDE.md` Status section. See Task 23.

---

### Task 23: Update CLAUDE.md, commit, tag

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Read current CLAUDE.md status section.**

Read the `## Status` section so you preserve the M1–M4 entries.

- [ ] **Step 2: Update the Status section.**

Replace the M5/next entry with:

```markdown
- **M5 — Menubar App + Hotkey + Pre-warm ✅ Complete** (tag `m5-menubar-app`). `Snatch.app` runs from the menubar with `LSUIElement = YES`; ⇧⌘6 hotkey via Carbon (pre-routed); pre-warmed cropper hits sub-100ms paint; partial-file sweep on launch; full Screen Recording permission flow (NSAlert + System Settings deep-link + relaunch dance); post-stop chain (notification + clipboard + recents); Carbon Esc cancel-during-recording; Recent Recordings ▸ submenu (cap 5, missing-file filter); scale dropdown persisted; SF Symbols icon set (camera.viewfinder / record.circle.fill / exclamationmark.triangle.fill); backpressure refactor of `ScreenRecordingPipeline` (real producer/consumer + independent encoder drain; clears CMSampleBuffer Sendable warning). New `SnatchAppKit` SPM library shares CropperWindow/CropperView/RecordingOverlayWindow between `snatch-session-cli` and the Xcode App target. `Snatch.xcodeproj` is the App-target home; the three CLIs stay in `Package.swift` as headless dev tools.
- **M6 — Smoke + ship** is next: Developer ID signing, notarization, gatekeeper pass on a fresh Mac, GitHub release.
```

- [ ] **Step 3: Commit.**

```bash
git add CLAUDE.md
git commit -m "docs: M5 menubar app complete"
```

- [ ] **Step 4: Push the tag (optional; depends on whether the repo has a remote).**

If the repo has an `origin`:
```bash
git push origin main && git push origin m5-menubar-app
```

If not, skip.

---

## Self-review

After completing all tasks, the executing agent (or a follow-up review pass) should verify:

- **Spec coverage:** Walk through `docs/superpowers/specs/2026-05-01-m5-menubar-app-design.md` §3–§12. Every component named in §3 should map to a task above. Every flow in §10 should be exercised by the smoke checklist in Task 22.

- **Type consistency:** `MenubarIconState.icon(permission:session:) -> MenubarIcon` is referenced in Tasks 16 and 19 — same signature both places. `RecordingPipeline` protocol is unchanged (Lane A doesn't touch it). `RecordingSession.State` adds `.cropping` (Task 7); subsequent tasks (15, 16, 19, 20) use the new state.

- **Smoke gates:**
  - Task 3 (backpressure) is a manual gate after Lane A.
  - Task 22 (M5 done) is the milestone gate.
  - Both require human verification; subagents can prepare commands but not pass these themselves.

- **Carry-overs to M6** (per spec §14): Developer ID signing, notarization, GitHub release, hardened-runtime entitlements review, gatekeeper test on a fresh Mac, README/install instructions. Not addressed in M5; tracked in spec.

---

## Suggested model assignments

The user's prior session noted: "Use Haiku for mechanical TDD tasks, Sonnet/Opus for state-machine and integration tasks." Mapping that onto the tasks here:

**Haiku-suitable (mechanical TDD):**
Task 1 (BridgeQueue blocking primitives), Task 4 (ScalePresetStore), Task 5 (RecentRecordingsStore), Task 6 (PathProvider), Task 9 (PartialFileSweeper), Task 11 (Log additions), Task 13 (Args cleanup), Task 16 (MenubarIconState mapping function).

**Sonnet/Opus (state-machine + integration):**
Task 2 (ScreenRecordingPipeline rewrite), Task 7 (RecordingSession .cropping state), Task 8 (PermissionsCoordinator), Task 10 (ShareableContentCache), Task 12 (SPM library split), Task 14 (Xcode project setup), Task 15 (AppDelegate + MenubarCoordinator skeleton), Task 17 (Cropper/overlay show/hide wiring), Task 18 (Permission alerts), Task 19 (MenubarController), Task 20 (HotkeyRegistrar), Task 21 (PasteboardWriter + NotificationPresenter).

**Human-in-the-loop:**
Task 3 (backpressure smoke), Task 14 step 7 (Xcode project creation in IDE), Task 16 step 1 (test target creation in IDE), Task 22 (M5 smoke checklist), Task 23 step 4 (push, optional).

---

## Reminder: workflow constraints

- **Do not run `git checkout`, `git switch`, `git reset --hard`, `git stash`, or any destructive git command.**
- **Do not run `--no-verify` or skip pre-commit hooks unless explicitly authorized.**
- **Do not push to `origin` without explicit authorization.**
- **Manual smoke gates require a human at the keyboard.** Subagents can prepare and document commands but should not claim a smoke gate has passed without human confirmation.
- **Work directly on `main`. No worktree.**
