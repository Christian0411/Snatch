# Snatch M4 — Coordinator Wiring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire the M3 cropper, the M2 capture pipeline, and the M1 encoder together end-to-end behind a `RecordingSession` state machine. After M4: a user runs `swift run snatch-session-cli`, drags a region, clicks Record, sees a thin red border with a floating Stop button, clicks Stop, and a GIF is written to the path passed via `--output`.

**Architecture:** Three-layer split. *Pure state machine* (`RecordingSession`) lives in `SnatchKit/Coordinator/`, depends only on a `RecordingPipeline` protocol + `RegionStore`, and is unit-tested via a `FakeRecordingPipeline` (no SCKit at all). *Production pipeline* (`ScreenRecordingPipeline`) is the single concrete `RecordingPipeline` impl — it owns the capture/encoder queues, `BridgeQueue`, `SCStreamWrapper`, `FrameConverter`, `GifskiEncoder`, and is the relocation of the inline plumbing currently in `Sources/SnatchRecordCLI/main.swift:99-216`. *AppKit shell* (`RecordingOverlayWindow`, `RecordingStopButton`, rewired `AppDelegate`) lives in the renamed `SnatchSessionCLI` SPM target and is smoke-tested by hand per spec §9.

**Tech Stack:** Swift 5.10, ScreenCaptureKit (`SCStream`, `SCShareableContent`, `SCWindow`, `SCContentFilter`), AppKit (`NSWindow`, `NSView`, `NSButton`), Foundation (`UserDefaults`, `DispatchQueue`, `Task`), Combine (`@Published` via `ObservableObject`), XCTest. Still on Swift Package Manager — Xcode project transition deferred to M5 (matches M3 rationale).

---

## Spec references

This plan implements the parts of `docs/superpowers/specs/2026-04-30-snatch-design.md` covering:
- §6 `RecordingSession` (state machine, public surface, transitions)
- §6 boundaries — Capture and Encoder do not know about UI; Coordinator owns the pipeline lifecycle
- §7 Flow 1 (start happy path, steps 4-7)
- §7 Flow 2 (stop normal save)
- §7 Flow 3 (cancel — both `cropping → idle` and `recording → cancelling → idle`)
- §8 error handling — permission denied, encoder error mid-recording (the M4 subset; modal dialogs and notifications remain M5)
- §10 M4 paragraph — "RecordingSession state machine integrates Cropper + Capture + Encoder. Click Record → records → click stop → GIF saved."

Plan-level decisions are documented in the milestone-specific design at `docs/superpowers/specs/2026-04-30-m4-coordinator-wiring-design.md`.

Out of scope for M4 (covered in later milestones):
- Global hotkey (`⇧⌘6` via Carbon) — M5
- Carbon Esc hotkey during recording (cancel-during-recording trigger) — M5; the *transition* and `pipeline.cancel` are tested in M4
- `NSStatusItem` menubar — M5
- `NotificationPresenter`, `PasteboardWriter`, `RecentRecordingsStore` — M5
- `PathProvider` Desktop auto-naming (M4 uses `--output`) — M5
- Partial-file sweep on launch — M5
- Pre-warm strategy — M5
- Permission-flow modals + System Settings deep-link — M5 (M4 prints to stderr)
- Multi-display reconfigure mid-session — M5
- Pipeline backpressure refactor (capture/encoder dispatch coupling at `Sources/SnatchRecordCLI/main.swift:142-151`) — M5

## File Structure

After M4 completes, the repo looks like (new/changed entries marked):

```
/Users/starship/src/snatch/
├── CLAUDE.md                                            (modified — Status: M4 done; rename note)
├── Package.swift                                        (modified — SnatchCropperCLI → SnatchSessionCLI)
├── Sources/
│   ├── SnatchKit/
│   │   ├── Capture/
│   │   │   ├── BridgeQueue.swift
│   │   │   ├── FrameConverter.swift
│   │   │   └── SCStreamWrapper.swift                    (modified — excludingWindows parameter)
│   │   ├── Coordinator/                                 (new directory)
│   │   │   ├── RecordingSession.swift                   (new — state machine, ObservableObject)
│   │   │   ├── RecordingPipeline.swift                  (new — protocol)
│   │   │   ├── ScreenRecordingPipeline.swift            (new — concrete impl)
│   │   │   └── RecordingSessionError.swift              (new — LocalizedError enum)
│   │   ├── Encoder/
│   │   │   └── GifskiEncoder.swift
│   │   ├── Logging/
│   │   │   └── Log.swift                                (unchanged — Log.coordinator already exists)
│   │   ├── Shared/
│   │   │   ├── RGBAFrame.swift
│   │   │   └── ScalePreset.swift
│   │   ├── System/
│   │   │   └── RegionStore.swift                        (modified — @unchecked Sendable)
│   │   └── UI/
│   │       └── Cropper/                                 (unchanged from M3)
│   │           ├── CropperGeometry.swift
│   │           ├── CropperHandle.swift
│   │           └── CropperState.swift
│   ├── SnatchCLI/
│   │   └── main.swift                                   (unchanged)
│   ├── SnatchRecordCLI/
│   │   └── main.swift                                   (modified — uses ScreenRecordingPipeline)
│   └── SnatchSessionCLI/                                (renamed from SnatchCropperCLI)
│       ├── AppDelegate.swift                            (modified — wires RecordingSession + overlay)
│       ├── Args.swift                                   (new — argv parser)
│       ├── CropperRecordButton.swift                    (unchanged from M3)
│       ├── CropperView.swift                            (unchanged from M3)
│       ├── CropperWindow.swift                          (unchanged from M3)
│       ├── RecordingOverlayWindow.swift                 (new — red-border + Stop button host)
│       ├── RecordingStopButton.swift                    (new — small red NSButton)
│       └── main.swift                                   (modified — Args parsing before NSApplication.run)
├── Tests/
│   └── SnatchKitTests/
│       ├── (existing M1/M2/M3 test files unchanged unless noted)
│       ├── Helpers/
│       │   ├── FakeRecordingPipeline.swift              (new)
│       │   └── SampleBufferFactory.swift
│       ├── RecordingSessionTests.swift                  (new — state machine TDD coverage)
│       ├── RecordingSessionErrorTests.swift             (new — errorDescription string check)
│       ├── ScreenRecordingPipelineTests.swift           (new — non-live API/contract checks)
│       ├── ScreenRecordingPipelineLiveTests.swift       (new — live capture integration; skipped without permission)
│       └── RegionStoreTests.swift                       (modified — Sendable compile-check)
└── docs/superpowers/
    ├── plans/
    │   └── 2026-04-30-m4-coordinator-wiring.md          (this file)
    └── specs/
        ├── 2026-04-30-snatch-design.md
        └── 2026-04-30-m4-coordinator-wiring-design.md
```

