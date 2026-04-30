# Snatch — Design Spec

**Date**: 2026-04-30
**Status**: Approved (brainstorming complete; pending writing-plans decomposition)

## 1. Overview

Snatch is a fast, simple, native macOS GIF recorder. The user selects a region of their screen, records, and gets a GIF saved to the Desktop with the file already in the system clipboard — ready to ⌘V into Slack, Discord, Notes, Mail, Finder, or anywhere that accepts a file paste.

The reason to build it (rather than use Kap, LICEcap, or Gifski.app) is **speed at both ends of the lifecycle**:

1. **Hotkey → cropper-ready (user can start dragging) in < 100 ms.** Kap takes 1–2 seconds here — partly Electron cold start, partly lazy initialization of capture infrastructure. We mitigate by keeping the menubar app resident, pre-warming the cropper window, and pre-fetching `SCShareableContent` on launch.
2. **Stop trigger → GIF saved + clipboard ready in < 500 ms.** The encoder runs continuously during capture (streaming gifski), so when the user hits stop, the GIF is essentially already written — only a flush remains.

Secondarily: **simplicity**. One Xcode project, no Electron, no FFmpeg pipeline, no plugin system, no settings window in v1, no third-party Swift packages.

## 2. Non-goals (v1)

- Cross-platform support (macOS only; do not introduce Linux/Windows abstractions)
- Video output other than GIF (no MP4, WebM, APNG)
- Audio recording
- Cloud upload, share-sheet integrations, plugin systems
- A general settings/preferences UI (hotkey, save path, fps, quality are all hardcoded; only the scale preset is user-selectable, and that lives in the menubar dropdown)
- Mouse-click highlights, keystroke overlays, screencast-style polish
- A recording duration cap
- Crash recovery into watchable GIFs (orphaned `.partial` files are deleted on relaunch, not rescued)

## 3. Stack

