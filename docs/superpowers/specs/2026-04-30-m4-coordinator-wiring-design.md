# M4 — Coordinator Wiring · Design

**Date**: 2026-04-30
**Status**: Approved (brainstorming complete; pending writing-plans decomposition)
**Master spec**: [`2026-04-30-snatch-design.md`](2026-04-30-snatch-design.md) (§6 RecordingSession, §7 Flows 1-3, §8 errors, §10 M4 paragraph)

## 1. Goal

Wire the M3 cropper, the M2 capture pipeline, and the M1 encoder together end-to-end behind a `RecordingSession` state machine. After M4 lands: a user runs `swift run snatch-session-cli`, drags a region, clicks Record, sees thin red border feedback with a floating Stop button, clicks Stop, and a GIF is written to disk. Cancel-from-cropping (Esc) works. Hotkey, full menubar, notifications, clipboard, Desktop auto-naming, and pre-warm remain M5 work.

## 2. Locked decisions (from brainstorming)

These four design questions were settled before the doc was written:

1. **Stop trigger UX = floating Stop button on the red-border recording overlay.** The red-border overlay window is the spec §4 recording feedback ("thin red border around captured region, excluded from capture") — it has to be built eventually. M4 builds it now and adds a small floating "Stop" button as the user-triggerable stop affordance, since hotkey + menubar are M5. Pulls real product UX work forward by one milestone.

2. **CLI target rename: `SnatchCropperCLI` → `SnatchSessionCLI`.** The M3 cropper-only smoke harness expands into the M4 session driver. Mechanical rename in the first commit of M4 (`Sources/SnatchCropperCLI/` → `Sources/SnatchSessionCLI/`, `Package.swift` product name, `swift run` invocations in CLAUDE.md). The `m3-cropper-ui` tag preserves the previous form historically.

3. **`RecordingPipeline` protocol seam.** Extract the inline pipeline plumbing currently in `Sources/SnatchRecordCLI/main.swift:99-216` (capture/encoder queues + `BridgeQueue` + `SCStreamWrapper` + `FrameConverter` + `GifskiEncoder` + PTS anchor + drain logic) into a new `RecordingPipeline` protocol with one concrete implementation `ScreenRecordingPipeline`. `RecordingSession` depends on the protocol. Tests inject a `FakeRecordingPipeline`. `snatch-record-cli` is simplified to use the same class — no behavioral change, just the same M2 plumbing relocated and given a name.

4. **Cancel-during-recording: build the *transition*, defer the *trigger* to M5.** `RecordingSession.cancel()` and the full `recording → cancelling → idle` path (including pipeline cancel + `.partial` deletion) are implemented and unit-tested in M4. The user-facing affordance for it (Carbon Esc hotkey per spec §7 Flow 3) lands in M5. The M4 red-border overlay has only a "Stop" button — no Cancel button.

## 3. Components

### 3.1 New in `Sources/SnatchKit/Coordinator/` (this directory does not yet exist)

```
Coordinator/
├── RecordingSession.swift        — state machine (ObservableObject)
├── RecordingPipeline.swift       — protocol
├── ScreenRecordingPipeline.swift — concrete impl owning queues + bridge + wrapper + encoder
└── RecordingSessionError.swift   — LocalizedError enum
```

#### `RecordingSession`

```swift
@MainActor
public final class RecordingSession: ObservableObject {
    public enum State: Equatable {
        case idle
        case recording
        case finalizing
        case cancelling
    }

    public struct Result: Sendable {
        public let outputURL: URL
        public let droppedFrames: Int
        public let stopLatencyMs: Double
    }

    @Published public private(set) var state: State = .idle

    public init(pipeline: RecordingPipeline,
                regionStore: RegionStore,
                clock: @escaping () -> CFAbsoluteTime = CFAbsoluteTimeGetCurrent)

    /// Idle → Recording. Persists region. Calls pipeline.start.
    /// Throws if pipeline.start throws (state stays .idle).
    public func start(region: CGRect,
                      scale: ScalePreset,
                      fps: Int,
                      outputURL: URL,
                      excludingWindows: [SCWindow]) async throws

    /// Recording → Finalizing → Idle. Returns final URL + drop count + latency.
    /// Throws if pipeline.stop throws (state still ends at .idle, .partial may remain).
    public func stop() async throws -> Result

    /// Cropping → Idle (no-op if pipeline isn't running) OR Recording → Cancelling → Idle
    /// (pipeline.cancel; .partial unlinked).
    public func cancel() async
}
```