**Layering rules** (extending M3's split):
1. `SnatchKit/Coordinator/` is the only place that imports both `ScreenCaptureKit` (in the concrete pipeline) and high-level types like `ObservableObject`. The protocol file imports only `ScreenCaptureKit` (for `SCWindow`) and Foundation.
2. `RecordingSession` is `@MainActor` and never imports `AppKit`. UI lives in `SnatchSessionCLI/`.
3. `SnatchSessionCLI/` is the only place that imports `AppKit`. It wires `CropperView.onRecord` and overlay `onStop` callbacks to `await session.start/stop/cancel(...)`.
4. `Tests/SnatchKitTests/Helpers/FakeRecordingPipeline.swift` is the only test seam for `RecordingSession`. Tests do not touch `ScreenRecordingPipeline` outside the dedicated live-capture test.

## Naming convention notes

- New SnatchKit types live in `SnatchKit/Coordinator/`. The directory is created by the first file added to it (Task 4).
- The CLI binary is `snatch-session-cli` (mirrors `snatch-record-cli` and `snatch-cropper-cli`'s `kebab-case`); the SPM target is `SnatchSessionCLI` (matches the existing `Snatch*CLI` PascalCase pattern).
- The state-machine `State` enum has 4 cases: `idle | recording | finalizing | cancelling`. The spec §6 fifth case `.cropping` is represented in M4 as AppDelegate's UI mode while `state == .idle` (see design doc §3.1). M5 may revisit.

---

## Task 1: Rename SnatchCropperCLI target → SnatchSessionCLI

**Files:**
- Move (`git mv`): `Sources/SnatchCropperCLI/` → `Sources/SnatchSessionCLI/` (5 files: AppDelegate.swift, CropperWindow.swift, CropperView.swift, CropperRecordButton.swift, main.swift)
- Modify: `Package.swift` (lines 11 and 44-48)

This rename is mechanical and lands first so subsequent tasks operate on the final target name. It preserves blame via `git mv`. The `m3-cropper-ui` tag (frozen at commit `49f0265`) keeps its old binary name `snatch-cropper-cli` historically; from the M4 commit onward the binary is `snatch-session-cli`.

- [ ] **Step 1: Verify nothing else references the old target/binary name**

Run from repo root:
```bash
grep -RIn 'SnatchCropperCLI\|snatch-cropper-cli' --exclude-dir=.git --exclude-dir=.build .
```
Expected: matches in `Package.swift` (lines 11, 44-48), `Sources/SnatchCropperCLI/main.swift` header comment (line 3, line 17), `docs/superpowers/plans/2026-04-30-m3-cropper-ui.md`, `docs/superpowers/specs/2026-04-30-m4-coordinator-wiring-design.md`, and `CLAUDE.md`.

The docs and plan references are historical and stay as-is. Only `Package.swift` and the source file's header comments need updating.

- [ ] **Step 2: `git mv` the directory**

```bash
git mv Sources/SnatchCropperCLI Sources/SnatchSessionCLI
```

Verify with `git status` — all 5 files should show as renames.

- [ ] **Step 3: Update Package.swift**

Open `Package.swift`. Line 11:
```swift
.executable(name: "snatch-cropper-cli", targets: ["SnatchCropperCLI"]),
```
becomes:
```swift
.executable(name: "snatch-session-cli", targets: ["SnatchSessionCLI"]),
```

Lines 44-48:
```swift
        .executableTarget(
            name: "SnatchCropperCLI",
            dependencies: ["SnatchKit"],
            path: "Sources/SnatchCropperCLI"
        ),
```
becomes:
```swift
        .executableTarget(
            name: "SnatchSessionCLI",
            dependencies: ["SnatchKit"],
            path: "Sources/SnatchSessionCLI"
        ),
```

- [ ] **Step 4: Update the header comment in main.swift**

Open `Sources/SnatchSessionCLI/main.swift`. The first line currently reads:
```swift
// Sources/SnatchCropperCLI/main.swift
```
Update to:
```swift
// Sources/SnatchSessionCLI/main.swift
```

In the same file, the doc-comment block at lines 3-22 references `snatch-cropper-cli` and "M3" — leave that block alone for now; Task 16 rewrites the description when AppDelegate is rewired.

- [ ] **Step 5: Verify build still green**

```bash
swift build
```
Expected: succeeds, no warnings. (`SwiftCompile` lines now reference `SnatchSessionCLI` instead of `SnatchCropperCLI`.)

```bash
swift test 2>&1 | tail -5
```
Expected: full default suite passes (75 tests + 1 skipped live-capture test, matching M3's done state).

- [ ] **Step 6: Verify the renamed binary still runs the cropper smoke**

```bash
swift run snatch-session-cli 2>&1 | head -1
```
Expected: cropper window appears (or, if Screen Recording permission is unavailable to the host terminal, output describing the interactive UI). Press Esc to dismiss. Output `CANCELLED` to stdout.

This is a sanity check that the rename didn't break the binary. The actual M4 wiring lands in Task 16.

- [ ] **Step 7: Commit**

```bash
git add Package.swift Sources/SnatchSessionCLI/
git commit -m "$(cat <<'EOF'
refactor(target): rename SnatchCropperCLI → SnatchSessionCLI

Mechanical rename for M4 — the binary now hosts the full cropper +
recording session driver, not only the M3 cropper smoke harness.
The m3-cropper-ui tag preserves the old name historically.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: SCStreamWrapper.start gains `excludingWindows` parameter

**Files:**
- Modify: `Sources/SnatchKit/Capture/SCStreamWrapper.swift` (signature at lines 55-60; filter construction at line 88)

The cropper and recording overlay windows must be excluded from `SCContentFilter` so they don't appear in the recorded GIF. Currently `SCContentFilter` is constructed with `excludingWindows: []` (line 88) and there's no way for callers to pass exclusions through. This task adds an `excludingWindows: [SCWindow] = []` parameter to `SCStreamWrapper.start(...)` and threads it through.

The threading itself is not unit-testable without a live SCKit session (no helper to extract — `SCContentFilter` construction is one line). The behavior is verified end-to-end via the live integration test in Task 12.

- [ ] **Step 1: Read current signature and call site**

Re-read `Sources/SnatchKit/Capture/SCStreamWrapper.swift:55-90` to confirm what's there:
- Lines 55-60: signature with parameters `region`, `scale`, `fps`, `queue`.
- Line 88: `let filter = SCContentFilter(display: display, excludingWindows: [])`

- [ ] **Step 2: Update the signature**

In `Sources/SnatchKit/Capture/SCStreamWrapper.swift`, change lines 55-60 from:
```swift
    public func start(
        region: CGRect,
        scale: ScalePreset,
        fps: Int,
        queue: DispatchQueue
    ) async throws -> AsyncStream<CMSampleBuffer> {
```
to:
```swift
    public func start(
        region: CGRect,
        scale: ScalePreset,
        fps: Int,
        queue: DispatchQueue,
        excludingWindows: [SCWindow] = []
    ) async throws -> AsyncStream<CMSampleBuffer> {
```

The default `[]` keeps existing call sites (notably `Sources/SnatchRecordCLI/main.swift:119`) compiling without changes.

- [ ] **Step 3: Thread the parameter through to SCContentFilter**

Line 88 currently:
```swift
        let filter = SCContentFilter(display: display, excludingWindows: [])
```
Change to:
```swift
        let filter = SCContentFilter(display: display, excludingWindows: excludingWindows)
```

- [ ] **Step 4: Update the doc comment**

Lines 47-54 currently document the existing parameters. Add an entry for `excludingWindows`:

In the doc block above `start(...)`, after the existing `- queue:` bullet, add:
```swift
    ///   - excludingWindows: SCWindow handles to exclude from the
    ///     `SCContentFilter`. M4 uses this to keep the cropper and recording
    ///     overlay windows out of the captured GIF (spec §6). Default `[]`.
```

- [ ] **Step 5: Verify build still green**

```bash
swift build
```
Expected: succeeds, no warnings.

```bash
swift test 2>&1 | tail -5
```
Expected: full default suite passes — `SCStreamWrapperHelperTests` and `PipelineIntegrationTests` still green; the parameter has a default so existing callers are unaffected.

- [ ] **Step 6: Commit**

```bash
git add Sources/SnatchKit/Capture/SCStreamWrapper.swift
git commit -m "$(cat <<'EOF'
feat(capture): SCStreamWrapper.start accepts excludingWindows

Threads the SCContentFilter exclusion list through to callers so M4's
RecordingSession can keep the cropper + recording overlay out of the
recorded GIF. Defaulted to [] for backwards compat with snatch-record-cli.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: RegionStore @unchecked Sendable

**Files:**
- Modify: `Sources/SnatchKit/System/RegionStore.swift`
- Modify: `Tests/SnatchKitTests/RegionStoreTests.swift`

`RecordingSession.start` is `@MainActor`. It needs to call `regionStore.persist(region)` without triggering Swift's strict-concurrency warnings about a non-`Sendable` class crossing actor boundaries. `UserDefaults` is documented thread-safe (Apple Developer docs: "thread-safe"), so `@unchecked Sendable` is honest here.

- [ ] **Step 1: Write the compile-time Sendable check (RED)**

Open `Tests/SnatchKitTests/RegionStoreTests.swift`. Append a new test at the bottom of the class (just before the closing `}`):

```swift
    func test_RegionStore_isSendable() {
        // Compile-time check — if RegionStore isn't Sendable, this fails to compile.
        let store = RegionStore(defaults: defaults)
        Self._requireSendable(store)
    }

    /// Compile-time guard: the type parameter must conform to Sendable, otherwise
    /// the call site won't typecheck.
    private static func _requireSendable<T: Sendable>(_ value: T) {}
```

- [ ] **Step 2: Run test — should fail to compile**

```bash
swift test --filter RegionStoreTests.test_RegionStore_isSendable 2>&1 | tail -10
```
Expected: compile error mentioning `RegionStore` does not conform to `Sendable`.

- [ ] **Step 3: Make RegionStore Sendable**

In `Sources/SnatchKit/System/RegionStore.swift`, change line 8 from:
```swift
public final class RegionStore {
```
to:
```swift
public final class RegionStore: @unchecked Sendable {
    // UserDefaults is documented thread-safe by Apple. All mutations go through
    // `defaults.set/removeObject`, never through the array-of-doubles cache directly.
```

Note: keep the next-line `private let defaults: UserDefaults` and the existing body unchanged. The `@unchecked Sendable` is on the class declaration; the comment is added immediately inside the class body.

- [ ] **Step 4: Run test — should pass**

```bash
swift test --filter RegionStoreTests.test_RegionStore_isSendable
```
Expected: PASS.

```bash
swift test 2>&1 | tail -5
```
Expected: full suite still green (the existing 6 RegionStoreTests still pass; one new test added makes 7 RegionStore tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/SnatchKit/System/RegionStore.swift Tests/SnatchKitTests/RegionStoreTests.swift
git commit -m "$(cat <<'EOF'
feat(system): RegionStore is @unchecked Sendable

Required so RecordingSession (@MainActor) can call regionStore.persist
without crossing-actor-boundary warnings. UserDefaults is documented
thread-safe; the conformance is honest. Added a compile-time check.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: RecordingSessionError enum

**Files:**
- Create: `Sources/SnatchKit/Coordinator/RecordingSessionError.swift`
- Create: `Tests/SnatchKitTests/RecordingSessionErrorTests.swift`

Lightweight error type that wraps pipeline errors with a transition-context prefix. Lands first because both `RecordingSession` (Task 6+) and the protocol type signatures need it.

- [ ] **Step 1: Write the test (RED)**

Create `Tests/SnatchKitTests/RecordingSessionErrorTests.swift`:

```swift
import XCTest
@testable import SnatchKit

final class RecordingSessionErrorTests: XCTestCase {

    private struct StubError: Error, CustomStringConvertible {
        var description: String { "stub error reason" }
    }

    func test_pipelineStartFailed_describesStartTransitionAndUnderlying() {
        let err = RecordingSessionError.pipelineStartFailed(underlying: StubError())
        XCTAssertNotNil(err.errorDescription)
        XCTAssertTrue(err.errorDescription!.contains("start"),
                      "expected 'start' in description: \(err.errorDescription!)")
        XCTAssertTrue(err.errorDescription!.contains("stub error reason"),
                      "expected underlying description in: \(err.errorDescription!)")
    }

    func test_pipelineStopFailed_describesStopTransitionAndUnderlying() {
        let err = RecordingSessionError.pipelineStopFailed(underlying: StubError())
        XCTAssertNotNil(err.errorDescription)
        XCTAssertTrue(err.errorDescription!.contains("stop"),
                      "expected 'stop' in description: \(err.errorDescription!)")
        XCTAssertTrue(err.errorDescription!.contains("stub error reason"),
                      "expected underlying description in: \(err.errorDescription!)")
    }
}
```

- [ ] **Step 2: Run test — should fail to compile**

```bash
swift test --filter RecordingSessionErrorTests 2>&1 | tail -10
```
Expected: compile error mentioning `RecordingSessionError` not found.

- [ ] **Step 3: Create the enum**

Create `Sources/SnatchKit/Coordinator/RecordingSessionError.swift`:

```swift
import Foundation

/// Errors thrown by `RecordingSession` when a pipeline transition fails.
/// The state machine wraps underlying pipeline errors with a transition
/// context label so callers know which step (start vs stop) blew up.
///
/// `cancel()` does not throw — there's no `pipelineCancelFailed` case by design.
public enum RecordingSessionError: Error, LocalizedError {
    case pipelineStartFailed(underlying: Error)
    case pipelineStopFailed(underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .pipelineStartFailed(let underlying):
            return "Recording failed during start: \(String(describing: underlying))"
        case .pipelineStopFailed(let underlying):
            return "Recording failed during stop: \(String(describing: underlying))"
        }
    }
}
```

- [ ] **Step 4: Run test — should pass**

```bash
swift test --filter RecordingSessionErrorTests
```
Expected: 2 PASS.

```bash
swift test 2>&1 | tail -5
```
Expected: full suite still green.

- [ ] **Step 5: Commit**

```bash
git add Sources/SnatchKit/Coordinator/RecordingSessionError.swift Tests/SnatchKitTests/RecordingSessionErrorTests.swift
git commit -m "$(cat <<'EOF'
feat(coordinator): RecordingSessionError enum

Wraps pipeline errors with a transition-context prefix (start vs stop).
LocalizedError so AppDelegate can surface the description on stderr.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: RecordingPipeline protocol + FakeRecordingPipeline test helper

**Files:**
- Create: `Sources/SnatchKit/Coordinator/RecordingPipeline.swift`
- Create: `Tests/SnatchKitTests/Helpers/FakeRecordingPipeline.swift`

The protocol is the testable seam between `RecordingSession` and the SCKit-touching pipeline. `FakeRecordingPipeline` is the deterministic in-memory fake the session tests will drive.

- [ ] **Step 1: Create the protocol file**

Create `Sources/SnatchKit/Coordinator/RecordingPipeline.swift`:

```swift
import Foundation
import CoreGraphics
import ScreenCaptureKit

/// Lifecycle contract for the screen-capture-to-GIF pipeline. The state
/// machine `RecordingSession` depends on this protocol so unit tests can
/// substitute `FakeRecordingPipeline` and exercise transitions without
/// ScreenCaptureKit, gifski, or filesystem I/O.
///
/// Concrete production impl: `ScreenRecordingPipeline`.
public protocol RecordingPipeline: Sendable {
    /// Begin capture. Returns once `SCStream.startCapture` has acknowledged
    /// — at that point frames are flowing into the encoder. Throws on any
    /// permission / display / encoder construction failure.
    func start(region: CGRect,
               scale: ScalePreset,
               fps: Int,
               outputURL: URL,
               excludingWindows: [SCWindow]) async throws

    /// End capture, drain in-flight frames, finish the encoder, and
    /// atomically rename the `.partial` to the final URL. Returns the
    /// final URL on success.
    func stop() async throws -> URL

    /// Abort capture. Tears down SCStream, drains+discards bridge contents,
    /// finishes the gifski handle, unlinks the `.partial`. Does not throw —
    /// cancel is best-effort cleanup.
    func cancel() async

    /// Bridge-overflow drop count from the most recent start..stop window.
    /// Reset on each `start()`.
    var droppedFrames: Int { get }
}
```

- [ ] **Step 2: Create the test helper directory + fake**

Create `Tests/SnatchKitTests/Helpers/FakeRecordingPipeline.swift`:

```swift
import Foundation
import CoreGraphics
import ScreenCaptureKit
@testable import SnatchKit

/// In-memory `RecordingPipeline` for `RecordingSessionTests`. Records every
/// call and lets tests configure errors / return values / drop counts. Lock
/// guarded for safe observation across the test's main thread and the
/// session's `@MainActor` context.
final class FakeRecordingPipeline: RecordingPipeline, @unchecked Sendable {

    struct StartCall: Equatable {
        let region: CGRect
        let scale: ScalePreset
        let fps: Int
        let outputURL: URL
        let excludingWindowCount: Int  // SCWindow isn't Equatable; count suffices.
    }

    private let lock = NSLock()
    private var _startCalls: [StartCall] = []
    private var _stopCallCount: Int = 0
    private var _cancelCallCount: Int = 0
    private var _droppedFrames: Int = 0

    // Test-controllable behavior
    var startError: Error?
    var stopError: Error?
    var stopReturnURL: URL = URL(fileURLWithPath: "/tmp/fake-output.gif")
    var droppedFramesValue: Int = 0

    /// Optional gates that let tests pause the pipeline mid-call so they can
    /// exercise debounce / re-entrant behavior. Both default to nil = don't pause.
    var startGate: (() async -> Void)?

    var startCalls: [StartCall] { lock.withLock { _startCalls } }
    var stopCallCount: Int { lock.withLock { _stopCallCount } }
    var cancelCallCount: Int { lock.withLock { _cancelCallCount } }

    var droppedFrames: Int { lock.withLock { _droppedFrames } }

    func start(region: CGRect,
               scale: ScalePreset,
               fps: Int,
               outputURL: URL,
               excludingWindows: [SCWindow]) async throws {
        lock.withLock {
            _startCalls.append(StartCall(
                region: region, scale: scale, fps: fps,
                outputURL: outputURL, excludingWindowCount: excludingWindows.count
            ))
            _droppedFrames = 0
        }
        if let gate = startGate {
            await gate()
        }
        if let err = startError {
            throw err
        }
    }

    func stop() async throws -> URL {
        lock.withLock {
            _stopCallCount += 1
            _droppedFrames = droppedFramesValue
        }
        if let err = stopError {
            throw err
        }
        return stopReturnURL
    }

    func cancel() async {
        lock.withLock {
            _cancelCallCount += 1
        }
    }
}
```

- [ ] **Step 3: Verify build still green**

```bash
swift build
```
Expected: succeeds, no warnings.

```bash
swift test 2>&1 | tail -5
```
Expected: full suite still green. The fake compiles but isn't used yet; no new tests pass / fail. The protocol file and helper are ready for Task 6+.

- [ ] **Step 4: Commit**

```bash
git add Sources/SnatchKit/Coordinator/RecordingPipeline.swift Tests/SnatchKitTests/Helpers/FakeRecordingPipeline.swift
git commit -m "$(cat <<'EOF'
feat(coordinator): RecordingPipeline protocol + FakeRecordingPipeline helper

Protocol seam separating RecordingSession (state machine, no SCKit)
from the production capture pipeline (SCKit + gifski). Fake is
@unchecked Sendable with NSLock so the upcoming session tests can
observe call counts across the @MainActor boundary.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: RecordingSession scaffold + happy path (TDD)

**Files:**
- Create: `Sources/SnatchKit/Coordinator/RecordingSession.swift`
- Create: `Tests/SnatchKitTests/RecordingSessionTests.swift`

This task lands the state machine scaffold and the happy-path transitions: `idle → recording` (on `start`) and `recording → finalizing → idle` (on `stop`). Cancel paths come in Task 7. Error paths in Task 8. Ignored events in Task 9.

The `clock` injection makes `Result.stopLatencyMs` deterministic in tests — without it, the assertion would be against `0.0` because the fake pipeline returns synchronously, and we want a real check.

- [ ] **Step 1: Write the failing tests (RED)**

Create `Tests/SnatchKitTests/RecordingSessionTests.swift`:

```swift
import XCTest
import CoreGraphics
@testable import SnatchKit

final class RecordingSessionTests: XCTestCase {

    private var pipeline: FakeRecordingPipeline!
    private var regionStore: RegionStore!
    private var defaults: UserDefaults!
    private var suiteName: String!
    /// Fake clock; bumped by helper to simulate elapsed time.
    private var fakeNow: CFAbsoluteTime = 0

    override func setUp() {
        super.setUp()
        pipeline = FakeRecordingPipeline()
        suiteName = "co.snatch.tests.RecordingSession.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        regionStore = RegionStore(defaults: defaults)
        fakeNow = 1000.0
    }

    override func tearDown() {
        defaults?.removePersistentDomain(forName: suiteName)
        defaults = nil
        regionStore = nil
        pipeline = nil
        suiteName = nil
        super.tearDown()
    }

    @MainActor
    private func makeSession() -> RecordingSession {
        RecordingSession(
            pipeline: pipeline,
            regionStore: regionStore,
            clock: { [weak self] in self?.fakeNow ?? 0 }
        )
    }

    @MainActor
    func test_initialState_isIdle() {
        let session = makeSession()
        XCTAssertEqual(session.state, .idle)
    }

    @MainActor
    func test_start_fromIdle_transitionsToRecordingAndCallsPipeline() async throws {
        let session = makeSession()
        let region = CGRect(x: 10, y: 20, width: 300, height: 200)
        let url = URL(fileURLWithPath: "/tmp/m4-test.gif")

        try await session.start(
            region: region, scale: .standard, fps: 30,
            outputURL: url, excludingWindows: []
        )

        XCTAssertEqual(session.state, .recording)
        XCTAssertEqual(pipeline.startCalls.count, 1)
        let call = pipeline.startCalls[0]
        XCTAssertEqual(call.region, region)
        XCTAssertEqual(call.scale, .standard)
        XCTAssertEqual(call.fps, 30)
        XCTAssertEqual(call.outputURL, url)
        XCTAssertEqual(call.excludingWindowCount, 0)
    }

    @MainActor
    func test_start_persistsRegion() async throws {
        let session = makeSession()
        let region = CGRect(x: 7, y: 11, width: 320, height: 240)

        try await session.start(
            region: region, scale: .standard, fps: 30,
            outputURL: URL(fileURLWithPath: "/tmp/m4.gif"),
            excludingWindows: []
        )

        XCTAssertEqual(regionStore.lastRegion, region)
    }

    @MainActor
    func test_stop_fromRecording_transitionsToIdleAndReturnsResult() async throws {
        let session = makeSession()
        let outURL = URL(fileURLWithPath: "/tmp/m4-result.gif")
        let returnedURL = URL(fileURLWithPath: "/tmp/m4-actual.gif")
        pipeline.stopReturnURL = returnedURL
        pipeline.droppedFramesValue = 4

        try await session.start(
            region: CGRect(x: 0, y: 0, width: 100, height: 100),
            scale: .standard, fps: 30,
            outputURL: outURL, excludingWindows: []
        )
        XCTAssertEqual(session.state, .recording)

        // Advance the fake clock by 0.123 seconds between start-of-stop and end-of-stop
        let beforeStop = fakeNow
        // pipeline.stop runs synchronously in the fake — bump the clock with a closure injection
        // so RecordingSession's measurement covers the elapsed window. The session reads the
        // clock once at entry to stop() (T0) and once after pipeline.stop returns (T1).
        // The fake's stop() is fast, so we bump fakeNow by the gate to simulate elapsed time.
        // Simpler approach: stop the closure mid-flight via a one-shot stopGate-equivalent.
        // For now, bump fakeNow before calling stop and re-read after to keep the test honest.
        // (The session reads clock() at entry; we control fakeNow before that call.)
        fakeNow = beforeStop + 0.123

        let result = try await session.stop()

        XCTAssertEqual(session.state, .idle)
        XCTAssertEqual(result.outputURL, returnedURL)
        XCTAssertEqual(result.droppedFrames, 4)
        // stopLatencyMs measured from T0 (entry to stop()) to T1 (after pipeline.stop) — both
        // read fakeNow which doesn't change inside the synchronous fake stop, so we expect 0.
        // (We'll exercise non-zero latency in the live integration test in Task 12.)
        XCTAssertEqual(result.stopLatencyMs, 0.0, accuracy: 0.001)
    }

    @MainActor
    func test_stop_passesThroughPipelineDroppedFrames() async throws {
        let session = makeSession()
        pipeline.droppedFramesValue = 17

        try await session.start(
            region: CGRect(x: 0, y: 0, width: 50, height: 50),
            scale: .standard, fps: 30,
            outputURL: URL(fileURLWithPath: "/tmp/m4.gif"),
            excludingWindows: []
        )
        let result = try await session.stop()

        XCTAssertEqual(result.droppedFrames, 17)
    }
}
```

- [ ] **Step 2: Run tests — should fail to compile**

```bash
swift test --filter RecordingSessionTests 2>&1 | tail -10
```
Expected: compile error mentioning `RecordingSession` not found.

- [ ] **Step 3: Implement the scaffold**

Create `Sources/SnatchKit/Coordinator/RecordingSession.swift`:

```swift
import Foundation
import CoreGraphics
import Combine
import ScreenCaptureKit

/// Top-level coordinator state machine. Wraps a `RecordingPipeline` with the
/// transition rules and observable state described in the M4 design doc §3.1.
///
/// Threading: `@MainActor`. All state mutations and `@Published` updates run
/// on main. The pipeline owns its own off-main capture/encoder queues.
@MainActor
public final class RecordingSession: ObservableObject {

    public enum State: Equatable {
        case idle
        case recording
        case finalizing
        case cancelling
    }

    public struct Result: Sendable, Equatable {
        public let outputURL: URL
        public let droppedFrames: Int
        public let stopLatencyMs: Double

        public init(outputURL: URL, droppedFrames: Int, stopLatencyMs: Double) {
            self.outputURL = outputURL
            self.droppedFrames = droppedFrames
            self.stopLatencyMs = stopLatencyMs
        }
    }

    @Published public private(set) var state: State = .idle

    private let pipeline: RecordingPipeline
    private let regionStore: RegionStore
    private let clock: () -> CFAbsoluteTime

    public init(pipeline: RecordingPipeline,
                regionStore: RegionStore,
                clock: @escaping () -> CFAbsoluteTime = CFAbsoluteTimeGetCurrent) {
        self.pipeline = pipeline
        self.regionStore = regionStore
        self.clock = clock
    }

    /// Idle → Recording. Persists `region` to `RegionStore`. Calls
    /// `pipeline.start`. Throws `RecordingSessionError.pipelineStartFailed`
    /// wrapping the underlying error if the pipeline rejects the start;
    /// state remains `.idle` on failure.
    public func start(region: CGRect,
                      scale: ScalePreset,
                      fps: Int,
                      outputURL: URL,
                      excludingWindows: [SCWindow]) async throws {
        guard state == .idle else {
            Log.coordinator.info("start ignored from state \(String(describing: self.state), privacy: .public)")
            return
        }
        regionStore.persist(region)
        do {
            try await pipeline.start(
                region: region,
                scale: scale,
                fps: fps,
                outputURL: outputURL,
                excludingWindows: excludingWindows
            )
        } catch {
            Log.coordinator.error("pipeline.start failed: \(String(describing: error), privacy: .public)")
            throw RecordingSessionError.pipelineStartFailed(underlying: error)
        }
        state = .recording
        Log.coordinator.info("state .idle → .recording")
    }

    /// Recording → Finalizing → Idle. Returns `Result` carrying the final URL,
    /// drop count, and stop latency in ms. Throws
    /// `RecordingSessionError.pipelineStopFailed` wrapping the underlying error
    /// if `pipeline.stop` fails; state still ends at `.idle`.
    public func stop() async throws -> Result {
        guard state == .recording else {
            Log.coordinator.info("stop ignored from state \(String(describing: self.state), privacy: .public)")
            // Throwing on ignored events would force callers to defensively wrap every
            // call in do/catch even when the no-op is intentional. Surface this as a
            // soft return by throwing a user-cancelled-style error? — no, the design
            // doc says ignored events are no-ops + log. We need to produce *something*
            // since the signature is non-Void. Honest answer: stop() should only be
            // reachable from .recording; if a caller invokes it from another state
            // they get a clear runtime fault, not silent swallowing of a result.
            preconditionFailure("RecordingSession.stop() called from \(state); guard upstream")
        }
        state = .finalizing
        Log.coordinator.info("state .recording → .finalizing")

        let stopT0 = clock()
        let url: URL
        do {
            url = try await pipeline.stop()
        } catch {
            Log.coordinator.error("pipeline.stop failed: \(String(describing: error), privacy: .public)")
            state = .idle
            throw RecordingSessionError.pipelineStopFailed(underlying: error)
        }
        let stopT1 = clock()

        state = .idle
        Log.coordinator.info("state .finalizing → .idle")

        return Result(
            outputURL: url,
            droppedFrames: pipeline.droppedFrames,
            stopLatencyMs: (stopT1 - stopT0) * 1_000
        )
    }

    /// Cancel. From `.idle` this is a no-op. From `.recording` transitions
    /// through `.cancelling → .idle`, calling `pipeline.cancel()` to tear
    /// down capture and unlink the `.partial`. Implementation lands in Task 7.
    public func cancel() async {
        Log.coordinator.info("cancel ignored from state \(String(describing: self.state), privacy: .public) (Task 7 will implement)")
        // Filled in by Task 7.
    }
}
```

Note: the `cancel()` body is intentionally a stub here — Task 7 implements the real transition. This task only needs `cancel()` to exist for the type to be usable.

The `preconditionFailure` in `stop()` is a deliberate design choice — the signature returns `Result` (non-optional, non-throwing for state mismatch). The state machine treats stop-from-non-recording as a programming error. The "ignored when state mismatch" semantics from the design doc apply to AppDelegate-level invocations; AppDelegate guards against this by only wiring the Stop button while in `.recording`. Re-evaluate if this becomes annoying in practice.

- [ ] **Step 4: Run tests — should pass**

```bash
swift test --filter RecordingSessionTests
```
Expected: 5 PASS (initial state; start happy path; start persists region; stop happy path; stop drop count passthrough).

```bash
swift test 2>&1 | tail -5
```
Expected: full suite green.

- [ ] **Step 5: Commit**

```bash
git add Sources/SnatchKit/Coordinator/RecordingSession.swift Tests/SnatchKitTests/RecordingSessionTests.swift
git commit -m "$(cat <<'EOF'
feat(coordinator): RecordingSession scaffold + start/stop happy path

@MainActor ObservableObject state machine with idle/recording/finalizing
/cancelling enum. Start from idle persists region + calls pipeline.start
+ moves to .recording. Stop from .recording moves through .finalizing
to .idle and returns Result(outputURL, droppedFrames, stopLatencyMs).
Cancel is a stub; Task 7 will implement.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: RecordingSession cancel paths (TDD)

**Files:**
- Modify: `Sources/SnatchKit/Coordinator/RecordingSession.swift` (`cancel()` body)
- Modify: `Tests/SnatchKitTests/RecordingSessionTests.swift` (append cancel tests)

Implements `cancel()`'s two paths: from `.idle` (no-op) and from `.recording` (`.recording → .cancelling → .idle`, calling `pipeline.cancel()`). Per design doc §4.3, this transition is wired in M4 even though no user-facing affordance triggers it until M5.

- [ ] **Step 1: Write the failing tests (RED)**

Append to `Tests/SnatchKitTests/RecordingSessionTests.swift` (just before the closing `}` of the class):

```swift
    @MainActor
    func test_cancel_fromIdle_isNoOp() async {
        let session = makeSession()
        XCTAssertEqual(session.state, .idle)

        await session.cancel()

        XCTAssertEqual(session.state, .idle)
        XCTAssertEqual(pipeline.cancelCallCount, 0,
                       "pipeline.cancel must not be called when session is idle")
        XCTAssertEqual(pipeline.startCalls.count, 0)
        XCTAssertEqual(pipeline.stopCallCount, 0)
    }

    @MainActor
    func test_cancel_fromRecording_transitionsToIdleAndCallsPipelineCancel() async throws {
        let session = makeSession()
        try await session.start(
            region: CGRect(x: 0, y: 0, width: 100, height: 100),
            scale: .standard, fps: 30,
            outputURL: URL(fileURLWithPath: "/tmp/m4.gif"),
            excludingWindows: []
        )
        XCTAssertEqual(session.state, .recording)

        await session.cancel()

        XCTAssertEqual(session.state, .idle)
        XCTAssertEqual(pipeline.cancelCallCount, 1)
    }

    @MainActor
    func test_cancel_fromRecording_doesNotCallPipelineStop() async throws {
        let session = makeSession()
        try await session.start(
            region: CGRect(x: 0, y: 0, width: 100, height: 100),
            scale: .standard, fps: 30,
            outputURL: URL(fileURLWithPath: "/tmp/m4.gif"),
            excludingWindows: []
        )

        await session.cancel()

        XCTAssertEqual(pipeline.stopCallCount, 0,
                       "cancel must use pipeline.cancel, not pipeline.stop")
    }
```

- [ ] **Step 2: Run tests — should fail**

```bash
swift test --filter RecordingSessionTests.test_cancel 2>&1 | tail -15
```
Expected: at least one of the three fails. The `_fromIdle_isNoOp` may pass by accident (current stub does nothing, leaves state at `.idle`, pipeline.cancel call count 0). The `_fromRecording_*` tests fail because the stub doesn't actually transition from `.recording` and doesn't call `pipeline.cancel()`.

- [ ] **Step 3: Implement cancel()**

In `Sources/SnatchKit/Coordinator/RecordingSession.swift`, replace the stub `cancel()` body with:

```swift
    public func cancel() async {
        switch state {
        case .idle:
            Log.coordinator.info("cancel from .idle (no-op)")
            return
        case .recording:
            state = .cancelling
            Log.coordinator.info("state .recording → .cancelling")
            await pipeline.cancel()
            state = .idle
            Log.coordinator.info("state .cancelling → .idle")
        case .finalizing, .cancelling:
            Log.coordinator.info("cancel ignored from state \(String(describing: self.state), privacy: .public)")
            return
        }
    }
```

- [ ] **Step 4: Run tests — should pass**

```bash
swift test --filter RecordingSessionTests
```
Expected: all 8 PASS (5 from Task 6 + 3 new cancel tests).

```bash
swift test 2>&1 | tail -5
```
Expected: full suite green.

- [ ] **Step 5: Commit**

```bash
git add Sources/SnatchKit/Coordinator/RecordingSession.swift Tests/SnatchKitTests/RecordingSessionTests.swift
git commit -m "$(cat <<'EOF'
feat(coordinator): RecordingSession.cancel for idle + recording paths

Cancel from .idle is a logged no-op. Cancel from .recording moves through
.cancelling to .idle and invokes pipeline.cancel (which on the production
side will stop SCStream, drain+discard the bridge, and unlink the .partial).
M5 will wire the user-facing cancel trigger via the Carbon Esc hotkey.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: RecordingSession error paths (TDD)

**Files:**
- Modify: `Tests/SnatchKitTests/RecordingSessionTests.swift` (append error-path tests)

Verifies `pipeline.start` and `pipeline.stop` errors get wrapped in `RecordingSessionError` and the state machine ends in a sane state. These tests exercise behavior already in `RecordingSession` from Task 6 — no implementation changes needed if Task 6 was implemented correctly. The TDD check here is "did Task 6 actually do what the doc said".

- [ ] **Step 1: Write the tests (likely already passing)**

Append to `Tests/SnatchKitTests/RecordingSessionTests.swift`:

```swift
    private struct StubPipelineError: Error, CustomStringConvertible {
        let label: String
        var description: String { "stub-pipeline-error[\(label)]" }
    }

    @MainActor
    func test_start_pipelineFailure_keepsStateIdleAndRethrowsWrapped() async {
        pipeline.startError = StubPipelineError(label: "start")
        let session = makeSession()

        do {
            try await session.start(
                region: CGRect(x: 0, y: 0, width: 100, height: 100),
                scale: .standard, fps: 30,
                outputURL: URL(fileURLWithPath: "/tmp/m4.gif"),
                excludingWindows: []
            )
            XCTFail("expected throw")
        } catch let err as RecordingSessionError {
            switch err {
            case .pipelineStartFailed(let underlying):
                XCTAssertEqual(String(describing: underlying), "stub-pipeline-error[start]")
            default:
                XCTFail("expected .pipelineStartFailed, got \(err)")
            }
        } catch {
            XCTFail("expected RecordingSessionError, got \(error)")
        }

        XCTAssertEqual(session.state, .idle)
    }

    @MainActor
    func test_stop_pipelineFailure_endsAtIdleAndRethrowsWrapped() async throws {
        let session = makeSession()
        try await session.start(
            region: CGRect(x: 0, y: 0, width: 100, height: 100),
            scale: .standard, fps: 30,
            outputURL: URL(fileURLWithPath: "/tmp/m4.gif"),
            excludingWindows: []
        )
        pipeline.stopError = StubPipelineError(label: "stop")

        do {
            _ = try await session.stop()
            XCTFail("expected throw")
        } catch let err as RecordingSessionError {
            switch err {
            case .pipelineStopFailed(let underlying):
                XCTAssertEqual(String(describing: underlying), "stub-pipeline-error[stop]")
            default:
                XCTFail("expected .pipelineStopFailed, got \(err)")
            }
        } catch {
            XCTFail("expected RecordingSessionError, got \(error)")
        }

        XCTAssertEqual(session.state, .idle,
                       "state must end at .idle even when pipeline.stop fails")
    }
```

- [ ] **Step 2: Run tests — should pass**

```bash
swift test --filter RecordingSessionTests
```
Expected: 10 PASS (8 from Tasks 6/7 + 2 new error-path tests). If either error test fails, fix the implementation in `RecordingSession.swift` per the test expectations — the design doc §3.1 / §5 specify the wrapping + end state.

```bash
swift test 2>&1 | tail -5
```
Expected: full suite green.

- [ ] **Step 3: Commit**

```bash
git add Tests/SnatchKitTests/RecordingSessionTests.swift
git commit -m "$(cat <<'EOF'
test(coordinator): RecordingSession error-path coverage

Verifies pipeline.start / pipeline.stop failures are wrapped in
RecordingSessionError.pipelineStart/StopFailed with the underlying
error preserved, and that state lands at .idle in both cases.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: RecordingSession ignored-event coverage (TDD)

**Files:**
- Modify: `Tests/SnatchKitTests/RecordingSessionTests.swift` (append ignored-event tests)

Verifies the no-op cells of the §3.1 transition table: `start` while not idle, `cancel` from idle (re-cover from a different angle), and the debounce semantics for `start` while a previous `start` is mid-flight. The implementation already covers these via the `guard state == ...` checks in Task 6.

- [ ] **Step 1: Write the tests**

Append to `Tests/SnatchKitTests/RecordingSessionTests.swift`:

```swift
    @MainActor
    func test_start_whileRecording_isIgnored() async throws {
        let session = makeSession()
        try await session.start(
            region: CGRect(x: 0, y: 0, width: 100, height: 100),
            scale: .standard, fps: 30,
            outputURL: URL(fileURLWithPath: "/tmp/m4-1.gif"),
            excludingWindows: []
        )
        XCTAssertEqual(session.state, .recording)
        XCTAssertEqual(pipeline.startCalls.count, 1)

        // Second start should be ignored, not re-enter the pipeline.
        try await session.start(
            region: CGRect(x: 50, y: 50, width: 200, height: 200),
            scale: .retina, fps: 30,
            outputURL: URL(fileURLWithPath: "/tmp/m4-2.gif"),
            excludingWindows: []
        )

        XCTAssertEqual(session.state, .recording)
        XCTAssertEqual(pipeline.startCalls.count, 1,
                       "pipeline.start must not be called twice")
    }

    @MainActor
    func test_secondStart_doesNotRepersistRegion() async throws {
        let session = makeSession()
        let firstRegion = CGRect(x: 0, y: 0, width: 100, height: 100)
        let secondRegion = CGRect(x: 200, y: 200, width: 50, height: 50)

        try await session.start(
            region: firstRegion, scale: .standard, fps: 30,
            outputURL: URL(fileURLWithPath: "/tmp/m4.gif"),
            excludingWindows: []
        )
        try await session.start(
            region: secondRegion, scale: .standard, fps: 30,
            outputURL: URL(fileURLWithPath: "/tmp/m4-2.gif"),
            excludingWindows: []
        )

        // Ignored second start must not have overwritten the persisted region.
        XCTAssertEqual(regionStore.lastRegion, firstRegion)
    }

    @MainActor
    func test_cancelDuringStart_observesIdleAndIsNoop() async throws {
        // pipeline.start blocks on a gate. While it's mid-flight, fire cancel().
        // The cancel must observe state == .idle (because the session sets
        // .recording only AFTER pipeline.start returns) and become a no-op.
        let gateOpen = AtomicBool()
        pipeline.startGate = {
            while !gateOpen.value {
                await Task.yield()
            }
        }

        let session = makeSession()
        let startTask = Task { @MainActor in
            try await session.start(
                region: CGRect(x: 0, y: 0, width: 100, height: 100),
                scale: .standard, fps: 30,
                outputURL: URL(fileURLWithPath: "/tmp/m4.gif"),
                excludingWindows: []
            )
        }

        // While start is parked on the gate, fire stop() and cancel().
        // Both should observe state == .idle (start hasn't returned yet)
        // and be ignored.
        // stop() preconditionFails from .idle by design — call cancel() only.
        await session.cancel()
        XCTAssertEqual(pipeline.cancelCallCount, 0,
                       "cancel during pre-recording-start window must be no-op")

        // Open the gate, let start finish.
        gateOpen.value = true
        try await startTask.value

        XCTAssertEqual(session.state, .recording)
    }

    /// Tiny @unchecked Sendable Bool for the test gate above. Plain `var Bool`
    /// can't cross @MainActor / Task boundaries cleanly under strict concurrency.
    private final class AtomicBool: @unchecked Sendable {
        private let lock = NSLock()
        private var _value = false
        var value: Bool {
            get { lock.withLock { _value } }
            set { lock.withLock { _value = newValue } }
        }
    }
```

Note: the stop()-while-idle case is covered by the `preconditionFailure` in Task 6's `stop()` implementation — we intentionally don't test that path here because the design choice is "fail fast on programming errors". AppDelegate guards against it by only wiring the Stop button while in `.recording`. The during-start test exercises the *cancel* version, which is the realistic case for race-condition testing.

- [ ] **Step 2: Run tests — should pass**

```bash
swift test --filter RecordingSessionTests
```
Expected: 13 PASS (10 from Tasks 6-8 + 3 new ignored-event tests).

```bash
swift test 2>&1 | tail -5
```
Expected: full suite green.

- [ ] **Step 3: Commit**

```bash
git add Tests/SnatchKitTests/RecordingSessionTests.swift
git commit -m "$(cat <<'EOF'
test(coordinator): RecordingSession ignored-event coverage

Verifies start-while-recording is a no-op, ignored second start does
not re-persist region, and cancel during a not-yet-returned start
observes .idle and remains a no-op (debounce per design doc §3.1).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 10: ScreenRecordingPipeline implementation

**Files:**
- Create: `Sources/SnatchKit/Coordinator/ScreenRecordingPipeline.swift`
- Create: `Tests/SnatchKitTests/ScreenRecordingPipelineTests.swift`

Concrete `RecordingPipeline` implementation. Lifts the inline plumbing from `Sources/SnatchRecordCLI/main.swift:99-216` into a class with proper lifecycle (no globals, no actor leaks). Behavior is byte-for-byte identical to M2 — same queues, same bridge capacity, same fence/drain at stop, same `Task.detached` for `gifski_finish`.

Unit tests in this task are limited to construction + initial-state checks. The end-to-end live verification lives in Task 12.

- [ ] **Step 1: Write the failing tests (RED)**

Create `Tests/SnatchKitTests/ScreenRecordingPipelineTests.swift`:

```swift
import XCTest
@testable import SnatchKit

final class ScreenRecordingPipelineTests: XCTestCase {

    func test_initialDroppedFrames_isZero() {
        let pipeline = ScreenRecordingPipeline()
        XCTAssertEqual(pipeline.droppedFrames, 0)
    }

    func test_pipelineConformsToRecordingPipelineProtocol() {
        // Compile-time check.
        let pipeline: any RecordingPipeline = ScreenRecordingPipeline()
        _ = pipeline
    }
}
```

- [ ] **Step 2: Run tests — should fail to compile**

```bash
swift test --filter ScreenRecordingPipelineTests 2>&1 | tail -10
```
Expected: compile error mentioning `ScreenRecordingPipeline` not found.

- [ ] **Step 3: Implement ScreenRecordingPipeline**

Create `Sources/SnatchKit/Coordinator/ScreenRecordingPipeline.swift`:

```swift
import Foundation
import CoreMedia
import CoreGraphics
import ScreenCaptureKit

/// Production `RecordingPipeline` impl. Owns the capture/encoder queues, the
/// bridge, the SCStream wrapper, the frame converter, and the gifski encoder
/// for the lifetime of one start..stop window.
///
/// This class is the home of the inline plumbing previously living in
/// `Sources/SnatchRecordCLI/main.swift:99-216` (M2). Behavior is byte-for-byte
/// equivalent — same queues, same bridge capacity (60), same fence-and-drain
/// at stop, same `Task.detached` for `gifski_finish`.
///
/// Threading: `@unchecked Sendable`. All mutable state is partitioned by the
/// captureQueue / encoderQueue invariants documented on `GifskiEncoder` and
/// `BridgeQueue`. Public `async` methods are reentrant-unsafe — callers must
/// not interleave start..stop windows on the same instance. `RecordingSession`
/// enforces that via its state machine.
public final class ScreenRecordingPipeline: RecordingPipeline, @unchecked Sendable {

    private let captureQueue = DispatchQueue(label: "co.snatch.capture", qos: .userInteractive)
    private let encoderQueue = DispatchQueue(label: "co.snatch.encoder", qos: .userInitiated)

    /// Lifecycle-scoped state. Allocated on `start`, retained until `stop` /
    /// `cancel`, then reset for reuse.
    private struct ActiveSession {
        let wrapper: SCStreamWrapper
        let converter: FrameConverter
        let bridge: BridgeQueue<(RGBAFrame, TimeInterval)>
        let encoder: GifskiEncoder
        let outputURL: URL
        let consumeTask: Task<Void, Never>
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

        let captureQueue = self.captureQueue
        let encoderQueue = self.encoderQueue

        // Same shape as M2's snatch-record-cli. The 1:1 dispatch coupling here
        // is a documented carry-over to M5 — see snatch-record-cli's old
        // comment block at lines 142-151.
        let consumeTask = Task {
            for await sample in stream {
                captureQueue.async {
                    guard let frame = converter.convert(sample) else { return }
                    let pts = sample.presentationTimeStamp.seconds
                    let base = ptsAnchor.anchor(pts)
                    let relativePTS = pts - base

                    let dropped = bridge.enqueue((frame, relativePTS))
                    if dropped > 0 && dropped % 10 == 0 {
                        Log.capture.debug("bridge drops at \(dropped, privacy: .public)")
                    }

                    encoderQueue.async {
                        if let item = bridge.dequeue() {
                            do {
                                try encoder.addFrame(item.0, presentationTime: item.1)
                            } catch {
                                Log.encoder.error("addFrame failed: \(String(describing: error), privacy: .public)")
                            }
                        }
                    }
                }
            }
        }

        active = ActiveSession(
            wrapper: wrapper,
            converter: converter,
            bridge: bridge,
            encoder: encoder,
            outputURL: outputURL,
            consumeTask: consumeTask
        )
    }

    public func stop() async throws -> URL {
        guard let s = active else {
            preconditionFailure("ScreenRecordingPipeline.stop called with no active session")
        }
        await s.wrapper.stop()
        s.consumeTask.cancel()

        // Fence: any in-flight captureQueue.async closures must complete before
        // we drain — otherwise late enqueues race with the drain. Same shape as
        // snatch-record-cli/main.swift:186-204.
        captureQueue.sync {}

        // Drain the bridge into the encoder.
        let bridge = s.bridge
        let encoder = s.encoder
        encoderQueue.sync {
            while let item = bridge.dequeue() {
                do {
                    try encoder.addFrame(item.0, presentationTime: item.1)
                } catch {
                    Log.encoder.error("drain addFrame failed: \(String(describing: error), privacy: .public)")
                }
            }
        }

        // gifski_finish blocks. Per spec §5, schedule off the calling thread.
        let finishTask = Task.detached(priority: .userInitiated) { [encoder] in
            try await encoder.finish()
        }
        try await finishTask.value

        let url = s.outputURL
        active = nil
        return url
    }

    public func cancel() async {
        guard let s = active else { return }
        await s.wrapper.stop()
        s.consumeTask.cancel()

        captureQueue.sync {}

        // Drain + discard any in-flight frames so they don't block the encoder
        // teardown. We don't add them to gifski since we're aborting.
        _ = s.bridge.drain()

        // GifskiEncoder.cancel() handles `gifski_finish` + unlink. May briefly
        // block — schedule off the @MainActor caller. Per the encoder doc
        // (§ Threading), cancel() must not run on main.
        let encoder = s.encoder
        let cancelTask = Task.detached(priority: .userInitiated) {
            encoder.cancel()
        }
        await cancelTask.value

        active = nil
    }
}

/// Mutex-protected `TimeInterval?` for the first-frame PTS we observe. The
/// captureQueue is serial, but multiple captureQueue closures may race to
/// observe firstPTS — explicit synchronization prevents that race.
///
/// Lifted from `Sources/SnatchRecordCLI/main.swift` (was `final class PTSAnchor`).
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

- [ ] **Step 4: Run tests — should pass**

```bash
swift test --filter ScreenRecordingPipelineTests
```
Expected: 2 PASS (initial droppedFrames; protocol conformance compile-check).

```bash
swift test 2>&1 | tail -5
```
Expected: full suite green.

- [ ] **Step 5: Commit**

```bash
git add Sources/SnatchKit/Coordinator/ScreenRecordingPipeline.swift Tests/SnatchKitTests/ScreenRecordingPipelineTests.swift
git commit -m "$(cat <<'EOF'
feat(coordinator): ScreenRecordingPipeline (concrete RecordingPipeline)

Lifts the M2 inline plumbing from snatch-record-cli/main.swift:99-216
into a reusable class. Same queues, same bridge capacity, same
fence/drain at stop, same Task.detached for gifski_finish. Live
integration test lands in Task 12; snatch-record-cli adoption in Task 11.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 11: Refactor snatch-record-cli to use ScreenRecordingPipeline

**Files:**
- Modify: `Sources/SnatchRecordCLI/main.swift` (replace lines 85-216 — the inline plumbing)

The CLI keeps its argv parsing and stays a fixed-duration smoke harness; the pipeline plumbing collapses to a few lines. This serves three purposes: (1) confirms the extraction works against M2's existing live test, (2) eliminates the now-duplicated logic, (3) gives M4's plan a regression check before AppDelegate gets rewired.

- [ ] **Step 1: Read the current main.swift**

Re-read `Sources/SnatchRecordCLI/main.swift` to confirm the structure: lines 1-83 are arg parsing + struct definitions; lines 85-216 are the inline plumbing that's about to be replaced.

- [ ] **Step 2: Replace the plumbing**

Open `Sources/SnatchRecordCLI/main.swift`. Delete lines 85-216 (everything from `/// Mutex-protected ...` through the final `print` call). Replace with:

```swift
let args = parseArgs()

let pipeline = ScreenRecordingPipeline()

do {
    try await pipeline.start(
        region: args.region,
        scale: args.scale,
        fps: args.fps,
        outputURL: args.output,
        excludingWindows: []
    )
} catch SCStreamWrapperError.permissionDenied {
    FileHandle.standardError.write(Data("""
    Snatch needs Screen Recording permission.
    Open System Settings → Privacy & Security → Screen Recording, enable
    this binary (or the parent terminal app), then re-run.

    """.utf8))
    exit(3)
} catch {
    FileHandle.standardError.write(Data("Capture start failed: \(error)\n".utf8))
    exit(1)
}

try? await Task.sleep(nanoseconds: UInt64(args.duration * 1_000_000_000))

let stopTriggerAt = CFAbsoluteTimeGetCurrent()

let outputURL: URL
do {
    outputURL = try await pipeline.stop()
} catch {
    FileHandle.standardError.write(Data("encoder.finish failed: \(error)\n".utf8))
    exit(1)
}

let stopLatencyMs = (CFAbsoluteTimeGetCurrent() - stopTriggerAt) * 1_000

print("✅ Wrote \(outputURL.path)")
print("   bridge drops: \(pipeline.droppedFrames)")
print("   stop → save latency: \(String(format: "%.1f", stopLatencyMs)) ms (target < 500 ms)")
```

- [ ] **Step 3: Verify build green**

```bash
swift build
```
Expected: succeeds, no warnings.

```bash
swift test 2>&1 | tail -5
```
Expected: full suite green. The existing M2 `PipelineIntegrationTests` and `SCStreamWrapperLiveTests` still pass (the latter still skipped without permission).

- [ ] **Step 4: Manual smoke check (regression for M2)**

If you have Screen Recording permission for the parent terminal:
```bash
swift run snatch-record-cli --duration 2 --output /tmp/m4-task11-regression.gif
```
Expected: produces a valid GIF (~1-3 MB depending on what's on screen). Output line includes `bridge drops: N` and `stop → save latency: Xms`. Latency under 500 ms.

```bash
file /tmp/m4-task11-regression.gif
```
Expected: `GIF image data, version 89a, ...`.

If permission is unavailable, document the skip in the commit message.

- [ ] **Step 5: Commit**

```bash
git add Sources/SnatchRecordCLI/main.swift
git commit -m "$(cat <<'EOF'
refactor(record-cli): use ScreenRecordingPipeline instead of inline plumbing

Replaces 130 lines of inline capture/encoder wiring with a few lines
calling pipeline.start/stop. Behavior identical — same queues, same
bridge capacity, same fence/drain. Confirms the M4 extraction is a
zero-behavior-change refactor before AppDelegate gets rewired.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 12: ScreenRecordingPipeline live integration test

**Files:**
- Create: `Tests/SnatchKitTests/ScreenRecordingPipelineLiveTests.swift`

Live capture test paralleling the existing `SCStreamWrapperLiveTests`. Skipped without screen-recording permission. Verifies a real ~1-second pipeline run produces a valid GIF on disk and meets the < 500 ms stop-latency target.

- [ ] **Step 1: Inspect the existing pattern**

Re-read `Tests/SnatchKitTests/SCStreamWrapperLiveTests.swift` to learn how it skips when permission is unavailable (`CGPreflightScreenCaptureAccess()` returns false → `throw XCTSkip(...)`).

- [ ] **Step 2: Write the test**

Create `Tests/SnatchKitTests/ScreenRecordingPipelineLiveTests.swift`:

```swift
import XCTest
import CoreGraphics
@testable import SnatchKit

/// End-to-end pipeline smoke test against real ScreenCaptureKit.
/// Skipped without Screen Recording permission for the host process.
final class ScreenRecordingPipelineLiveTests: XCTestCase {

    func test_oneSecondCapture_producesValidGifUnder500msStopLatency() async throws {
        guard CGPreflightScreenCaptureAccess() else {
            throw XCTSkip("Screen Recording permission not granted to test runner")
        }

        let outputURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("snatch-pipeline-live-\(UUID().uuidString).gif")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let pipeline = ScreenRecordingPipeline()
        try await pipeline.start(
            region: CGRect(x: 0, y: 0, width: 320, height: 240),
            scale: .standard,
            fps: 30,
            outputURL: outputURL,
            excludingWindows: []
        )

        try await Task.sleep(nanoseconds: 1_000_000_000)  // 1.0 s

        let stopT0 = CFAbsoluteTimeGetCurrent()
        let returned = try await pipeline.stop()
        let stopLatencyMs = (CFAbsoluteTimeGetCurrent() - stopT0) * 1_000

        XCTAssertEqual(returned, outputURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path),
                      "GIF file must exist at \(outputURL.path)")
        let attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        let size = attributes[.size] as! Int
        XCTAssertGreaterThan(size, 100,
                             "GIF file size suspiciously small: \(size) bytes")

        // Decode + sanity-check frame count.
        let decoder = try GifDecoder(url: outputURL)
        XCTAssertGreaterThan(decoder.frameCount, 5,
                             "expected several frames in 1s capture, got \(decoder.frameCount)")

        XCTAssertLessThan(stopLatencyMs, 500.0,
                          "stop → file-closed latency \(stopLatencyMs) ms exceeds 500 ms target")
    }
}
```

- [ ] **Step 3: Run the test**

```bash
swift test --filter ScreenRecordingPipelineLiveTests 2>&1 | tail -10
```

Two acceptable outcomes:
- **With permission**: PASS, with `stop → file-closed` latency printed under 500 ms.
- **Without permission**: SKIPPED via `XCTSkip` (matches `SCStreamWrapperLiveTests` behavior).

```bash
swift test 2>&1 | tail -5
```
Expected: full suite green. The skipped-test count goes from 1 to 2 if the test runner doesn't have permission.

- [ ] **Step 4: Commit**

```bash
git add Tests/SnatchKitTests/ScreenRecordingPipelineLiveTests.swift
git commit -m "$(cat <<'EOF'
test(coordinator): live integration test for ScreenRecordingPipeline

Mirrors SCStreamWrapperLiveTests' skip-without-permission pattern.
Captures a real 320×240 @ 30fps for 1 second, asserts the GIF lands
on disk with multiple frames and stop-latency stays under 500 ms.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 13: Args parsing for SnatchSessionCLI

**Files:**
- Create: `Sources/SnatchSessionCLI/Args.swift`
- Modify: `Sources/SnatchSessionCLI/main.swift`

`SnatchSessionCLI` needs three CLI args: `--output PATH`, `--scale {retina|standard|compact}`, `--fps N`. The region is acquired interactively via the cropper, so no `--region` flag (unlike `snatch-record-cli`). Pattern mirrors `SnatchRecordCLI`'s parser.

This task is mostly mechanical — argv parsing has a stable shape, no recursion, no edge cases worth elaborate testing. The plan keeps it short.

- [ ] **Step 1: Create Args.swift**

Create `Sources/SnatchSessionCLI/Args.swift`:

```swift
// Sources/SnatchSessionCLI/Args.swift
import Foundation
import SnatchKit

struct Args {
    var output: URL = URL(fileURLWithPath: "/tmp/snatch-session.gif")
    var scale: ScalePreset = .standard
    var fps: Int = 30
}

enum ArgsError: Error {
    case usage
}

func parseSessionArgs() -> Args {
    var args = Args()
    var i = 1
    let argv = CommandLine.arguments
    while i < argv.count {
        let arg = argv[i]
        switch arg {
        case "--output":
            i += 1
            guard i < argv.count else { sessionUsage() }
            args.output = URL(fileURLWithPath: argv[i])
        case "--scale":
            i += 1
            guard i < argv.count, let s = ScalePreset(rawValue: argv[i]) else { sessionUsage() }
            args.scale = s
        case "--fps":
            i += 1
            guard i < argv.count, let n = Int(argv[i]) else { sessionUsage() }
            args.fps = n
        case "-h", "--help":
            sessionUsage()
        default:
            FileHandle.standardError.write(Data("Unknown argument: \(arg)\n".utf8))
            sessionUsage()
        }
        i += 1
    }
    return args
}

func sessionUsage() -> Never {
    FileHandle.standardError.write(Data("""
    snatch-session-cli — interactive cropper + GIF recorder.

    Usage:
      snatch-session-cli [options]

    Options:
      --output PATH                       Output .gif path. Default /tmp/snatch-session.gif.
      --scale {retina|standard|compact}   Capture scale preset. Default standard.
      --fps N                             Capture frame rate. Default 30.

    Region is selected interactively via the cropper overlay.

    """.utf8))
    exit(2)
}
```

- [ ] **Step 2: Modify main.swift to parse args before NSApplication.run**

Open `Sources/SnatchSessionCLI/main.swift`. The current contents (post-Task 1 rename) are:

```swift
// Sources/SnatchSessionCLI/main.swift
//
// snatch-cropper-cli — full-screen cropper UI smoke harness for M3.
// ... (long block describing M3 behavior)

import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
...
```

Replace the file with:

```swift
// Sources/SnatchSessionCLI/main.swift
//
// snatch-session-cli — interactive cropper + GIF recorder.
//
// On launch:
//   1. Parses args (--output, --scale, --fps).
//   2. Shows the M3 transparent cropper overlay.
//   3. On Record (button or Space/Enter): hides cropper, shows the
//      red-border recording overlay with a Stop button, drives a
//      RecordingSession through the M2 capture pipeline + M1 encoder.
//   4. On Stop: saves the GIF, prints "SAVED <url> (drops=N, stop-latency=Xms)",
//      and terminates.
//   5. On Esc during cropping: prints "CANCELLED" and terminates.
//
// Run:
//   swift run snatch-session-cli --output /tmp/m4-smoke.gif
//
// M5 will lift these files into Snatch.xcodeproj when LSUIElement,
// hotkey, and notifications all need a bundle simultaneously.

import AppKit

let parsedArgs = parseSessionArgs()

let app = NSApplication.shared
let delegate = AppDelegate(args: parsedArgs)
app.delegate = delegate

// Foreground the process so the cropper window is key + frontmost. SPM
// executables otherwise launch as ".Background" and may not become key.
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)

app.run()
```

- [ ] **Step 3: Update AppDelegate's signature to accept Args**

This step touches only the `init` — full rewiring lands in Task 16. Open `Sources/SnatchSessionCLI/AppDelegate.swift` and add a stored property + initializer at the top of the class (above the existing `private var cropperWindow:` line):

```swift
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let args: Args

    init(args: Args) {
        self.args = args
        super.init()
    }

    // ... (rest of existing class body)
```

The existing `private var cropperWindow: NSWindow?` and `private let regionStore = RegionStore()` properties stay. The existing `applicationDidFinishLaunching` body stays — Task 16 rewrites it.

- [ ] **Step 4: Verify build green**

```bash
swift build
```
Expected: succeeds, no warnings.

```bash
swift run snatch-session-cli --help 2>&1 | head -10
```
Expected: prints the usage block above; exit code 2.

```bash
swift run snatch-session-cli --scale invalid 2>&1 | head -5
```
Expected: prints usage block to stderr; exit code 2.

```bash
swift run snatch-session-cli 2>&1 | head -1 &
PID=$!
sleep 1
kill $PID 2>/dev/null
```
Expected: cropper window appears (M3 behavior still intact post-Args plumbing). The kill is to avoid leaving a stray process.

- [ ] **Step 5: Commit**

```bash
git add Sources/SnatchSessionCLI/Args.swift Sources/SnatchSessionCLI/main.swift Sources/SnatchSessionCLI/AppDelegate.swift
git commit -m "$(cat <<'EOF'
feat(session-cli): argv parser for --output / --scale / --fps

Mirrors SnatchRecordCLI's parser. Region is selected interactively via
the cropper, so no --region flag. AppDelegate now takes an Args struct
in init; full RecordingSession wiring lands in Task 16.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 14: RecordingStopButton

**Files:**
- Create: `Sources/SnatchSessionCLI/RecordingStopButton.swift`

Small NSButton subclass mirroring `CropperRecordButton` — same 88×28 size, same bezel/font, but red-tinted with a "Stop" label. AppKit-only; no tests (smoke-tested in Task 17).

- [ ] **Step 1: Create the file**

Create `Sources/SnatchSessionCLI/RecordingStopButton.swift`:

```swift
// Sources/SnatchSessionCLI/RecordingStopButton.swift
import AppKit

/// Pill-shaped "Stop" button rendered next to the recording overlay rectangle.
/// Subclassed only to centralize styling — behavior is plain NSButton.
final class RecordingStopButton: NSButton {

    static let preferredSize = CGSize(width: 88, height: 28)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.title = "Stop"
        self.bezelStyle = .rounded
        self.isBordered = true
        self.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        self.contentTintColor = .systemRed
        self.keyEquivalent = ""  // No accelerator — overlay window doesn't take key focus.
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }
}
```

- [ ] **Step 2: Verify build green**

```bash
swift build
```
Expected: succeeds, no warnings.

```bash
swift test 2>&1 | tail -5
```
Expected: full suite green. No tests added — visual smoke happens in Task 17.

- [ ] **Step 3: Commit**

```bash
git add Sources/SnatchSessionCLI/RecordingStopButton.swift
git commit -m "$(cat <<'EOF'
feat(session-cli): RecordingStopButton (red NSButton subclass)

Mirrors CropperRecordButton's pattern. 88×28 rounded bezel, system-red
content tint, "Stop" label. Used by RecordingOverlayWindow (Task 15).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 15: RecordingOverlayWindow with click-through hit-test

**Files:**
- Create: `Sources/SnatchSessionCLI/RecordingOverlayWindow.swift`

Borderless transparent `NSWindow` at `.screenSaver` level, sized to fully cover the cropper-selected region. Renders a thin red border stroked around the rectangle. The content view returns `nil` from `hitTest(_:)` for non-button regions so clicks pass through to apps underneath. The Stop button is the only hit-testable subview.

This is AppKit glue — no unit tests; visual + interactive verification in Task 17.

- [ ] **Step 1: Create the file**

Create `Sources/SnatchSessionCLI/RecordingOverlayWindow.swift`:

```swift
// Sources/SnatchSessionCLI/RecordingOverlayWindow.swift
import AppKit

/// Transparent borderless overlay shown around the recording region during
/// `.recording`. Renders a thin red border around the rectangle; everything
/// inside the border is click-through so apps underneath stay usable.
/// Hosts the Stop button as the only hit-testable subview.
///
/// This window is added to `SCContentFilter`'s exclusion list so the overlay
/// itself never appears in the recorded GIF (per spec §6).
final class RecordingOverlayWindow: NSWindow {

    /// Called when the user clicks the Stop button.
    var onStop: (() -> Void)?

    private let overlayView: RecordingOverlayView

    /// Width of the red border stroke, in points.
    static let borderWidth: CGFloat = 2.5

    /// Margin between the rectangle and the Stop button (when button is outside).
    static let stopButtonMargin: CGFloat = 8

    /// `regionInScreenCoords` is the screen-space rectangle (CG coords, top-left
    /// origin) that the user selected via the cropper. The window's frame is
    /// inflated by 64 points on each side so the Stop button can land outside
    /// the rectangle when there's room.
    init(regionInScreenCoords region: CGRect) {
        let inset: CGFloat = 64
        let windowFrame = region.insetBy(dx: -inset, dy: -inset)

        // Convert from CG coords (top-left origin) to AppKit coords (bottom-left
        // origin) for the NSWindow init. NSScreen.main.frame.height gives the
        // primary screen's logical height; M5 multi-display will need to pick the
        // correct screen.
        let screenHeight = NSScreen.main?.frame.height ?? 0
        let appKitFrame = NSRect(
            x: windowFrame.origin.x,
            y: screenHeight - windowFrame.maxY,
            width: windowFrame.width,
            height: windowFrame.height
        )

        // Region inside the window's local (view) coordinate space, with the
        // 64-point inset accounted for. We pass the view-local rect to the
        // content view so it can draw and lay out without re-doing the conversion.
        let regionInViewCoords = CGRect(
            x: inset,
            y: inset,
            width: region.width,
            height: region.height
        )

        self.overlayView = RecordingOverlayView(
            frame: NSRect(origin: .zero, size: appKitFrame.size),
            regionInViewCoords: regionInViewCoords
        )

        super.init(
            contentRect: appKitFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.level = .screenSaver
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // Allow mouse events on the Stop button; the content view's hitTest
        // returns nil elsewhere to pass clicks through.
        self.ignoresMouseEvents = false

        self.contentView = overlayView
        overlayView.onStop = { [weak self] in
            self?.onStop?()
        }
    }

    // Borderless windows default to canBecomeKey=false. We intentionally do NOT
    // override here — the overlay should not steal focus from underlying apps.
    // The Stop button is hit-tested without needing key status.
}

/// Content view of `RecordingOverlayWindow`. Draws the thin red border around
/// `regionInViewCoords` and hosts the Stop button. Returns nil from hitTest
/// for non-button regions so clicks pass through.
private final class RecordingOverlayView: NSView {

    var onStop: (() -> Void)?
    private let regionInViewCoords: CGRect
    private let stopButton: RecordingStopButton

    init(frame: NSRect, regionInViewCoords: CGRect) {
        self.regionInViewCoords = regionInViewCoords
        self.stopButton = RecordingStopButton(
            frame: NSRect(origin: .zero, size: RecordingStopButton.preferredSize)
        )
        super.init(frame: frame)
        stopButton.target = self
        stopButton.action = #selector(stopClicked(_:))
        addSubview(stopButton)
        layoutStopButton()
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }

    /// Flipped so y-down matches CG coords; consistent with CropperView (M3).
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // Draw the thin red border centered on the rectangle's edge.
        NSColor.systemRed.setStroke()
        let stroked = regionInViewCoords.insetBy(
            dx: RecordingOverlayWindow.borderWidth / 2,
            dy: RecordingOverlayWindow.borderWidth / 2
        )
        let path = NSBezierPath(rect: stroked)
        path.lineWidth = RecordingOverlayWindow.borderWidth
        path.stroke()
    }

    /// Pass clicks through everywhere except the Stop button.
    override func hitTest(_ point: NSPoint) -> NSView? {
        // `point` is in our SUPERVIEW's coords (window content view); convert
        // to our local space for the button-frame check.
        let local = convert(point, from: superview)
        if stopButton.frame.contains(local) {
            return stopButton
        }
        return nil
    }

    @objc private func stopClicked(_ sender: Any?) {
        onStop?()
    }

    override func layout() {
        super.layout()
        layoutStopButton()
    }

    private func layoutStopButton() {
        let btnSize = RecordingStopButton.preferredSize
        let margin = RecordingOverlayWindow.stopButtonMargin

        // Default placement: just below the rectangle's bottom-right corner,
        // outside the red border (so it doesn't compete visually with the rect).
        var x = regionInViewCoords.maxX - btnSize.width
        var y = regionInViewCoords.maxY + margin

        // Fall back inside the rectangle's bottom-right if outside-placement
        // would clip off the bottom of the window (rectangle hugs screen edge).
        if y + btnSize.height > bounds.height {
            y = regionInViewCoords.maxY - btnSize.height - margin
        }

        // Clamp x so the button doesn't fall off the left/right edge of the window.
        x = max(0, min(x, bounds.width - btnSize.width))

        stopButton.frame = NSRect(x: x, y: y, width: btnSize.width, height: btnSize.height)
    }
}
```

- [ ] **Step 2: Verify build green**

```bash
swift build
```
Expected: succeeds, no warnings.

```bash
swift test 2>&1 | tail -5
```
Expected: full suite green. The new file isn't yet referenced from `AppDelegate`; it just compiles.

- [ ] **Step 3: Commit**

```bash
git add Sources/SnatchSessionCLI/RecordingOverlayWindow.swift
git commit -m "$(cat <<'EOF'
feat(session-cli): RecordingOverlayWindow (red border + click-through Stop)

Borderless transparent NSWindow at screenSaver level. Draws a 2.5pt red
border stroked around the recording region; content view's hitTest
returns nil everywhere except the Stop button so clicks pass through
to apps underneath. Stop button placed outside the rect by default,
falls back inside when the rect hugs a screen edge. Will be added to
SCContentFilter's exclusion list by AppDelegate (Task 16).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 16: Wire AppDelegate to RecordingSession + overlay

**Files:**
- Modify: `Sources/SnatchSessionCLI/AppDelegate.swift` (full rewrite)

The big integration step. AppDelegate orchestrates the four components: cropper window (M3), recording session (Task 6+), recording pipeline (Task 10), and recording overlay window (Task 15). It resolves `[SCWindow]` for the cropper + overlay before calling `session.start`.

- [ ] **Step 1: Replace AppDelegate.swift with the full M4 version**

Open `Sources/SnatchSessionCLI/AppDelegate.swift`. The current contents (after Tasks 1 + 13) have the `init(args:)` + the M3 cropper-only flow. Replace the entire file with:

```swift
// Sources/SnatchSessionCLI/AppDelegate.swift
import AppKit
import ScreenCaptureKit
import SnatchKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let args: Args
    private let regionStore = RegionStore()

    private let pipeline: ScreenRecordingPipeline
    private let session: RecordingSession

    private var cropperWindow: CropperWindow?
    private var overlayWindow: RecordingOverlayWindow?

    /// Coordinate-space conversion is per primary display — multi-display lands in M5.
    private weak var primaryScreen: NSScreen?

    init(args: Args) {
        self.args = args
        self.pipeline = ScreenRecordingPipeline()
        self.session = RecordingSession(pipeline: pipeline, regionStore: regionStore)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let screen = NSScreen.main else {
            Self.printAndExit("CANCELLED", code: 0)
            return
        }
        self.primaryScreen = screen

        // Pre-draw the persisted region (in screen coords) translated to view-local.
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
            // Outbound: view-local → screen-space (CG coords).
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

    // MARK: - Cropper callbacks

    private func cropperRecordRequested(region: CGRect) {
        Task { @MainActor [weak self] in
            await self?.runRecordingFlow(region: region)
        }
    }

    private func cropperCancelled() {
        Task { @MainActor [weak self] in
            await self?.session.cancel()
            Self.printAndExit("CANCELLED", code: 0)
        }
    }

    // MARK: - Recording flow

    private func runRecordingFlow(region: CGRect) async {
        guard let cropperWindow = self.cropperWindow else {
            Self.printAndExit("ERROR: cropper window missing", code: 1, toStderr: true)
            return
        }

        // 1. Show the recording overlay first so it has a windowNumber assigned
        //    by WindowServer before we ask SCShareableContent to enumerate windows.
        let overlay = RecordingOverlayWindow(regionInScreenCoords: region)
        overlay.onStop = { [weak self] in
            self?.stopRequested()
        }
        overlay.orderFrontRegardless()
        self.overlayWindow = overlay

        // 2. Resolve [SCWindow] for cropper + overlay.
        let windowNumbers: [Int] = [cropperWindow.windowNumber, overlay.windowNumber]
        let scWindows: [SCWindow]
        do {
            scWindows = try await Self.resolveSCWindows(forNumbers: windowNumbers)
        } catch {
            Self.printAndExit("ERROR resolving SCWindows: \(error)", code: 1, toStderr: true)
            return
        }
        if scWindows.count != windowNumbers.count {
            Log.coordinator.error(
                "expected \(windowNumbers.count, privacy: .public) SCWindows, got \(scWindows.count, privacy: .public); overlay or cropper may leak into capture"
            )
        }

        // 3. Hide the cropper now (after SCWindow resolution — cropper must still
        //    be onscreen for the WindowServer to enumerate it).
        cropperWindow.orderOut(nil)

        // 4. Drive the session.
        do {
            try await session.start(
                region: region,
                scale: args.scale,
                fps: args.fps,
                outputURL: args.output,
                excludingWindows: scWindows
            )
        } catch RecordingSessionError.pipelineStartFailed(let underlying) {
            if case SCStreamWrapperError.permissionDenied = underlying {
                Self.printAndExit(
                    "Snatch needs Screen Recording permission. Open System Settings → Privacy & Security → Screen Recording.",
                    code: 3, toStderr: true
                )
            } else {
                Self.printAndExit("ERROR: \(String(describing: underlying))", code: 1, toStderr: true)
            }
            return
        } catch {
            Self.printAndExit("ERROR: \(error.localizedDescription)", code: 1, toStderr: true)
            return
        }

        // Now in .recording — wait for stopRequested() (Stop button click) to
        // call session.stop(). The flow continues there.
    }

    private func stopRequested() {
        Task { @MainActor [weak self] in
            await self?.runStopFlow()
        }
    }

    private func runStopFlow() async {
        do {
            let result = try await session.stop()
            overlayWindow?.orderOut(nil)
            overlayWindow = nil
            print("SAVED \(result.outputURL.path) (drops=\(result.droppedFrames), stop-latency=\(String(format: "%.1f", result.stopLatencyMs))ms)")
            NSApplication.shared.terminate(nil)
        } catch {
            overlayWindow?.orderOut(nil)
            overlayWindow = nil
            Self.printAndExit("RECORDING FAILED: \(error.localizedDescription)", code: 1, toStderr: true)
        }
    }

    // MARK: - SCWindow resolution

    /// Look up `[SCWindow]` for the given AppKit `NSWindow.windowNumber` values.
    /// Retries once after 50 ms if any are missing (race with WindowServer
    /// registration). Falls back to whatever it found after the retry.
    private static func resolveSCWindows(forNumbers numbers: [Int]) async throws -> [SCWindow] {
        let targetIDs = Set(numbers.map { CGWindowID($0) })

        let firstTry = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true
        ).windows.filter { targetIDs.contains($0.windowID) }

        if firstTry.count == numbers.count {
            return firstTry
        }

        // Retry once.
        try? await Task.sleep(nanoseconds: 50_000_000)
        let secondTry = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true
        ).windows.filter { targetIDs.contains($0.windowID) }
        return secondTry
    }

    // MARK: - Termination helper

    private static func printAndExit(_ message: String, code: Int32, toStderr: Bool = false) {
        if toStderr {
            FileHandle.standardError.write(Data((message + "\n").utf8))
        } else {
            print(message)
        }
        NSApplication.shared.terminate(nil)
    }
}
```

- [ ] **Step 2: Verify build green**

```bash
swift build
```
Expected: succeeds, no warnings.

```bash
swift test 2>&1 | tail -5
```
Expected: full suite green. AppDelegate is glue that's exercised by the manual smoke gate (Task 17), not by unit tests.

- [ ] **Step 3: Commit**

```bash
git add Sources/SnatchSessionCLI/AppDelegate.swift
git commit -m "$(cat <<'EOF'
feat(session-cli): wire AppDelegate to RecordingSession + overlay

End-to-end M4 integration. Cropper.onRecord → resolve [SCWindow] →
hide cropper → show RecordingOverlayWindow → session.start.
Overlay.onStop → session.stop → print SAVED line + terminate.
Cropper.onCancel → session.cancel + print CANCELLED.

Permission-denied surfaces a System Settings hint to stderr.
Other errors stringify and exit 1. Multi-display deferred to M5.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 17: Manual smoke gate, CLAUDE.md update, and tag

**Files:**
- Modify: `CLAUDE.md` (Status section)
- Tag: `m4-coordinator-wiring`

The end. M4 ships when this manual checklist passes by a human at the keyboard. There are no automated steps that can substitute for this — the cropper, overlay, capture, and Stop button are all exercised together against real ScreenCaptureKit, with eyeballs verifying that the cropper / red border / Stop button do not appear in the recorded GIF.

- [ ] **Step 1: Run automated checks one last time**

```bash
swift build
```
Expected: succeeds, no warnings.

```bash
swift test 2>&1 | tail -10
```
Expected (M3 baseline = 75 default green + 1 skipped live):
- New default-suite tests: 18 (13 RecordingSession + 2 RecordingSessionError + 2 ScreenRecordingPipeline + 1 RegionStore Sendable check). Total default suite: 93 passing.
- New skipped-without-permission test: 1 (ScreenRecordingPipelineLive). Total skipped without permission: 2 (the existing M2 SCStreamWrapperLive + this new one).
- With Screen Recording permission granted to the test runner: 95 passing, 0 skipped.
- Failures: 0 in either case.

- [ ] **Step 2: Manual smoke — happy path**

```bash
swift run snatch-session-cli --output /tmp/m4-smoke.gif
```

Walk through:
1. Cropper appears full-screen dim. Drag a region (say, 600×400 over a window with visible movement — a video player or a Console app scrolling).
2. Resize via the 8 handles to verify the cropper still works.
3. Click Record (or press Space/Enter).
4. Cropper fades; thin red border appears around the captured region. Floating Stop button visible to the bottom-right of the rectangle (or inside if region hugs the edge).
5. Move cursor / scroll the captured app for 3-5 seconds.
6. Click Stop.
7. Output line printed: `SAVED /tmp/m4-smoke.gif (drops=N, stop-latency=Xms)`. Latency under 500 ms.
8. Open the GIF in QuickLook (`qlmanage -p /tmp/m4-smoke.gif` or open in Finder + spacebar).
9. Inspect: animation plays. **Cropper dim, handles, Record button, red border, and Stop button must all be absent from the recorded frames.**

If Step 9 fails (overlay leaks into the GIF), grep `Log.coordinator` output for "expected N SCWindows, got M" — if M < N, the SCShareableContent enumeration raced. The retry in `resolveSCWindows` should mitigate, but persistent failures may need a longer wait or a different resolution strategy. File this as a blocking issue.

- [ ] **Step 3: Manual smoke — cancel path**

```bash
swift run snatch-session-cli
```

1. Cropper appears.
2. Press Esc (without selecting a region).
3. Output: `CANCELLED`. Exit 0.
4. No GIF file at the default `/tmp/snatch-session.gif` path (or, if a previous run left one, the file's mtime is unchanged).

- [ ] **Step 4: Manual smoke — region persistence**

Re-run from Step 2 (the happy path) without specifying a region. The cropper should pre-draw the rectangle from the previous successful Record. Confirm by visually identifying the persisted rectangle and the floating Record button without dragging.

```bash
swift run snatch-session-cli --output /tmp/m4-smoke-persistence.gif
```

- [ ] **Step 5: Manual smoke — record-cli regression**

```bash
swift run snatch-record-cli --duration 2 --output /tmp/m4-record-cli-regression.gif
```
Expected: produces a valid GIF (~1-3 MB), prints `bridge drops: N` and `stop → save latency: Xms`. Latency under 500 ms. Confirms the M2 smoke harness still works after the `ScreenRecordingPipeline` extraction.

- [ ] **Step 6: Update CLAUDE.md Status section**

Open `CLAUDE.md`. The current Status section is at lines 31-40 (approximately). The M4 entry currently reads:
```markdown
- **M4 — Coordinator wiring** is next. `RecordingSession` state machine integrates Cropper + Capture + Encoder. Click Record → records → click stop → GIF saved. Hotkey not yet hooked up; menubar minimal.
```

Replace with:
```markdown
- **M4 — Coordinator wiring ✅ Complete** (tag `m4-coordinator-wiring`). `RecordingSession` (`@MainActor` ObservableObject state machine in `SnatchKit/Coordinator/`) drives the M3 cropper, the new `ScreenRecordingPipeline` (which subsumes the M2 inline plumbing), and the M1 encoder end-to-end. Click Record → red-border overlay with floating Stop button → click Stop → GIF saved. Cancel-from-cropping (Esc) works. Cancel-from-recording is wired in the state machine + tested via `FakeRecordingPipeline` but not user-triggerable until M5 brings the Carbon Esc hotkey. The M3 `SnatchCropperCLI` target was renamed to `SnatchSessionCLI` (binary: `snatch-session-cli`); the `m3-cropper-ui` tag preserves the old name historically. `snatch-record-cli` now uses `ScreenRecordingPipeline` directly — no behavior change.
- **M5 — Menubar + hotkey + system polish + pre-warm** is next.
```

- [ ] **Step 7: Commit + tag**

```bash
git add CLAUDE.md
git commit -m "$(cat <<'EOF'
docs: M4 coordinator wiring complete

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
git tag m4-coordinator-wiring
```

- [ ] **Step 8: Verify final state**

```bash
git log --oneline m3-cropper-ui..HEAD | wc -l
```
Expected: 17 commits (one per task). Adjust if Tasks 6/7/8/9 were folded together.

```bash
git tag --list | tail -5
```
Expected: `m4-coordinator-wiring` is present.

```bash
swift test 2>&1 | tail -5
```
Expected: full suite green; ScreenRecordingPipelineLiveTests skipped or pass per permission availability.

---

## Done criteria

M4 ships when ALL of the following hold:

1. `swift build` succeeds, no warnings.
2. `swift test` shows green for the full default suite, including the new M4 tests:
   - `RecordingSessionErrorTests` (2)
   - `RecordingSessionTests` (13)
   - `ScreenRecordingPipelineTests` (2)
   - `ScreenRecordingPipelineLiveTests` (1, skipped without permission)
   - `RegionStoreTests` Sendable check (1 new)
3. `swift run snatch-session-cli --output /tmp/m4-smoke.gif` completes the full happy path (Task 17 Step 2). The recorded GIF contains no overlay artifacts.
4. `swift run snatch-session-cli` + Esc completes the cancel path (Task 17 Step 3).
5. Region persistence: re-run after a successful Record → cropper opens with the persisted rectangle pre-drawn (Task 17 Step 4).
6. `swift run snatch-record-cli --duration 2 --output /tmp/...gif` still produces a valid GIF with stop-latency < 500 ms (Task 17 Step 5).
7. The git tag `m4-coordinator-wiring` exists.
8. `CLAUDE.md` Status section reflects M4 done and the `SnatchCropperCLI → SnatchSessionCLI` rename.

## Carry-overs to M5

These aren't bugs — they're known seams M5 will need to close:

- **Global hotkey (`⇧⌘6` via Carbon).** No keyboard trigger for record/stop in M4.
- **Carbon Esc hotkey during recording.** Cancel-during-recording is wired in the state machine and unit-tested via `FakeRecordingPipeline.cancel`, but not user-triggerable.
- **`NSStatusItem` menubar.** Idle/recording icon states, scale dropdown, Recent Recordings, About, Quit.
- **`NotificationPresenter` + `PasteboardWriter`.** M4 prints `SAVED <path>` to stdout; M5 surfaces a macOS notification + copies the file URL to the clipboard.
- **`PathProvider` Desktop auto-naming.** M4 takes `--output PATH`; M5 defaults to `~/Desktop/snatch-YYYY-MM-DD-HH-mm-ss.gif`.
- **Partial-file sweep on launch.** Spec §8 — delete orphan `*.gif.partial` files at app launch.
- **Pre-warm strategy.** Cropper instantiated hidden at launch; `SCShareableContent` cached and refreshed reactively. The < 100 ms hotkey-to-cropper target is M5.
- **Permission-flow modals + System Settings deep-link.** M4 prints the System Settings hint to stderr; M5 adds the proper modal flow.
- **Multi-display reconfigure handling.** M4 picks `NSScreen.main` for cropper + overlay positioning. Multi-display + display reconnects are M5.
- **Pipeline backpressure refactor.** The 1:1 capture-to-encoder dispatch coupling at `Sources/SnatchRecordCLI/main.swift:142-151` (now in `ScreenRecordingPipeline.start`) is preserved by M4 verbatim. The cleaner producer/consumer shape is M5 work.
- **Lift `SnatchSessionCLI/` files into `Snatch.xcodeproj`.** M5 introduces the Xcode project when LSUIElement, Carbon, and notifications all need a bundle simultaneously. The file layout per spec §5 stays; only the build system changes.