- **Language**: Swift 5.10+
- **UI**: SwiftUI for menubar/menus, AppKit (`NSWindow`) for the cropper overlay (transparent borderless window at screen-saver level)
- **Capture**: ScreenCaptureKit (macOS 14+)
- **Encoder**: [gifski](https://github.com/ImageOptim/gifski) (Rust, statically linked via C FFI)
- **Min OS**: macOS 14 (Sonoma)
- **Build**:
  - One Xcode project — `Snatch.xcodeproj`
  - No third-party SPM dependencies
  - gifski vendored as `vendor/gifski/libgifski.a` (built once via `cargo build --release`; build script in `scripts/build-gifski.sh`)
  - Static lib + C bridging header in target

## 4. UX — locked decisions

| Aspect | Decision |
|---|---|
| Trigger | Global hotkey `⇧⌘6` + menubar icon click |
| Cropper | Drag rectangle → 8 resize handles + live `W × H` label → "Record" button (also Space / Enter) |
| Region memory | Last region persists across launches; pre-drawn on next cropper open |
| Stop | Hotkey toggle OR menubar icon click (whichever the user reaches for) |
| Cancel | Esc — discards file, no notification, no clipboard, no recent-list update |
| Recording feedback | Thin red border around captured region (excluded from capture) + menubar icon turns red. No countdown. |
| Post-stop | Auto-save → copy file URL to clipboard → macOS notification with "Reveal in Finder" |
| Save location | `~/Desktop/snatch-YYYY-MM-DD-HH-mm-ss.gif` (hardcoded) |
| Output | 30 fps fixed; gifski quality = 90 |
| Scale presets | *Retina* (2× physical pixels) · **Standard** (1× logical pixels — default) · *Compact* (0.5× logical) |
| Cursor | Always included in the recording |

## 5. Architecture

### Process model

Single Swift app, `LSUIElement = true` (menubar-only, no Dock icon). One `.app` bundle, no helper apps, no XPC, no external services.

### Layered shape

```
┌──────────────────────────────────────────────────┐
│  UI layer (AppKit + SwiftUI)                     │
│  • Menubar (NSStatusItem + NSMenu)               │
│  • Cropper (NSWindow at screenSaver level)       │
│  • Notifications (UserNotifications.framework)   │
├──────────────────────────────────────────────────┤
│  Coordinator (RecordingSession)                  │
│  state machine: idle → cropping → recording →    │
│                 finalizing → idle                │
├──────────────────────────────────────────────────┤
│  Capture            │   Encoder                  │
│  (ScreenCaptureKit) │   (gifski C-FFI)           │
│  — capture queue —  │   — encoder queue —        │
└──────────────────────────────────────────────────┘
        │                       │
   ┌────┴──────┐         ┌──────┴────────┐
   │ Hotkey    │         │ FileWriter    │
   │ Pasteboard│         │ Notification  │
   └───────────┘         └───────────────┘
       System adapters
```

### Concurrency model

- **Main queue**: UI only.
- **`captureQueue`** (serial, QoS `.userInteractive`): receives `CMSampleBuffer`s from SCStream's delegate; runs format conversion (CVPixelBuffer → tightly packed RGBA bytes).
- **`encoderQueue`** (serial, QoS `.userInitiated`): wraps gifski's blocking `gifski_add_frame_rgba` calls.
- **Bridge** between the two: a bounded queue of capacity 60 frames (2 s at 30 fps). On overflow, the *oldest* frame is dropped and a warning is logged. Frame drops signal that the encoder briefly fell behind on a huge region; they are graceful degradation, not a fatal error.

### Pre-warm strategy (hotkey-to-cropper latency target)

To hit the **< 100 ms hotkey → cropper-ready** target, the hotkey path must allocate, query, or block on nothing. All expensive setup happens on app launch or in the background:

- **`CropperWindow` is instantiated on app launch** (hidden, `orderOut`). Showing the cropper means `orderFrontRegardless` + state reset — no `NSWindow` allocation, no view-tree first-render cost.
- **`SCShareableContent.current` is pre-fetched on app launch** and cached. The cache is refreshed reactively on `NSApplication.didChangeScreenParametersNotification` (display reconfigured) and on `NSWorkspace.didActivateApplicationNotification` if the active app changed (so the exclusion list is current). Refresh runs on a background queue and never blocks the hotkey path.
- **`RegionStore`, `ScalePresetStore`, `RecentRecordingsStore` are eager-loaded on launch** into in-memory shadows. Reads on the hotkey path hit memory only.
- **`PermissionsCoordinator.check()` is cached** — `CGPreflightScreenCaptureAccess()` is fast after the first call, but we still cache the boolean for the process lifetime to avoid the syscall on the hotkey path.
- **NSScreen / display info is queried on launch** and refreshed on screen-parameter changes. The cropper picks the active display from cache.

If any of the above is stale at hotkey time (e.g., user reconnected a monitor between launch and now and the notification hasn't fired yet), the cropper still appears immediately with potentially-stale info; the SCStream start (which happens later, after Record) will use fresh data via a final pre-flight refresh.

The hotkey handler itself does only: state-machine transition `idle → cropping`, set the cropper's pre-drawn region from `RegionStore`, call `cropperWindow.orderFrontRegardless()`, `cropperWindow.makeKey()`. All cheap, all on the main queue.

### Code layout

```
Snatch/
├── App/             # AppDelegate, lifecycle, Info.plist (LSUIElement = YES)
├── Coordinator/     # RecordingSession (state machine)
├── Capture/         # SCStreamWrapper, FrameConverter
├── Encoder/         # GifskiEncoder (C-FFI), gifski-bridging-header.h
├── UI/
│   ├── Menubar/     # MenubarController (NSStatusItem + NSMenu)
│   └── Cropper/     # CropperWindow, CropperView, drag/handle logic
├── System/          # HotkeyRegistrar, PasteboardWriter, NotificationPresenter,
│                    # PathProvider, RegionStore, ScalePresetStore,
│                    # RecentRecordingsStore, PermissionsCoordinator
├── Tests/           # Unit + integration
│   └── Fixtures/    # PNG frames, CMSampleBuffer fixtures, reference GIF
├── vendor/
│   └── gifski/      # libgifski.a + gifski.h
└── scripts/
    └── build-gifski.sh
```

## 6. Components

### Shared types

```swift
struct RGBAFrame {
    let bytes: Data   // tightly packed RGBA8, no row padding
    let width: Int
    let height: Int
}

enum ScalePreset: String, Codable {
    case retina    // 2× physical pixels (full Retina resolution)
    case standard  // 1× logical pixels (default)
    case compact   // 0.5× logical pixels
}
```

Both are plain value types with no behavior. `ScalePreset` is applied at *capture* time via `SCStreamConfiguration.width/height` (hardware-accelerated downscale on the GPU), not at encode time — the encoder receives frames already at output dimensions.

### Coordinator

#### `RecordingSession`

Top-level state machine.

- **States**: `idle`, `cropping`, `recording`, `finalizing`, `cancelling`
- **Public surface**: `start()`, `stop()`, `cancel()`. State exposed as `@Published`.
- **Transitions**:
  - `idle → cropping`: hotkey or menubar click
  - `cropping → idle`: Esc or cropper close
  - `cropping → recording`: user clicks Record (or Space/Enter)
  - `recording → finalizing`: stop hotkey or menubar click
  - `recording → cancelling`: Esc during recording
  - `finalizing → idle`: gifski done, file saved, clipboard set, notification shown
  - `cancelling → idle`: writer torn down, partial file deleted
  - `finalizing` / `cancelling` + any input: ignored (debounce)
- **Depends on**: every component below; constructor-injected.

### Capture layer

#### `SCStreamWrapper`

Wraps `SCStream` lifecycle. Returns frames as `AsyncStream<CMSampleBuffer>`.

```swift
func start(
    region: CGRect,
    scale: ScalePreset,
    queue: DispatchQueue
) async throws -> AsyncStream<CMSampleBuffer>

func stop() async
```

- Uses `SCContentFilter` to exclude **our own overlay windows** (cropper, red-border, menubar) from capture.
- Uses `SCStreamConfiguration.sourceRect` for GPU-side region cropping (no manual cropping in user code).
- `ScalePreset` maps to `SCStreamConfiguration.width/height`: `.retina` = physical pixels (2× logical on Retina displays), `.standard` = logical pixels (1×), `.compact` = 0.5× logical pixels. Downscale is hardware-accelerated on capture.

#### `FrameConverter`

Converts each `CMSampleBuffer` (BGRA `CVPixelBuffer`) into tightly packed RGBA bytes that gifski consumes.

```swift
func convert(_ sample: CMSampleBuffer, outputSize: CGSize) -> RGBAFrame
```

- Uses `Accelerate.vImage` for byte-swap and any required scale-down.
- Allocates from a shared buffer pool — no per-frame allocation churn.

### Encoder layer

#### `GifskiEncoder`

Streaming wrapper over gifski's C API.

```swift
init(outputURL: URL, fps: Int = 30, quality: Int = 90) throws

func addFrame(_ frame: RGBAFrame, presentationTime: TimeInterval) throws
    // BLOCKING — must run on encoderQueue

func finish() async throws    // flushes, writes GIF trailer, fsyncs

func cancel()                 // discards writer, deletes partial output
```

- Output is written to `<finalURL>.partial` and atomically `rename(2)`'d to `<finalURL>` on `finish()`.
- On `cancel()`, the `.partial` is `unlink(2)`'d.

### UI layer

#### `CropperWindow`

Transparent borderless `NSWindow` at `NSWindow.Level.screenSaver` on the active display, `canBecomeKey = true` so it receives keyboard events.

- Initial state: full-screen dim. If `RegionStore.lastRegion` is present, the rectangle is rendered with handles + Record button already visible — user can press Record immediately for a same-region recording, or click-and-drag anywhere on the dim to start a fresh selection (which replaces the pre-drawn rectangle).
- During drag: live rectangle with a `W × H` label rendered at the rectangle's corner.
- On mouse-up: 8 resize handles + dimensions label + a floating "Record" button appear near the rectangle.
- Inputs:
  - `Record` button click / Space / Enter → `onRecordRequested(region: CGRect)`
  - Esc → `onCancelled()`
- Excluded from SCStream capture so the dim, handles, label, and Record button never appear in the recorded GIF.

#### `MenubarController`

Owns the `NSStatusItem`.

- **Icon states**: `idle` (outlined camera-rect glyph), `recording` (filled red dot).
- **Dropdown menu when idle**:
  - *Start Recording* (`⇧⌘6`)
  - *Scale ▸ {Retina · Standard · Compact}* (current marked with ✓)
  - *Recent Recordings ▸* (last 5; click reveals in Finder; missing files filtered out)
  - *About*
  - *Quit*
- **While recording**: clicking the icon stops immediately (no menu shown).
- Subscribes to `RecordingSession.state`.

### System adapters

| Component | Responsibility | Backing API |
|---|---|---|
| `HotkeyRegistrar` | Global ⇧⌘6 toggle | Carbon `RegisterEventHotKey`. Also dynamically registers Esc as a hotkey *only while `.recording`* — Esc is not intercepted system-wide. |
| `PasteboardWriter` | Copy GIF file URL to clipboard for ⌘V | `NSPasteboard.general` — writes `NSPasteboard.PasteboardType.fileURL` |
| `NotificationPresenter` | macOS notification with "Reveal in Finder" action | `UserNotifications` framework. Authorization requested on first save. |
| `PathProvider` | `nextOutputURL() -> URL` → `~/Desktop/snatch-YYYY-MM-DD-HH-mm-ss.gif` | Pure function over `Date()` |
| `RegionStore` | Persist last `CGRect` across launches | `UserDefaults` |
| `ScalePresetStore` | Persist current `ScalePreset` | `UserDefaults` |
| `RecentRecordingsStore` | Track 5 most recent saved files | `UserDefaults`; filters out paths that no longer exist on disk |
| `PermissionsCoordinator` | Check / prompt for Screen Recording permission | `CGPreflightScreenCaptureAccess()` + `CGRequestScreenCaptureAccess()` + System Settings deep-link fallback |

### Boundaries

- **Capture and Encoder do not know about UI.** They take a region/queue/URL and emit frames or write a file. Pure pipeline.
- **`CropperWindow` does not know about Capture.** It emits "user wants to record region X." The Coordinator wires it up.
- **No singletons.** Everything is constructor-injected. Makes unit testing the pipeline trivial with fake delegates and fixture frames.

## 7. Data flow

### State machine (summary)

```
        ┌──────┐
        │ idle │
        └──┬───┘
           │ hotkey / menubar
           ▼
       ┌──────────┐  Esc / ⇧⌘6
       │ cropping │ ─────────────► idle
       └────┬─────┘
            │ Record (or Space/Enter)
            ▼
       ┌──────────┐  Esc
       │recording │ ─────────────► cancelling ─► idle
       └────┬─────┘                  (delete partial)
            │ ⇧⌘6 / menubar click
            ▼
       ┌──────────┐
       │finalizing│ ─────────────► idle
       └──────────┘    (save + clipboard + notification)
```

### Flow 1 — Start (happy path)

```
1. ⇧⌘6 / menubar → HotkeyRegistrar or MenubarController fires
   → RecordingSession.start()                    state: idle → cropping

2. CropperWindow (pre-instantiated on launch) is unhidden:
   • orderFrontRegardless + makeKey on the active display (cached NSScreen)
   • pre-draws RegionStore.lastRegion if present (in-memory cache)
   • becomes key window so Esc lands in its responder chain
   • NO allocation, NO SCShareableContent query, NO disk I/O on this path

3. User drags / adjusts / sees live W×H label

4. Record (or Space/Enter)
   → CropperWindow.onRecordRequested(region)
   → RegionStore.persist(region)                 state: cropping → recording

5. RecordingSession boots pipeline:
   • Final SCShareableContent refresh (background, may have raced ahead of us)
   • PathProvider.nextOutputURL() → ~/Desktop/snatch-…gif
   • GifskiEncoder(outputURL, fps:30, quality:90) on encoderQueue
   • SCStreamWrapper.start(region, scale, captureQueue)
       — excludes our overlay windows
       — SCContentFilter.sourceRect handles GPU-side cropping
   • HotkeyRegistrar dynamically registers Esc as a Carbon hotkey
   • MenubarController.icon → red dot

6. CropperWindow fades out; thin red-border overlay window appears
   around the captured region (also excluded from capture)

7. Frame loop:
   captureQueue:  CMSampleBuffer → FrameConverter.convert → RGBAFrame
                  → enqueue on bridgeQueue (capacity 60)
   encoderQueue:  dequeue → GifskiEncoder.addFrame(frame, ptsTime)
                  → gifski writes to disk continuously
```

### Flow 2 — Stop (normal save)

```
1. ⇧⌘6 OR menubar icon click
   → RecordingSession.stop()                     state: recording → finalizing

2. Teardown:
   • SCStreamWrapper.stop() — await last frame delivery
   • bridgeQueue drains naturally into encoderQueue
   • GifskiEncoder.finish() — flushes, writes GIF trailer, fsyncs,
     atomically renames .partial → .gif
   • Red-border overlay dismissed
   • Carbon Esc hotkey unregistered

3. Post-save (parallel):
   • PasteboardWriter.copy(fileURL)              ← ⌘V works the instant this returns
   • RecentRecordingsStore.add(url, now)
   • NotificationPresenter.present(url)          ← "Saved. Reveal in Finder?"
   • MenubarController.icon → idle

4. state: finalizing → idle

Latency budget (north-star test):
   stop trigger → file closed:        < 200 ms typical
   stop trigger → notification shown: < 500 ms
```

### Flow 3 — Cancel (Esc)

```
While .cropping:
   Cropper window has key focus → keyDown(Esc) → onCancelled
   → RecordingSession.cancel() while .cropping
   → CropperWindow dismisses                     state: cropping → idle
   (no encoder, no capture, no file)

While .recording:
   Carbon Esc hotkey (registered on .recording entry) fires
   → RecordingSession.cancel()                   state: recording → cancelling
   • SCStreamWrapper.stop() — abandon in-flight frames
   • bridgeQueue drained, contents discarded
   • GifskiEncoder.cancel() — closes writer, DELETES .partial file
   • Red-border dismissed
   • Carbon Esc unregistered
   → state: cancelling → idle

   No clipboard. No notification. No recent-list update. Silent unwind.
```

### Flow 4 — Errors

| Failure | Detection | Behavior |
|---|---|---|
| Permission denied | `CGPreflightScreenCaptureAccess()` false on `start()` | Modal: *"Snatch needs Screen Recording permission"* with **Open System Settings** deep-link button. State stays `.idle`. |
| SCStream fails to start | `SCStreamWrapper.start` throws | Abort to `.idle`, re-show cropper with toast: *"Couldn't start capture: <reason>"* |
| Encoder error mid-recording | `GifskiEncoder.addFrame` throws on encoder queue (disk full, FFI failure) | Treated as auto-cancel (Flow 3 path), but with a non-silent notification: *"Recording failed: <reason>"* |
| Bridge overflow | bridgeQueue at capacity | Drop **oldest** frame, log warning, continue. Not surfaced to user during recording. On stop, log final drop count. |
| Display disconnected mid-recording | SCStream delegate emits stop event | Same as encoder error — surface failure notification. |

### Hotkey toggle semantics

- `.idle` + ⇧⌘6 → start (→ `.cropping`)
- `.cropping` + ⇧⌘6 → cancel (same as Esc)
- `.recording` + ⇧⌘6 → stop (normal save)
- `.finalizing` / `.cancelling` + ⇧⌘6 → ignored (debounce)

## 8. Error handling

### Philosophy

- **Graceful degradation over silent failure** — drop frames, not recordings.
- **Visible failures over silent saves** — any error that prevents a save shows a notification with the reason.
- **No automatic retries** — user retries by hitting ⇧⌘6 again.

### First-launch / permission flow

```
Launch:
  PermissionsCoordinator.check()
    → granted: proceed silently
    → never-asked: defer (don't prompt on launch)
    → denied: menubar icon shows a "!" badge

User triggers ⇧⌘6 or menubar click → RecordingSession.start():
  PermissionsCoordinator.check()
    → granted: proceed
    → never-asked:
        CGRequestScreenCaptureAccess()   (system prompt fires once)
        Modal after grant: "Permission granted — please relaunch Snatch."
        [Quit & Relaunch] button.
    → denied:
        Modal: "Snatch needs Screen Recording permission to capture your screen."
        [Open System Settings] [Cancel]
        Deep-link target:
          x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture
```

The "permission granted requires relaunch" wrinkle is real macOS TCC behavior — the deny decision is cached for the lifetime of the process. Handling it cleanly = one extra dialog, not three.

### Crash safety / partial files

- gifski writes to `~/Desktop/snatch-YYYY-MM-DD-HH-mm-ss.gif.partial`.
- On `finish()` success → atomic `rename(.partial → .gif)`.
- On `cancel()` → `unlink` the `.partial`.
- **On app launch**: sweep `~/Desktop/snatch-*.gif.partial` and delete (any leftover means a previous run crashed mid-write). Single-pass, silent, only touches our naming pattern.

### Logging

- Apple's `os.log` (unified logging) with subsystem `co.snatch.app`.
- Categories: `capture`, `encoder`, `coordinator`, `ui`, `system`.
- Levels:
  - `.info` — every state transition; every recording start/stop with region + scale
  - `.debug` — frame drop events; queue depth peaks
  - `.error` — every error with full context
- No remote telemetry. Local logs only — discoverable via `Console.app`.

### Things explicitly not handled in v1

- **No recording duration cap** (YAGNI; revisit if users report runaway recordings).
- **No crash recovery into watchable GIFs** — truncated `.partial` is deleted, not rescued.
- **No display configuration change handling beyond surfacing the error** — disconnect a monitor mid-recording → recording fails with notification, file is cancelled.
- **No conflict detection on the global hotkey** — if ⇧⌘6 is bound elsewhere, registration fails silently with a log line.

## 9. Testing strategy

### Coverage map

| Component | Unit (TDD) | Integration | Manual smoke |
|---|---|---|---|
| `FrameConverter` | ✅ deterministic — fixture pixel buffer → assert exact RGBA bytes | | |
| `GifskiEncoder` | ✅ real FFI calls on fixture frames → decode output → assert frame count, dims, sentinel pixels | ✅ end-to-end pipeline | |
| `RecordingSession` | ✅ inject fakes for Capture/Encoder/stores → assert every transition for every flow | | |
| `PathProvider` | ✅ pure function | | |
| `RegionStore` / `ScalePresetStore` / `RecentRecordingsStore` | ✅ `UserDefaults(suiteName:)` for isolation | | |
| `SCStreamWrapper` | thin shim — minimal | ✅ | ✅ live capture |
| `CropperWindow` | drag math (rect from start/end, handle hit-testing) | | ✅ visual interaction |
| `MenubarController` | menu-item enablement logic | | ✅ click-through |
| `HotkeyRegistrar` | dispatch table | | ✅ system-wide ⇧⌘6 |
| `PermissionsCoordinator` | branch logic w/ mocked authorization state | | ✅ revoke / re-grant flow |
| `PasteboardWriter` / `NotificationPresenter` | minimal | | ✅ ⌘V into Slack; "Reveal in Finder" |

### Manual smoke checklist (run before each release tag)

1. **Cropper**: drag region; resize via handles; observe dimensions label; click Record / press Space / press Enter / press Esc — all behave correctly.
2. **Hotkey**: ⇧⌘6 from idle, while in fullscreen video, while another app is focused — all trigger cropper.
3. **Stop paths**: hotkey-stop, menubar-click-stop, Esc-cancel — each results in correct end state (saved + cleanup vs. discarded).
4. **Permission flow**: revoke Screen Recording in System Settings → relaunch → trigger record → modal flow → grant → relaunch → record succeeds.
5. **Notification**: appears, "Reveal in Finder" opens correct path.
6. **Clipboard**: ⌘V into Slack, Discord, Finder, Notes, Mail — animation preserved (file-URL paste).
7. **Visual quality**: a recording at each scale preset (Retina/Standard/Compact); eyeball check; dimensions match expectation.
8. **Hotkey latency**: time from ⇧⌘6 keypress to first paint of the cropper rectangle. Assert **< 100 ms** on M-series. Measure on first-of-session hotkey (cold-but-resident app) and on repeat hotkey (warm).
9. **Stop latency**: 5-second recording, time `stop trigger → notification`. Assert **< 500 ms** on M-series.
10. **Crash hygiene**: `kill -9 Snatch` mid-recording → relaunch → assert no `*.partial` files remain on Desktop.

### CI

- macOS GitHub runner (or local Xcode).
- `xcodebuild test -scheme Snatch` runs all unit + integration tests.
- SwiftLint for style; swift-format on save.
- Manual smoke gates: **not in CI** — run by a human before each tagged release.

### Fixtures

- `Tests/Fixtures/`:
  - 3–5 PNG frames loaded as RGBA byte arrays for encoder tests
  - One canned `CVPixelBuffer` BGRA-bytes blob for converter tests
  - One pre-decoded reference GIF for end-to-end pipeline assertions
- `vendor/gifski/libgifski.a` checked into the repo (saves a Rust toolchain dependency in CI).
- `scripts/build-gifski.sh` for rebuilds.

### TDD discipline

Every component above marked ✅ for unit testing follows the Superpowers `test-driven-development` skill (RED → GREEN → REFACTOR) per task. Components marked smoke-only are gated by the human checklist; we do not pretend to unit-test them.

## 10. Implementation milestones (high-level)

These are the build phases — to be refined into concrete tasks by the writing-plans skill. The pattern is **inner pipeline first, UI around it last**:

### M1 — Encoder smoke test
gifski FFI bridging works. From a CLI test harness, produce a valid GIF from N RGBA frames in `Tests/Fixtures/`. No capture, no UI. Validates the build setup, vendored `libgifski.a`, bridging header, and the `GifskiEncoder` wrapper.

### M2 — Capture pipeline
`SCStreamWrapper` + `FrameConverter` + bridge queue + `GifskiEncoder` end-to-end. A test runner records a fixed region for a fixed duration and produces a GIF on disk. Still no UI. Validates the streaming-encoder model and the **stop-latency** target.

### M3 — Cropper UI
Transparent `NSWindow` overlay. Drag rectangle, 8 resize handles, dimensions label, Record button, Space/Enter/Esc handling, region persistence. No recording yet — emits "user wants to record region X" to a console.

### M4 — Coordinator wiring
`RecordingSession` state machine integrates Cropper + Capture + Encoder. Click Record → records → click stop → GIF saved. Hotkey not yet hooked up; menubar minimal.

### M5 — Menubar + hotkey + system polish + pre-warm
Full `NSStatusItem` with menu, ⇧⌘6 registration via Carbon, dynamic Esc registration during recording, notification, clipboard, recent-recordings list, partial-file cleanup on launch, full permission flow. **Pre-warm strategy** (§5) wired up: cropper instantiated on launch, `SCShareableContent` pre-fetched + refreshed on display-config change, in-memory shadows of the persistence stores. Measures **hotkey-latency** target.

### M6 — Smoke pass + ship
Run the manual smoke checklist (§9). Measure latency on representative hardware. Fix anything visible. Build a signed `.app` bundle with hardened runtime + screen recording entitlement.

Each milestone ends with the manual smoke gate appropriate to its layer — not gated on automation alone.