**State machine — strict 4-state enum.** The spec §6 5-state model includes `.cropping`; M4 deviates by representing the cropping substate as AppDelegate's UI mode while `RecordingSession.state == .idle`. Rationale: keeps `RecordingSession` free of `NSWindow` / cropper-lifecycle concerns; the boundary "Coordinator does not import UI primitives directly" stays clean. M5 may revisit when the menubar app boots cropper from a hotkey.

**Public input → state transition table** (every cell explicit):

| From\Event | `start(...)` | `stop()` | `cancel()` |
|---|---|---|---|
| `.idle` | `.idle` → (await pipeline.start) → `.recording` | ignored + log | `.idle` (no-op + log) |
| `.recording` | ignored + log | `.recording` → `.finalizing` → (await pipeline.stop) → `.idle` | `.recording` → `.cancelling` → (await pipeline.cancel) → `.idle` |
| `.finalizing` | ignored + log | ignored + log | ignored + log |
| `.cancelling` | ignored + log | ignored + log | ignored + log |

`pipeline.start` is **non-cancellable** from the state machine's perspective: state moves to `.recording` only after `pipeline.start` returns. Calls to `stop()`/`cancel()` while a `start()` is in flight observe `state == .idle` and are ignored as no-ops with a log line. (Risk R5 in §6.)

#### `RecordingPipeline` (protocol)

```swift
public protocol RecordingPipeline: Sendable {
    func start(region: CGRect, scale: ScalePreset, fps: Int,
               outputURL: URL, excludingWindows: [SCWindow]) async throws

    /// Drains in-flight frames, calls GifskiEncoder.finish off-thread,
    /// performs the atomic `.partial → .gif` rename. Returns the final URL.
    func stop() async throws -> URL

    /// Tears down SCStream, drains+discards bridge, calls
    /// GifskiEncoder.cancel which finishes the gifski handle and unlinks `.partial`.
    func cancel() async

    /// Frame drops accumulated during the most recent start..stop window.
    /// Reset on each start().
    var droppedFrames: Int { get }
}
```

#### `ScreenRecordingPipeline` (concrete)

The single production implementation. Owns:

- `captureQueue: DispatchQueue` (label `co.snatch.capture`, `.userInteractive`, serial)
- `encoderQueue: DispatchQueue` (label `co.snatch.encoder`, `.userInitiated`, serial)
- `BridgeQueue<(RGBAFrame, TimeInterval)>` of capacity 60
- `SCStreamWrapper`, `FrameConverter`, `PTSAnchor` (lifted out of the CLI)
- The `GifskiEncoder` for the active recording

`stop()` runs the same fence-and-drain as `Sources/SnatchRecordCLI/main.swift:186-216`: `captureQueue.sync {}` to fence in-flight closures, `encoderQueue.sync` drain loop, `Task.detached` for `gifski_finish` (per spec §5 / M2 carry-over). Then atomic rename via `GifskiEncoder.finish()`.

`cancel()` calls `wrapper.stop()` then `encoder.cancel()` (which itself calls `gifski_finish` and unlinks `.partial`).

Threading model is `@unchecked Sendable` with all mutable state guarded by the encoder/capture queue invariants already documented in `GifskiEncoder` and `BridgeQueue`. No new locking primitives.

#### `RecordingSessionError`

```swift
public enum RecordingSessionError: Error, LocalizedError {
    case pipelineStartFailed(underlying: Error)
    case pipelineStopFailed(underlying: Error)
    // pipelineCancelFailed is intentionally absent — cancel() does not throw.

    public var errorDescription: String? {
        // Returns the underlying error's localizedDescription with a prefix
        // identifying which transition failed, e.g.
        //   "Recording failed during start: <SCStreamWrapperError description>"
    }
}
```

`RecordingSession.start` wraps thrown pipeline errors in `.pipelineStartFailed`. Same for `stop`. AppDelegate prints `errorDescription` on stderr.

### 3.2 Modified

#### `SCStreamWrapper.start(...)` — new `excludingWindows` parameter

```swift
public func start(
    region: CGRect,
    scale: ScalePreset,
    fps: Int,
    queue: DispatchQueue,
    excludingWindows: [SCWindow] = []   // NEW, defaulted for backwards compat
) async throws -> AsyncStream<CMSampleBuffer>
```

`excludingWindows` is threaded into `SCContentFilter(display:excludingWindows:)` at `Sources/SnatchKit/Capture/SCStreamWrapper.swift:88` (currently hardcoded to `[]`). The default `[]` keeps `snatch-record-cli` working unchanged after the call-site refactor (`ScreenRecordingPipeline` will pass through whatever it received from `RecordingSession`).

#### `RegionStore` — `@unchecked Sendable`

`Sources/SnatchKit/System/RegionStore.swift` becomes:

```swift
public final class RegionStore: @unchecked Sendable {
    // UserDefaults is documented as thread-safe (Apple developer documentation:
    // "thread-safe"). All mutations go through `defaults.set/removeObject`.
}
```

Enables `@MainActor RecordingSession.start` and tests on background contexts to interact with the store without Sendable warnings.

### 3.3 Renamed: `Sources/SnatchCropperCLI/` → `Sources/SnatchSessionCLI/`

`Package.swift` updates:
- `.executable(name: "snatch-cropper-cli", ...)` → `.executable(name: "snatch-session-cli", ...)`
- `.executableTarget(name: "SnatchCropperCLI", path: "Sources/SnatchCropperCLI")` → `.executableTarget(name: "SnatchSessionCLI", path: "Sources/SnatchSessionCLI")`
- Source files moved with `git mv` to preserve history.

CLAUDE.md "Status" section updates after M4 ships to reflect the rename and the new run command.

### 3.4 New in `Sources/SnatchSessionCLI/`

```
RecordingOverlayWindow.swift  — borderless NSWindow, transparent body with thin red border stroke,
                                positioned at the recording region. screenSaver level. Hosts Stop button.
RecordingStopButton.swift     — small NSButton-based control (mirrors CropperRecordButton's style).
                                "Stop" label, red tint, similar size/positioning instincts.
Args.swift                    — argv parser (mirrors SnatchRecordCLI's pattern):
                                --output PATH (required, default /tmp/snatch-session.gif)
                                --scale {retina|standard|compact}  (default standard)
                                --fps N  (default 30)
                                Region itself comes from the cropper, not argv —
                                no --region flag here.
```

`main.swift` keeps the existing `NSApplication.shared` boot pattern; `AppDelegate.init` accepts the parsed `Args` so the user-selected scale/fps/output path flow into `session.start(...)` after the cropper resolves the region.

`AppDelegate.swift` rewires:
- `applicationDidFinishLaunching`: instantiate `ScreenRecordingPipeline`, `RegionStore`, `RecordingSession`. Show cropper.
- `cropperRecordRequested(region:)` (was print + exit) becomes:
  1. Resolve `[SCWindow]` for the cropper window + the about-to-be-shown overlay window via `SCShareableContent.current`.
  2. Hide cropper window (`orderOut`).
  3. Instantiate `RecordingOverlayWindow` for the region; show it; wire its `onStop` to a session-driven callback.
  4. `await session.start(region:scale:fps:outputURL:excludingWindows: scWindows)`.
- Stop callback: `await session.stop()` → print SAVED line with URL/drops/latency → terminate.
- Cropper Esc cancel: `await session.cancel()` → print CANCELLED → terminate.

Wraps each `await` in `Task { @MainActor in ... }` with a do/catch that prints the error on stderr and exits non-zero.

### 3.5 Simplified `Sources/SnatchRecordCLI/main.swift`

The inline plumbing at lines 99-216 collapses into:

```swift
let pipeline = ScreenRecordingPipeline()
try await pipeline.start(region: args.region, scale: args.scale, fps: args.fps,
                         outputURL: args.output, excludingWindows: [])
try? await Task.sleep(nanoseconds: UInt64(args.duration * 1_000_000_000))
let stopTriggerAt = CFAbsoluteTimeGetCurrent()
let url = try await pipeline.stop()
let stopLatencyMs = (CFAbsoluteTimeGetCurrent() - stopTriggerAt) * 1_000
print("✅ Wrote \(url.path)")
print("   bridge drops: \(pipeline.droppedFrames)")
print("   stop → save latency: \(String(format: "%.1f", stopLatencyMs)) ms (target < 500 ms)")
```

The `PTSAnchor` class private to the CLI moves into `ScreenRecordingPipeline`. The CLI's `Args` struct stays. Behavior is identical to the M2 form; this is mechanical relocation.

## 4. Data flow

### 4.1 Happy path

```
1. swift run snatch-session-cli --output /tmp/m4.gif
2. AppDelegate boots:
   • ScreenRecordingPipeline + RegionStore + RecordingSession constructed
   • CropperWindow shown (M3 unchanged)
   • Subscribes to session.$state for any future UI driven by it (M4 logs only)

3. User Records
   → AppDelegate resolves [SCWindow] for cropper + overlay
   → cropperWindow.orderOut(nil)
   → RecordingOverlayWindow shown around region (Stop button as only hit-tested subview)
   → await session.start(region, scale, fps, outputURL, excludingWindows: scWindows)
       • RecordingSession: regionStore.persist(region); state .idle → .recording
       • pipeline.start: SCStreamWrapper.start with exclusions, encoder created on
         encoderQueue, bridge drained by encoderQueue, capture pumps frames

4. User clicks Stop
   → overlayWindow.onStop callback in AppDelegate
   → await session.stop()
       • RecordingSession: state .recording → .finalizing; stopAt = clock()
       • url = try await pipeline.stop()  // fence + drain + finish + atomic rename
       • state .finalizing → .idle
       • returns Result(url, droppedFrames, stopLatencyMs)
   → overlayWindow dismissed
   → AppDelegate prints "SAVED <url> (drops=N, stop-latency=Xms)"
   → exit 0
```

### 4.2 Cancel from cropping (M4 in scope)

```
User hits Esc in cropper before Record
→ CropperView.onCancel
→ AppDelegate calls session.cancel() (state == .idle, no-op)
→ AppDelegate prints "CANCELLED" → exit 0
```

### 4.3 Cancel from recording (M4: tested only, not user-triggerable)

```
session.cancel() while .recording
→ state .recording → .cancelling
→ pipeline.cancel():
    SCStreamWrapper.stop() — abandons in-flight frames
    Bridge drained, contents discarded
    GifskiEncoder.cancel() — finishes handle, unlinks .partial
→ state .cancelling → .idle
```

### 4.4 Concurrency

- `RecordingSession` is `@MainActor`. State mutations + `@Published` updates on main.
- `ScreenRecordingPipeline` owns its capture/encoder queues internally; presents an `async` API to its caller.
- `pipeline.stop()`'s `gifski_finish` runs via `Task.detached(priority: .userInitiated)` per spec §5.
- The bridge fence (`captureQueue.sync {}`) and drain (`encoderQueue.sync { ... }`) move from `snatch-record-cli` into `ScreenRecordingPipeline.stop()` unchanged.

### 4.5 Stop-latency measurement

`RecordingSession.stop` records `clock()` immediately on entry, computes the delta after `pipeline.stop()` returns, returns it on `Result.stopLatencyMs`. The `clock` parameter on `RecordingSession.init` is the test seam.

## 5. Error handling

M4 surfaces only the subset of spec §8 errors that flow through `RecordingSession`:

| Failure | Detection | M4 behavior |
|---|---|---|
| Permission denied at start | `SCStreamWrapperError.permissionDenied` from `pipeline.start` | `RecordingSession.start` wraps in `.pipelineStartFailed`, rethrows. AppDelegate prints `"Snatch needs Screen Recording permission. Open System Settings → Privacy & Security → Screen Recording."` to stderr; exit 3. State remains `.idle`. |
| Other start failure | `SCStreamWrapperError.startFailed`, `displayNotFound`, `noDisplaysAvailable`, encoder construction failure | `.pipelineStartFailed` rethrow; AppDelegate prints to stderr; exit 1. State remains `.idle`. |
| Stop failure (encoder error during finish) | `pipeline.stop()` throws | `RecordingSession` finishes its transition through `.finalizing → .idle`, then rethrows wrapped in `.pipelineStopFailed`. AppDelegate prints `"RECORDING FAILED: <reason>"`; exit 1. `.partial` may be left behind (M5's launch-time sweep cleans it). |
| Bridge overflow | drop-oldest inside `BridgeQueue` (M2 behavior, unchanged) | Not surfaced mid-recording; final `droppedFrames` count appears on `Result` and in AppDelegate's SAVED line. |
| Display disconnected mid-recording | SCStream delegate stop event | Not specifically handled in M4; surfaces as a `pipeline.stop` failure if it manifests. Documented as M5 concern. |

**Explicitly deferred to M5** (out of scope for M4):
- Modal dialogs for the permission flow (M4 is a CLI; stderr suffices).
- `CGRequestScreenCaptureAccess` first-prompt dance.
- Notification-based failure surfacing.
- Partial-file sweep on launch.

**Logging:** `Log.coordinator` (already declared in `Sources/SnatchKit/Logging/Log.swift:18`). Each state transition: `.info`. Each error path: `.error`. No new logging categories.

## 6. Risks

- **R1: `SCWindow` resolution latency.** `SCShareableContent.current` is async and can take 50-200 ms. Mitigation: AppDelegate resolves `[SCWindow]` after both windows are realized but before calling `session.start`; not inside `RecordingSession.start` itself. M5 pre-warm replaces this with a cached `SCShareableContent`.

- **R2: NSWindow → SCWindow matching is fragile.** The bridge is `NSWindow.windowNumber` (`Int`) ↔ `SCWindow.windowID` (`CGWindowID` = `UInt32`). Plan task verifies the cast on macOS 14. If a window can't be resolved (race with WindowServer registration), the exclusion list is short and the overlay leaks into the GIF — visible but not catastrophic. Mitigation: log `.error`, retry once after a 50 ms delay before falling back to no-exclusion.

- **R3: Click-through window with a hit-tested button.** The overlay must allow clicks to pass through to the underlying app everywhere except the Stop button. Standard pattern: `NSView.hitTest(_:)` returns `nil` for non-button regions on the overlay's content view. Plan task prototypes this early. Fallback: split into two windows (decoration-only click-through window + button window).

- **R4: Stop button placement at screen edges.** If the recorded region hugs a screen edge, there's no room outside it for the Stop button. Mitigation: button's window is included in the `excludingWindows` list regardless of placement; positioning logic falls back to inside-rectangle (top-right corner) when outside-placement would clip off-screen.

- **R5: Pipeline cancel during start.** If the user clicks Stop or hits Esc while `pipeline.start` is mid-flight, the state machine debounces it: state moves to `.recording` only *after* `pipeline.start` returns, so concurrent `stop()`/`cancel()` calls observe `.idle` and become no-ops. `SCStream.startCapture` typically returns in <100 ms once permission is granted; the unresponsive window is small enough to accept.

- **R6: Sendable shape for the protocol.** `RecordingPipeline` is marked `Sendable`. Concrete `ScreenRecordingPipeline` is `@unchecked Sendable` with the existing per-queue invariants from `GifskiEncoder` / `BridgeQueue`. `FakeRecordingPipeline` is `@unchecked Sendable` with internal lock for cross-task observation. Compile-time conformance is exercised implicitly by the existing test compilation (no explicit `SendableChecks` file needed; if Swift's strict-concurrency checking surfaces a warning during build, that's the signal).

- **R7: Renaming target preserves history.** `git mv Sources/SnatchCropperCLI Sources/SnatchSessionCLI` keeps blame. CLAUDE.md updates after the rename. The `m3-cropper-ui` tag stays valid (frozen) — `swift run snatch-cropper-cli` works historically on that tag.

## 7. Testing strategy

### 7.1 Unit tests (TDD)

| Test file | Coverage |
|---|---|
| `RecordingSessionTests.swift` (new) | Every cell of the §3.1 transition table using a `FakeRecordingPipeline`. ~20 tests: idle→recording on start; ignored start while recording; recording→finalizing→idle on stop; recording→cancelling→idle on cancel; ignored events from terminal states; error rethrow + state restoration on start/stop failure; `Result.droppedFrames` and `stopLatencyMs` surfacing; `regionStore.persist` called on start; `regionStore` not persisted on cancel; debounce of stop/cancel during pipeline.start. |
| `ScreenRecordingPipelineTests.swift` (new) | One pipeline integration test wiring real `SCStreamWrapper` + `FrameConverter` + `BridgeQueue` + `GifskiEncoder` end-to-end. Skipped without screen-recording permission like the existing `SCStreamWrapperLiveTests`. Asserts a GIF lands at the requested URL. Stop-latency assertion < 500 ms. |
| `SCStreamWrapperHelperTests.swift` (extend) | Verify the new `excludingWindows` parameter is threaded through to `SCContentFilter`. Pure-helper test if reachable; otherwise a smoke check inside the live test. |
| `RegionStoreTests.swift` (extend) | Compile-time `Sendable` check via a `static func _check<T: Sendable>(_:)` helper. |

`Tests/SnatchKitTests/Helpers/FakeRecordingPipeline.swift` (new) implements `RecordingPipeline`, exposes `startCalls`, `stopCalls`, `cancelCalls`, configurable `startError`, `stopError`, `stopReturnURL`, `droppedFramesValue`. `@unchecked Sendable` with a single `NSLock` for cross-task observation.

### 7.2 Manual smoke gate (M4 done criteria)

Run by a human at the keyboard before tagging. M4 ships when ALL of the following hold:

1. `swift build` — succeeds, no warnings.
2. `swift test` — full default suite passes; live-capture test still skipped without permission grant.
3. `swift run snatch-session-cli --output /tmp/m4-smoke.gif`:
   - Cropper appears full-screen dim. Drag a region. Resize via handles. Click Record (or Space/Enter).
   - Cropper fades; thin red border appears around the captured region; floating Stop button visible.
   - Move some windows / scrub a video / type something visibly inside the captured region for 3-5 seconds.
   - Click Stop.
   - `SAVED /tmp/m4-smoke.gif (drops=N, stop-latency=Xms)` printed to stdout; binary exits 0.
   - Open the GIF in QuickLook. Animation plays. Cropper dim, handles, Record button, red border, and Stop button are all absent from the recorded frames.
4. `swift run snatch-session-cli` and press Esc on the cropper before recording — `CANCELLED` printed; exit 0; no file written.
5. Region persistence: re-run after step 3 — cropper opens with the previously-recorded rectangle pre-drawn.
6. `swift run snatch-record-cli --duration 2 --output /tmp/regression.gif` — confirms the M2 smoke harness still produces a valid GIF after the `ScreenRecordingPipeline` extraction (no regression).
7. Stop latency: from step 3, verify `stop-latency=Xms` is < 500 ms on M-series hardware.
8. The git tag `m4-coordinator-wiring` exists.
9. `CLAUDE.md` Status section reflects M4 done and the `SnatchCropperCLI → SnatchSessionCLI` rename.

## 8. Carry-overs to M5

These are explicit seams for M5 to close, not bugs:

- **Global hotkey (`⇧⌘6` via Carbon).** No keyboard trigger for record/stop in M4.
- **Carbon Esc hotkey during recording.** Cancel-during-recording is wired in the state machine but not user-triggerable.
- **`NSStatusItem` menubar.** Idle/recording icon states, scale dropdown, Recent Recordings, About, Quit.
- **Notifications + clipboard.** `NotificationPresenter` and `PasteboardWriter` System adapters per spec §5.
- **`PathProvider` for Desktop auto-naming.** M4 uses `--output` flag; M5 defaults to `~/Desktop/snatch-YYYY-MM-DD-HH-mm-ss.gif`.
- **Partial-file sweep on launch.** Spec §8: "On app launch, sweep `~/Desktop/snatch-*.gif.partial` and delete."
- **Pre-warm strategy.** Cropper instantiated hidden at launch; `SCShareableContent` cached; in-memory shadows of stores. The hotkey-to-cropper <100 ms target is M5.
- **Permission flow modals.** M4 prints to stderr; M5 adds the spec §8 modals + `Open System Settings` deep-link.
- **Multi-display reconfigure handling.** M4 doesn't handle displays connecting/disconnecting mid-session.
- **Pipeline backpressure regression test.** The current `snatch-record-cli` 1:1 dispatch shape (capture-side dispatches one encoder-side dequeue per sample) is preserved by the extraction; the cleaner producer/consumer shape noted in the M2 carry-over comment at `Sources/SnatchRecordCLI/main.swift:142-151` is M5 work. Documented but not addressed in M4.
