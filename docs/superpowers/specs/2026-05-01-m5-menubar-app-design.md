# M5 — Menubar App + Hotkey + Pre-warm · Design

**Date**: 2026-05-01
**Status**: Approved (brainstorming complete; pending writing-plans decomposition)
**Master spec**: [`2026-04-30-snatch-design.md`](2026-04-30-snatch-design.md) (§5 Pre-warm, §6 Components, §7 Flows 1–4, §8 First-launch / permission flow + partial-file safety, §10 M5 paragraph)
**Predecessor**: [`2026-04-30-m4-coordinator-wiring-design.md`](2026-04-30-m4-coordinator-wiring-design.md) (§8 Carry-overs to M5)

## 1. Goal & scope

After M5, double-clicking `Snatch.app` puts a SF-Symbols camera icon in the menubar with no Dock presence. The app is silent until either (a) the user presses ⇧⌘6 from any context — even a fullscreen video, even another app — and within ~100 ms the cropper appears on the screen the cursor is on, with the last region pre-drawn; or (b) the user clicks the menubar icon and gets the dropdown menu (Start Recording, Scale ▸, Recent Recordings ▸, About, Quit).

After Record → record → stop, the GIF lands at `~/Desktop/snatch-YYYY-MM-DD-HH-mm-ss.gif`, the file URL is on the clipboard ready for ⌘V into Slack/Discord/Finder, and a macOS notification appears with "Reveal in Finder." During recording, the icon is a red filled dot, the captured region has a thin red border around it (with a floating Stop button — same as M4), and ⇧⌘6 stops normally while a freshly-registered Carbon Esc hotkey cancels (delete `.partial`, no clipboard, no notification).

If Screen Recording permission has never been asked, the first Record triggers the system prompt + a "Permission granted — please relaunch" `NSAlert`. If denied, ⇧⌘6 surfaces an `NSAlert` with "Open System Settings" deep-linking to `Privacy_ScreenCapture`. The menubar icon shows a red `exclamationmark.triangle.fill` whenever permission is denied.

On launch, before the icon appears in the menubar: synchronously sweep `~/Desktop/snatch-*.gif.partial` orphans, then kick off pre-warm (cropper instantiated hidden, `SCShareableContent` pre-fetched + cached, persistence stores eager-loaded into memory shadows).

**Done gate**: `Snatch.app` is dev-signed with hardened runtime + screen-recording entitlement, built from `Snatch.xcodeproj` (which depends on the existing `Package.swift` as a local Swift package). All M5 smoke checks pass on the developer's M-series Mac. Hotkey-to-cropper measured < 100 ms. Stop-latency stays < 500 ms after the backpressure refactor.

**Out of scope** (deferred to M6): Developer ID Application signing, notarization, ticket stapling, GitHub release, install instructions.

## 2. Locked decisions (from brainstorming)

These eight design questions were settled before the doc was written:

1. **Milestone shape: M5 = "menubar app + hotkey + pre-warm"; M6 = "smoke + ship".** Spec §10's M5/M6 split holds. Splitting M5 further (e.g., M5a menubar+hotkey, M5b polish) was rejected because the Xcode project, hotkey, and menubar are tightly coupled (all need the `.app` bundle and `LSUIElement = YES`); splitting just doubles the smoke gates. Pre-warm is cross-cutting and lives wherever its components live.

2. **Multi-display: cropper appears on the mouse-cursor screen at hotkey time** (`NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }`, falling back to `NSScreen.main`). Convention used by Cmd-Shift-4, Kap, CleanShot, Snagit. Cross-display selection is not v1.

3. **Partial-file sweep: synchronous at launch, before pre-warm.** Sub-10ms operation; sync makes the post-launch invariant trivial ("by the time the icon appears, no orphans exist").

4. **Xcode project structure: mixed.** `Package.swift` stays for `SnatchKit` + the three CLIs. `Snatch.xcodeproj` is added with one App target that depends on `Package.swift` as a local Swift package via Xcode's "Local Swift Package" mechanism. CLIs remain as SPM dev tools.

5. **Menubar icon: SF Symbols template.** `camera.viewfinder` (idle), `record.circle.fill` red palette (recording), `exclamationmark.triangle.fill` red (permission denied). No custom assets in v1.

6. **Permission modal: `NSAlert.runModal()`.** App-modal alerts; `NSApp.activate(ignoringOtherApps: true)` immediately before each `runModal()` so they aren't buried (LSUIElement requirement).

7. **Backpressure refactor: bundled into M5, lands first.** The producer/consumer rewrite of `ScreenRecordingPipeline` is the first M5 task; everything else builds on the cleaner shape. `RecordingSession`'s public API doesn't change.

8. **M5 done = development-signed `.app` that runs on the developer's machine.** Distribution-signed (Developer ID) + notarized + GitHub release is M6.

## 3. Components

Components grouped into six lanes (the pre-warm umbrella in Lane E expands to two sub-components). Order matters — Lane A lands first; Lanes B–F can largely proceed in parallel afterwards.

### Lane A — Backpressure refactor (lands first)

**`ScreenRecordingPipeline` rework.** Replace the 1:1 capture-dispatches-encoder dispatch (`Coordinator/ScreenRecordingPipeline.swift:71-95`) with a real producer/consumer: capture queue enqueues into `BridgeQueue`, an independent encoder-side drain loop dequeues. Resolves the existing `CMSampleBuffer` Sendable warning by consuming `CMSampleBuffer` only inside the producer Task. `RecordingSession`'s public API doesn't change. See §6 for the full refactor design.

### Lane B — Persistence stores

Eager-loaded on launch into memory shadows so hotkey-path reads hit memory only.

- **`ScalePresetStore`** — UserDefaults key `co.snatch.scale-preset`, default `.standard`. Same shape as `RegionStore`. `@unchecked Sendable`.

- **`RecentRecordingsStore`** — UserDefaults key `co.snatch.recent-recordings`, capped at 5. Persists `[(URL, Date)]` as `[[String: String]]` (URL.path + ISO8601). `recents()` filters out entries whose file no longer exists *at read time* (no eager FS scan; the menu rebuild filters on each open). `add(url:)` prepends and trims to 5.

- **`PathProvider`** — pure function `nextOutputURL(now: Date = Date()) -> URL` returning `~/Desktop/snatch-YYYY-MM-DD-HH-mm-ss.gif`. Format string `"yyyy-MM-dd-HH-mm-ss"`, `Locale(identifier: "en_US_POSIX")`, `TimeZone.current`. No collision check — second-precision is enough for human-driven recording cadence.

### Lane C — System adapters

- **`HotkeyRegistrar`** — Carbon `RegisterEventHotKey` for ⇧⌘6 (id 1) on app launch; dynamically registers Esc (id 2) on `RecordingSession.state == .recording` entry, unregisters on exit. Carbon over `NSEvent.addGlobalMonitorForEvents` because global monitors fire AFTER the focused app sees the keypress; Carbon hotkeys are pre-routed.

- **`PasteboardWriter`** — `NSPasteboard.general.clearContents() + writeObjects([url as NSURL])`. URL must be a `file://` URL for paste-as-file behavior. Single function: `copy(fileURL: URL)`.

- **`NotificationPresenter`** — `UNUserNotificationCenter.current()`. On first call: `requestAuthorization([.alert, .sound])` and cache the result. `present(savedURL:)` builds a `UNMutableNotificationContent` with title "GIF saved," body filename, action `revealInFinder` (id `co.snatch.notification.reveal`). Action handler calls `NSWorkspace.shared.activateFileViewerSelecting([url])`. If user denied notifications, the save still succeeds — notification is best-effort. New for M5: `presentFailure(_ message: String)` for the failure paths from §10.

- **`PermissionsCoordinator`** — wraps `CGPreflightScreenCaptureAccess` + `CGRequestScreenCaptureAccess`. Three states: `granted`, `denied`, `notDetermined`. Caches the granted result for process lifetime. Full state machine and modals in §7.

### Lane D — Menubar UI

- **`MenubarController`** — owns `NSStatusItem(variableLength)`. Three icon states driven by `RecordingSession.state` + `PermissionsCoordinator.state`: idle → `camera.viewfinder` (template), recording → `record.circle.fill` (red palette), permissionDenied → `exclamationmark.triangle.fill` (red). Dropdown items in order: Start Recording (⇧⌘6), Scale ▸ {Retina · Standard · Compact} (current marked ✓), Recent Recordings ▸ (rebuilt on `menuWillOpen`, last 5 filtered for existence, click → `NSWorkspace.activateFileViewerSelecting`), About (`NSApp.orderFrontStandardAboutPanel`), Quit (`NSApp.terminate`). While recording: icon-click stops immediately, no menu shown — implemented by intercepting `mouseDown` on `statusItem.button` and routing based on state.

### Lane E — Pre-warm + lifecycle

- **`PartialFileSweeper`** — sync at start of `applicationDidFinishLaunching`. Globs `~/Desktop/snatch-*.gif.partial` via `FileManager.default.contentsOfDirectory(at:..., includingPropertiesForKeys: nil)`, regex-matches the timestamped pattern, `unlink`s. Logs each removal at `.info`. Errors are best-effort.

- **`ShareableContentCache`** — fetches `SCShareableContent.current` on launch (background `Task`); stores `[SCDisplay]` and our own overlay `SCWindow`s. Refresh triggered on `NSApplication.didChangeScreenParametersNotification` and `NSWorkspace.didActivateApplicationNotification` (latter only if the active app changed). Reads on hotkey path return cached value immediately; if cache is empty (first hotkey beats first fetch), the cropper shows with our own overlays unexcluded — they get excluded on the final pre-flight refresh just before `SCStream.startCapture`.

- **Cropper pre-warm** — `CropperWindow` is constructed in `applicationDidFinishLaunching` (after pre-warm tasks kick off), kept hidden via `orderOut`. Showing means setting frame to the active screen, restoring `RegionStore.lastRegion`, calling `orderFrontRegardless` + `makeKey`. No `NSWindow` allocation, no view-tree first-render cost, on the hotkey path. `RecordingOverlayWindow` follows the same pattern (instantiated once, reused per recording).

### Lane F — Build + ship

- **`Snatch.xcodeproj`** — single `App` target, bundle id `co.snatch.app`. `Info.plist` keys: `LSUIElement = YES`, `NSScreenCaptureUsageDescription`. Entitlement file `Snatch.entitlements`: `com.apple.security.device.screen-capture = true`, app-sandbox off. Hardened runtime ON. Code-signing: "Apple Development" identity (whatever the developer has configured locally). Full structure in §6.

### Small cleanups folded in

- Delete `ArgsError` from `Sources/SnatchSessionCLI/Args.swift` (dead code, never thrown).
- `snatch-session-cli` stays as a dev tool. `--output` flag retained for explicit override; *default* changes to `PathProvider.nextOutputURL()` so the CLI matches the app's behavior.
- `snatch-record-cli` stays as a headless region-driven dev tool, unchanged.

## 4. App lifecycle + pre-warm

The whole point of pre-warm is that **the hotkey path allocates nothing, queries nothing, and blocks on nothing**. Everything expensive happens at launch or in the background.

### Launch sequence

```
applicationWillFinishLaunching:
   1. Read CFBundle info, set up os.log subsystems

applicationDidFinishLaunching:
   2. SYNC: PartialFileSweeper.sweep()
        — globs ~/Desktop/snatch-*.gif.partial, unlinks each
        — typical: 0–3 files, < 10 ms total
        — must complete before any new recording can start

   3. SYNC: Construct AppDelegate's component graph (cheap, no I/O):
        let regionStore         = RegionStore()
        let scaleStore          = ScalePresetStore()
        let recentsStore        = RecentRecordingsStore()
        let permissions         = PermissionsCoordinator()
        let permissionsState    = permissions.preflight()
        let pasteboard          = PasteboardWriter()
        let notifier            = NotificationPresenter()
        let pathProvider        = PathProvider()
        let pipeline            = ScreenRecordingPipeline()
        let session             = RecordingSession(pipeline:, regionStore:)
        let cropperWindow       = CropperWindow(...)        // hidden
        let recordingOverlay    = RecordingOverlayWindow(...) // hidden
        let menubar             = MenubarController(session:, scaleStore:, recentsStore:, permissions:)
        let hotkeys             = HotkeyRegistrar(session:)
        let shareableContent    = ShareableContentCache()

   4. SYNC: hotkeys.registerGlobal()                       ⇧⌘6 live

   5. SYNC: menubar.show()                                  NSStatusItem visible

   6. ASYNC (Task.detached): shareableContent.refresh()    50-200 ms

   7. ASYNC: notifier.requestAuthorizationIfNeeded()        may show OS prompt

   8. Subscribe to OS notifications:
        NSApplication.didChangeScreenParametersNotification → shareableContent.refresh()
        NSWorkspace.didActivateApplicationNotification     → shareableContent.refresh()
        NSApplication.didBecomeActiveNotification          → permissions.preflight()
        UNUserNotificationCenter delegate installed
```

### Hotkey path (idle → cropping)

```
HotkeyRegistrar Carbon callback:
   on main queue:
     guard session.state == .idle else { dispatch by state — see §5 }
     guard permissions.cachedState != .denied else {
         showPermissionDeniedAlert()         // §7
         return
     }
     if permissions.cachedState == .notDetermined {
         Task { await permissions.request() … }  // §7 flow
         return
     }
     session.beginCropping()                  // .idle → .cropping
```

`MenubarCoordinator` observes `session.$state`; on `.cropping` entry:

```
     screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
              ?? NSScreen.main!
     cropperWindow.setFrame(screen.frame, display: false)
     cropperWindow.preDrawRegion(regionStore.last)
     cropperWindow.orderFrontRegardless()
     cropperWindow.makeKey()
```

Nothing on this path touches disk, allocates an `NSWindow`, or talks to ScreenCaptureKit. Target: **< 100 ms keypress → first paint** on M-series.

### Cache staleness handling

`ShareableContentCache` *can* be stale at hotkey time:
- User reconnected a monitor between launch and hotkey, and `didChangeScreenParametersNotification` hasn't fired yet.
- A new app launched and we haven't yet refreshed the active-app list.

The cache is **only** used as the source of `excludingWindows` for `SCStream.startCapture`. Final correctness is enforced by a **pre-flight refresh** inside `MenubarCoordinator.recordRequested` — `await shareableContent.refresh()` immediately before `session.start`, blocking that path (not the hotkey path) by at most 50–200 ms. If even that refresh fails, capture proceeds with stale-or-empty exclusions; our overlays may appear in 1–2 frames before the cropper hides.

### Quit cleanup

`applicationWillTerminate`:
- `hotkeys.unregisterAll()` (Carbon hotkeys leak otherwise, though process exit cleans them eventually)
- `session.cancel()` if recording (deletes any `.partial`)
- Persistence stores have already written on each mutation; nothing to flush

## 5. Hotkey + state-machine integration

M4 left `RecordingSession` at 4 states (`.idle`, `.recording`, `.finalizing`, `.cancelling`) with cropping represented as AppDelegate's UI mode while session was `.idle`. M5 has a new actor — `HotkeyRegistrar` — which fires from any context (background app focused, menubar dropdown closed) and needs to know whether we're already cropping to decide how to dispatch. M5 promotes cropping to a session state.

### State machine extension

```swift
public enum State: Equatable {
    case idle
    case cropping     // NEW
    case recording
    case finalizing
    case cancelling
}

public func beginCropping()        // .idle → .cropping
public func cancelCropping() async // .cropping → .idle (no pipeline involved)
```

Existing `start(region:scale:fps:outputURL:excludingWindows:)` becomes callable from **both** `.idle` and `.cropping`. snatch-record-cli (no cropper) continues calling it from `.idle`. The menubar app calls it from `.cropping`.

Updated transition table:

| From\Event | `beginCropping()` | `start(region:...)` | `cancelCropping()` | `stop()` | `cancel()` |
|---|---|---|---|---|---|
| `.idle` | `.idle → .cropping` | `.idle → .recording` *(snatch-record-cli)* | ignored | ignored | `.idle` no-op |
| `.cropping` | ignored | `.cropping → .recording` *(menubar)* | `.cropping → .idle` | ignored | `.cropping → .idle` *(alias)* |
| `.recording` | ignored | ignored | ignored | `.recording → .finalizing → .idle` | `.recording → .cancelling → .idle` |
| `.finalizing` / `.cancelling` | ignored | ignored | ignored | ignored | ignored |

`cancelCropping()` is a no-op from any state other than `.cropping`. `cancel()` from `.cropping` routes to `cancelCropping()` for symmetry.

This is purely additive; M4's tests still pass. New tests cover the four new cells.

### Cropper window ownership

`CropperWindow` does not know about `RecordingSession`. Wiring lives in `MenubarCoordinator`:

```swift
session.$state
    .receive(on: RunLoop.main)
    .sink { [weak self] state in
        guard let self else { return }
        switch state {
        case .cropping:    self.cropperWindow.show(region: regionStore.last,
                                                    onScreen: activeScreen())
        case .recording:   self.cropperWindow.hide(); self.recordingOverlay.show(region: lastRegion)
        case .finalizing, .cancelling:  self.recordingOverlay.hide()
        case .idle:        self.cropperWindow.hide(); self.recordingOverlay.hide()
        }
    }
```

`CropperWindow.onRecordRequested(region:)` → `MenubarCoordinator.recordRequested(region:)` → pre-flight cache refresh → `session.start(region:, scale: scaleStore.current, fps: 30, outputURL: pathProvider.nextOutputURL(), excludingWindows: shareableContent.excludingWindows())`.

`CropperWindow.onCancelled` → `Task { await session.cancelCropping() }`.

### Hotkey routing

```swift
hotkeys.onHotkey = { [weak self] in
    guard let self else { return }
    guard self.permissions.cachedState != .denied else { self.showDeniedAlert(); return }
    if self.permissions.cachedState == .notDetermined {
        Task { await self.handlePermissionRequest() }
        return
    }
    Task { @MainActor in
        switch self.session.state {
        case .idle:                         self.session.beginCropping()
        case .cropping:                     await self.session.cancelCropping()
        case .recording:                    try? await self.session.stop()
        case .finalizing, .cancelling:      break   // debounce
        }
    }
}
```

Esc behavior is split:
- **Inside cropper** (window has key focus): handled by `CropperView.keyDown(with:)` → `onCancelled` → `session.cancelCropping()`. No global hotkey.
- **During recording** (cropper hidden, no app has key focus): Carbon Esc hotkey registered on `.recording` entry, unregistered on `.recording` exit. Fires → `session.cancel()`.

### MenubarController hotkey wiring

Menubar dropdown's "Start Recording" item targets the same dispatch as the hotkey. While `state == .recording`, intercept `mouseDown` on `statusItem.button` to call `session.stop()` directly without showing the menu.

## 6. Backpressure refactor

### Current shape

For each captured `CMSampleBuffer`, the consume `Task` dispatches a `captureQueue.async` closure that converts to `RGBAFrame`, enqueues into `BridgeQueue`, then dispatches a *one-shot* `encoderQueue.async` closure that calls `bridge.dequeue` once and runs `addFrame`. Per-sample, that's two queue hops and a 1:1 capture-encoder coupling masquerading as a producer/consumer.

Two problems:

1. **Backpressure works, but accidentally.** When the encoder falls behind, encoder dispatches stack up on `encoderQueue`; capture continues filling `BridgeQueue`. The 60-frame cap *does* drop oldest when full, but only because of the queue-of-dispatches coincidence, not because anyone designed it.
2. **`CMSampleBuffer` Sendable warning.** `Sources/SnatchKit/Coordinator/ScreenRecordingPipeline.swift:73` captures `sample` (a `CMSampleBuffer`) into a `captureQueue.async` closure. `CMSampleBuffer` isn't formally `Sendable`. Strict concurrency emits a warning.

### Target shape

Two independent loops sharing a real bounded queue:

```
Producer (consume Task):  SCStream → converter → bridge.enqueue(RGBAFrame, pts)
                                                  ↓
                          BridgeQueue<(RGBAFrame, TimeInterval)> (cap 60, drop-oldest)
                                                  ↓
Consumer (encoderQueue):  bridge.dequeueBlocking → encoder.addFrame loop
```

**`BridgeQueue` gains a blocking primitive.** Add `dequeueBlocking() -> T?` that blocks until an item is available or `close()` is called; returns nil only when `close()` has been called and the queue has drained. Implementation: `NSLock` + `DispatchSemaphore`, signal on every enqueue and on close. Plus `drainAndDiscard()` for the cancel path (clears items without delivering).

**Producer Task** (replaces the `for await` + `captureQueue.async` nesting):

```swift
let consumeTask = Task {
    for await sample in stream {
        guard let frame = converter.convert(sample) else { continue }
        let pts = sample.presentationTimeStamp.seconds
        let base = ptsAnchor.anchor(pts)
        bridge.enqueue((frame, pts - base))
    }
}
```

The `CMSampleBuffer` is consumed only inside this `Task` body; nothing crosses an actor or queue boundary with `sample` in tow. Sendable warning gone, no `@unchecked` suppression needed.

**Consumer loop** runs on `encoderQueue` (preserves `GifskiEncoder`'s "single serial queue" contract):

```swift
let consumerHandle = Task.detached(priority: .userInitiated) {
    encoderQueue.sync {
        while let (frame, pts) = bridge.dequeueBlocking() {
            do { try encoder.addFrame(frame, presentationTime: pts) }
            catch { Log.encoder.error("addFrame: \(...)") }
        }
    }
}
```

The drain block exits when `bridge.close()` is called and the queue is empty.

### Stop / cancel rewiring

```swift
public func stop() async throws -> URL {
    await s.wrapper.stop()              // capture stream ends
    await s.consumeTask.value           // producer Task drains naturally
    s.bridge.close()                    // wakes the consumer loop after final drain
    await s.consumerHandle.value        // block until consumer loop exits
    let finishTask = Task.detached(priority: .userInitiated) { [encoder] in
        try await encoder.finish()
    }
    try await finishTask.value
    return s.outputURL
}
```

`cancel()`: same wrapper.stop, then `bridge.drainAndDiscard()` (clears items without delivering), then `bridge.close()`, then await consumer exit, then `encoder.cancel()` on detached task.

### What changes externally

**Nothing.** `RecordingPipeline` protocol is unchanged. `RecordingSession` is unchanged. `snatch-record-cli` is unchanged. M4's tests still pass.

### What changes internally

| File | Change |
|---|---|
| `Sources/SnatchKit/Bridge/BridgeQueue.swift` | Add `dequeueBlocking()`, `close()`, `drainAndDiscard()`. ~30 lines + tests. |
| `Sources/SnatchKit/Coordinator/ScreenRecordingPipeline.swift` | Rewrite `start`/`stop`/`cancel` per above. Net change: -20/+30 lines. Keep `PTSAnchor` private class as-is. |
| `Tests/SnatchKitTests/BridgeQueueTests.swift` | New tests: dequeueBlocking happy path, dequeueBlocking + close interleaving, drainAndDiscard. |

`@unchecked Sendable` stays on `ScreenRecordingPipeline` (it owns `active: ActiveSession?` mutated under start/stop windowing). The CMSampleBuffer warning resolution drops one source of noise; other `@unchecked` annotations are intentional.

## 7. Xcode project transition

### Repo layout after M5

```
snatch/
├── Snatch.xcodeproj/                  ← NEW
├── App/                               ← NEW (Xcode App target sources)
│   ├── SnatchApp.swift                  - @main entry, instantiates AppDelegate
│   ├── AppDelegate.swift                - menubar app lifecycle
│   ├── MenubarCoordinator.swift         - the session.$state observer from §5
│   ├── Info.plist                       - LSUIElement, NSScreenCaptureUsageDescription
│   ├── Snatch.entitlements              - hardened runtime entitlements
│   ├── Assets.xcassets/                 - AppIcon (Dock-stub icon for the bundle)
│   └── UI/
│       ├── Cropper/                     - moved from Sources/SnatchSessionCLI/
│       ├── Menubar/                     - MenubarController, MenubarMenu builders
│       ├── RecordingOverlay/            - moved from Sources/SnatchSessionCLI/
│       └── Permission/                  - PermissionAlertPresenter (NSAlert wrapper)
├── Package.swift                       (unchanged — still defines SnatchKit + 3 CLIs)
├── Sources/
│   ├── SnatchKit/                      (unchanged + small additions for Lanes B/C/E)
│   ├── SnatchCLI/                      (M1 encoder smoke — unchanged)
│   ├── SnatchRecordCLI/                (M2 region-driven smoke — unchanged)
│   └── SnatchSessionCLI/               (M3+M4 cropper-driven smoke — keeps minimal AppDelegate + Args)
├── Tests/SnatchKitTests/               (unchanged + new tests for M5 components)
├── vendor/                             (unchanged)
├── scripts/                            (unchanged)
└── docs/                               (unchanged)
```

### App target dependencies

`Snatch.xcodeproj` has one target: **`App`** (deliverable: `Snatch.app`).

- Type: macOS App
- Bundle id: `co.snatch.app`
- Deployment target: macOS 14.0
- Sources: just `App/**/*.swift`
- Package products: `SnatchKit` from the local package at the repo root
- System frameworks: `AppKit`, `SwiftUI`, `Carbon` (HotkeyRegistrar), `ScreenCaptureKit` (transitive via SnatchKit), `UserNotifications`

The "Local Swift Package" reference is added via Xcode's *File → Add Package Dependencies → Add Local…*, pointing at the repo root. Xcode generates an `XCLocalSwiftPackageReference` entry in `project.pbxproj`. When SnatchKit grows new files in `Package.swift`, the App target picks them up automatically.

### `Info.plist`

```xml
<key>LSUIElement</key>                  <true/>
<key>LSApplicationCategoryType</key>    <string>public.app-category.utilities</string>
<key>CFBundleName</key>                 <string>Snatch</string>
<key>CFBundleDisplayName</key>          <string>Snatch</string>
<key>CFBundleIdentifier</key>           <string>co.snatch.app</string>
<key>NSScreenCaptureUsageDescription</key>
    <string>Snatch records GIFs of the screen regions you select.</string>
<key>NSHumanReadableCopyright</key>     <string>© 2026 Snatch</string>
<key>NSPrincipalClass</key>             <string>NSApplication</string>
```

`LSUIElement = true` is the load-bearing key — no Dock icon, no app-switcher entry. `NSScreenCaptureUsageDescription` is the *purpose string* shown by macOS in the screen-recording permission prompt.

No `NSAppleEventsUsageDescription`, no `NSAppleScriptEnabled` — Snatch doesn't script other apps. Keeping the entitlement surface minimal makes notarization straightforward in M6.

### `Snatch.entitlements`

```xml
<key>com.apple.security.app-sandbox</key>           <false/>
<key>com.apple.security.device.screen-capture</key> <true/>
```

App sandbox **off**. Sandbox isn't needed for non-MAS distribution, and it would force temporary file-write exceptions for `~/Desktop/snatch-*.gif`. Standard choice for direct-distribution menubar utilities.

Hardened runtime: ON (Xcode default, required for notarization in M6).

### Signing

- Code Signing Identity: `Apple Development`.
- Code Signing Style: Automatic.
- Development Team: the user's team ID. Stored in `project.pbxproj`.

In M5 the goal is "runs on developer's Mac with stable TCC permission grant across rebuilds." Apple Development signing is sufficient for that — TCC keys on (signing identity, bundle id), and Apple Development certs are stable across an `xcodebuild build` cycle.

CI compatibility (rebuilding on a GitHub macOS runner) is M6's concern.

### What stays in Package.swift

- `SnatchKit` library target.
- `SnatchCLI`, `SnatchRecordCLI`, `SnatchSessionCLI` executables (dev tools — work without signing or screen-recording bundle permission, since SPM binaries get permission granted to the binary path, not a bundle).
- `SnatchKitTests` — runnable via both `swift test` and `xcodebuild test`.

The CLIs won't have menubar UI / hotkey / pre-warm. `snatch-session-cli` keeps its minimal AppDelegate and uses `--output` flag for explicit override; default switches to `PathProvider.nextOutputURL()`.

### Migration mechanics

The M4 `Sources/SnatchSessionCLI/` AppKit shell (`AppDelegate.swift`, `CropperWindow.swift`, `CropperView.swift`, `CropperRecordButton.swift`, `RecordingOverlayWindow.swift`, `RecordingStopButton.swift`) gets `git mv`'d to `App/UI/Cropper/`, `App/UI/RecordingOverlay/` — preserves blame.

The CLI itself gets a *new* minimal AppDelegate (just enough to drive the cropper + record-stop without menubar/hotkey/permission/pre-warm), so `snatch-session-cli` continues to work as a smoke harness.

Xcode project file is generated by hand in Xcode; the resulting `pbxproj` is checked in as-is (no `xcodegen.yml`).

## 8. Permission flow

Three TCC states for screen-recording permission, exposed via `PermissionsCoordinator`:

```swift
public enum PermissionState {
    case granted          // CGPreflightScreenCaptureAccess() returned true
    case denied           // returned false AND CGRequestScreenCaptureAccess() returned false
    case notDetermined    // returned false but request hasn't been made this process
}
```

Detecting `denied` vs `notDetermined` from preflight alone isn't possible — both look the same. Resolution: `notDetermined` is the initial state of a fresh `PermissionsCoordinator`; once `request()` is called and the user responds, the state collapses to `granted` or `denied` for the rest of the process lifetime. Matches macOS TCC semantics (deny is cached for process lifetime).

### State machine

```
                   process start
                        │
                        ▼
              ┌─────────────────┐
              │  preflight()    │
              └────┬───────┬────┘
                   │       │
              true │       │ false
                   ▼       ▼
              .granted  .notDetermined
                              │
                              │ user triggers a recording
                              ▼
                       request()
                       (system prompt fires once)
                          │           │
                       grant        deny
                          │           │
                          ▼           ▼
                .granted (relaunch  .denied (cached
                 required modal)     for process)
```

### Launch-time check

```swift
applicationDidFinishLaunching:
    permissionsState = permissions.preflight()
    // .granted   → silent, menubar icon = camera.viewfinder
    // .denied    → menubar icon = exclamationmark.triangle.fill (red)
    // .notDetermined → silent (don't prompt at launch); icon = camera.viewfinder
```

We do NOT prompt at launch. The system prompt fires only when the user attempts a recording — that's when the *purpose* is clear.

### Hotkey-time / record-time gate

```swift
HotkeyRegistrar.onHotkey:
    switch permissions.cachedState {
    case .granted:
        // proceed normally — session.beginCropping()
    case .denied:
        showDeniedAlert()
        return
    case .notDetermined:
        Task { @MainActor in
            let result = await permissions.request()
            switch result {
            case .granted:    showRelaunchAlert()
            case .denied:     showDeniedAlert()
            case .notDetermined:
                // user dismissed the system prompt — treat as deny
                showDeniedAlert()
            }
        }
        return
    }
```

### Modal: denied state

```swift
let alert = NSAlert()
alert.messageText = "Screen Recording permission required"
alert.informativeText = """
Snatch needs permission to capture your screen to make GIFs.

You can grant this in System Settings → Privacy & Security → Screen Recording.
"""
alert.addButton(withTitle: "Open System Settings")  // default
alert.addButton(withTitle: "Cancel")
alert.alertStyle = .warning
NSApp.activate(ignoringOtherApps: true)            // foreground the alert (LSUIElement)
let response = alert.runModal()
if response == .alertFirstButtonReturn {
    NSWorkspace.shared.open(URL(string:
        "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
}
```

`NSApp.activate(ignoringOtherApps:)` is critical — without it, an `LSUIElement` app's modal can appear behind the previously-focused app and the user thinks the hotkey did nothing.

### Modal: granted state, relaunch required

After `request()` returns `.granted`, the *process* still has a stale TCC cache for the rest of its lifetime. Apple's documented workaround is relaunch.

```swift
let alert = NSAlert()
alert.messageText = "Permission granted"
alert.informativeText = """
Snatch needs to relaunch once to start recording. Click the button below to quit and reopen.
"""
alert.addButton(withTitle: "Quit & Relaunch")  // default
alert.addButton(withTitle: "Quit")
alert.alertStyle = .informational
NSApp.activate(ignoringOtherApps: true)
let response = alert.runModal()
if response == .alertFirstButtonReturn {
    let bundleURL = Bundle.main.bundleURL
    let config = NSWorkspace.OpenConfiguration()
    config.createsNewApplicationInstance = false
    Task {
        do {
            try await NSWorkspace.shared.openApplication(at: bundleURL, configuration: config)
        } catch {
            Log.system.error("relaunch failed: \(...)")
        }
        await MainActor.run { NSApp.terminate(nil) }
    }
} else {
    NSApp.terminate(nil)
}
```

`NSWorkspace.openApplication(at:)` queues a launch that proceeds after the current instance terminates.

### Menubar icon updates on permission state changes

`MenubarController` subscribes to `PermissionsCoordinator.$state` combined with `RecordingSession.$state`:

```swift
permissions.$state
    .combineLatest(session.$state)
    .map { permissionState, sessionState -> NSImage in
        if case .denied = permissionState { return permissionDeniedIcon }
        switch sessionState {
        case .recording: return recordingIcon
        default:         return idleIcon
        }
    }
    .receive(on: RunLoop.main)
    .assign(to: \.image, on: statusItem.button)
```

Permission state is *also* refreshed when the user comes back from System Settings. We listen for `NSApplication.didBecomeActiveNotification` and re-run `preflight()` — if it now returns true, the user just granted while we were backgrounded; transition `.denied → .granted` without a relaunch (the relaunch wrinkle only applies when the *process* fired `CGRequestScreenCaptureAccess`).

Edge case: user *revokes* in System Settings while Snatch is running. Same `didBecomeActive` listener catches it on next foreground; transition `.granted → .denied`, update icon, abort any in-flight recording with a notification.

## 9. Cropper window: pre-warm, multi-display, ordering

### Pre-warm at launch

`CropperWindow` is constructed in `applicationDidFinishLaunching` after the partial-file sweep but before the `ShareableContentCache` background refresh:

```swift
self.cropperWindow = CropperWindow(
    contentRect: NSScreen.main!.frame,    // placeholder; resized on each show
    delegate: self                          // routes onRecord / onCancel
)
// Window is allocated but never orderFrontRegardless'd here.
```

Pre-warm savings come from two things: (1) the `NSWindow` allocation + view-tree construction happens once at launch instead of on the hotkey path; (2) AppKit's lazy first-frame layout cost is paid against a hidden window during launch. Empirically on M-series this saves 20-40ms on first hotkey.

The cropper window is **not** added to `ShareableContentCache.excludingWindows` until first show — its `windowNumber` isn't valid until ordered onscreen at least once. We add it on first `orderFrontRegardless` and keep it across hide/show cycles.

### Show on hotkey

```swift
func showCropper(suggestedRegion: CGRect?) {
    let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
        ?? NSScreen.main!
    cropperWindow.setFrame(screen.frame, display: false)
    cropperWindow.preDrawRegion(suggestedRegion)
    cropperWindow.orderFrontRegardless()
    cropperWindow.makeKey()
    if !shareableContent.contains(cropperWindow) {
        shareableContent.addOurWindow(cropperWindow)
    }
}
```

The cropper is a **single window** sized to the active display's frame. We don't show overlays on other displays. If the user wants to move to another display, they cancel (Esc) and trigger ⇧⌘6 again with the cursor on the desired screen.

### Window levels

```
NSWindow.Level                                   In our use
─────────────────────────────────────────────    ───────────────────────────
.screenSaver       (CGShieldingWindowLevel)      cropperWindow (during crop)
.screenSaver - 1                                 recordingOverlayWindow (during record)
.statusBar                                       (system menubar — above us)
.normal                                          everything else
```

There's no time when both cropper and overlay are visible (cropper hides on Record, overlay shows on Record), so the level distinction is mostly defensive — if a state-machine bug ever shows both, the cropper wins.

### Recording overlay: shared instance

M4 instantiates `RecordingOverlayWindow` per-recording. M5 follows the cropper pattern: instantiate once at launch (hidden), reuse on each recording. Same allocation-and-warm-up savings.

On `session.state == .recording` entry: `recordingOverlay.setFrame(regionWithBorderPadding); orderFrontRegardless()`. On `.recording` exit: `orderOut(nil)`. Both windows go into `ShareableContentCache.excludingWindows` once their `windowNumber`s exist.

### Key-window handling for Esc

Cropper has `canBecomeKey = true` so its `CropperView.keyDown(with:)` receives Esc. When `orderFrontRegardless` + `makeKey` runs, the cropper takes key-window status away from whatever app the user was just in. That's intentional — we need the keyboard.

For recording-overlay Esc: the overlay is click-through everywhere except the Stop button (M4 R3). It does NOT become key window — keystrokes pass through to whatever app is underneath. Esc-to-cancel during recording goes through the Carbon Esc hotkey, not through any window's `keyDown`.

### Display reconfigure during cropping

If the user yanks a display cable while the cropper is on it, `NSApplication.didChangeScreenParametersNotification` fires. Handler in `MenubarCoordinator`: if `session.state == .cropping`, re-resolve active screen (mouse-cursor lookup will now find a remaining screen) and `setFrame` to it. The pre-drawn region is clamped to the new bounds before redraw.

### Edge cases settled

| Case | Behavior |
|---|---|
| `NSScreen.main` is nil (no displays) | Hotkey is no-op; log `.error`. |
| Cursor between screens (in the gap) | `frame.contains` returns false for both; fall through to `NSScreen.main!`. |
| Cursor on a screen that disappears mid-frame | Resolved by display reconfigure handler. |
| Cropper shown on a screen with a notch | Cropper covers whole display including under the notch; uses `screen.frame`, not `visibleFrame`. |
| User triggers ⇧⌘6 on display A, drags region, then mouse moves to display B before pressing Record | Cropper stays on A. Region is in A's coordinates. Record proceeds against A. |

## 10. Data flow

Spec §7 already covers Flows 1–4. Below: only the parts that differ from M4.

### Flow 1 — Cold launch (new in M5)

```
1. user double-clicks Snatch.app
2. macOS launches; LSUIElement = YES means no Dock icon, no app-switcher entry
3. applicationDidFinishLaunching:
   • PartialFileSweeper.sweep()                   sync, ~5ms
   • Component graph constructed                  sync, ~10ms
   • permissionsState = permissions.preflight()   sync, < 1ms
   • CropperWindow + RecordingOverlayWindow allocated, hidden
   • hotkeys.registerGlobal()                     ⇧⌘6 live
   • menubar.show()                               NSStatusItem visible
   • Task.detached { shareableContent.refresh() } 50-200ms in background
   • notifier.requestAuthorizationIfNeeded()      may show OS prompt; non-blocking
   • OS notification subscriptions installed
```

### Flow 2 — Hotkey → cropping (the <100ms path)

```
1. user presses ⇧⌘6 from any app
2. Carbon dispatches event to our handler on main queue
3. HotkeyRegistrar.onHotkey:
     guard permissions.cachedState != .denied else { showDeniedAlert(); return }
     if permissions.cachedState == .notDetermined { route to permission flow; return }
     switch session.state { case .idle: session.beginCropping(); ... }
4. session.state .idle → .cropping  (synchronous @Published update)
5. MenubarCoordinator.cropperPresenter sink fires:
     screen = mouse-cursor screen     ~1ms
     cropperWindow.setFrame(screen.frame); preDrawRegion(regionStore.last)
     cropperWindow.orderFrontRegardless(); makeKey()
6. AppKit paints the cropper                       ~30ms first-of-session, ~5ms warm
─────────────────────────────────────────────────────
   Total: ~30-80ms keypress → first paint, well under 100ms target
```

### Flow 3 — Menubar dropdown → cropping

```
1. user clicks NSStatusItem
2. AppKit shows the dropdown
3. user clicks Start Recording
4. MenubarController routes to same handler as HotkeyRegistrar.onHotkey
5. → identical to Flow 2 from step 3
```

### Flow 4 — Record → save (replaces M4 with full post-stop chain)

```
.cropping
  user clicks Record / presses Space / presses Enter
  cropperWindow.onRecordRequested(region)
  → MenubarCoordinator.recordRequested(region):
      url = pathProvider.nextOutputURL()
      Task { @MainActor in
          await shareableContent.refresh()                  // pre-flight
          let excluding = shareableContent.excludingWindows()
          try await session.start(region: region, scale: scaleStore.current,
                                  fps: 30, outputURL: url,
                                  excludingWindows: excluding)
      }

session.state .cropping → .recording (after pipeline.start returns)
  cropperWindow hidden by sink
  recordingOverlay shown with red border + Stop button
  hotkeys.registerEsc()                            // Carbon Esc registered

.recording
  user clicks Stop (overlay) OR clicks menubar icon OR presses ⇧⌘6
  → session.stop()

session.state .recording → .finalizing → .idle
  recordingOverlay hidden
  hotkeys.unregisterEsc()
  pipeline.stop() returns final URL
  → MenubarCoordinator.handleSessionResult(url, droppedFrames, stopLatencyMs):
      pasteboard.copy(fileURL: url)               // ⌘V works the instant this returns
      recentsStore.add(url)
      notifier.present(savedURL: url)              // "GIF saved", Reveal in Finder action
      Log.coordinator.info("saved \(url) drops=\(...) latency=\(...)ms")
```

### Flow 5 — Recording → cancel via Carbon Esc (newly user-triggerable in M5)

```
.recording
  user presses Esc anywhere (Carbon hotkey, not window keyDown)
  → HotkeyRegistrar.onEsc: session.cancel()

session.state .recording → .cancelling → .idle
  recordingOverlay hidden
  hotkeys.unregisterEsc()
  pipeline.cancel():
    wrapper.stop(); bridge.drainAndDiscard(); bridge.close()
    encoder.cancel() → gifski_finish on detached task → unlink .partial
  no clipboard, no notification, no recents update
  Log.coordinator.info("recording cancelled, .partial unlinked")
```

### Flow 6 — Cropping → cancel via Esc

`CropperView.keyDown(.escape)` → `cropperWindow.onCancelled` → `session.cancelCropping()` → `.cropping → .idle` → cropper hides via sink. No pipeline involved.

### Flow 7 — Notification action ("Reveal in Finder")

```
1. notification fires from Flow 4
2. user clicks it (or its action button "Reveal in Finder")
3. UNUserNotificationCenterDelegate.userNotificationCenter(_:didReceive:withCompletionHandler:)
4. action id == "co.snatch.notification.reveal":
     NSWorkspace.shared.activateFileViewerSelecting([url])
```

### Flow 8 — Recents menu item click

```
1. user opens menubar dropdown
2. menuWillOpen rebuilds Recent Recordings ▸ submenu:
     items = recentsStore.recents().filter { FileManager.default.fileExists(atPath: $0.path) }
     for each item: NSMenuItem(title: filename, action: #selector(revealRecent(_:)))
3. user clicks an item
4. revealRecent(_:): NSWorkspace.shared.activateFileViewerSelecting([url])
```

### Concurrency summary

| Lane | Queue | Notes |
|---|---|---|
| All UI work, state-machine transitions, `@Published` updates | main | `RecordingSession` is `@MainActor` |
| SCStream delegate, frame conversion | `captureQueue` | `qos: .userInteractive`, serial |
| `BridgeQueue` enqueue | from producer Task | lock + semaphore |
| `BridgeQueue` dequeue + `gifski_add_frame_rgba` | `encoderQueue` (single drain loop after backpressure refactor) | `qos: .userInitiated`, serial |
| `gifski_finish` / `gifski_cancel` | `Task.detached(priority: .userInitiated)` | spec §5 mandate |
| `SCShareableContent.refresh` | background `Task` | hotkey path NEVER waits on this |

## 11. Error handling

Spec §8 already enumerates the canonical failures. M5 inherits all of them via M4's `RecordingSession` + `RecordingSessionError` plumbing. New cases below; existing cases unchanged.

### M5-specific cases

| Case | Detection | Behavior |
|---|---|---|
| Hotkey registration fails | `RegisterEventHotKey` returns non-zero | Log `.error` (`"⇧⌘6 already bound by another app"`); menubar still works as the alternative trigger; no user-visible alert. |
| Notification authorization denied | `UNUserNotificationCenter.authorizationStatus` ≠ `.authorized` after request | Recording still saves + clipboard still copied. Log `.info` once at launch. No nag. |
| Notification delivery fails | `UNUserNotificationCenter.add` returns error | Log `.error`. The save already succeeded; the user can find the file via menubar Recents. |
| Pasteboard write fails | `NSPasteboard.writeObjects` returns false | Log `.error`. Save still succeeded; ⌘V won't paste this run, but the file exists. |
| `ShareableContentCache.refresh` fails | thrown `SCStreamError` from `SCShareableContent.current` | Log `.error`; cache remains stale-or-empty. Pre-flight refresh in `recordRequested` retries; if that also fails, capture proceeds without window exclusions (overlays may appear in 1-2 frames of the GIF). Not surfaced to user. |
| Display disconnected mid-recording | SCStream delegate emits stop event | Same as spec §8: `pipeline.stop` throws → `RecordingSessionError.pipelineStopFailed` → `notifier.presentFailure("Recording stopped: display disconnected")`. `.partial` is left for the next-launch sweep. |
| Display disconnected mid-cropping | `NSApplication.didChangeScreenParametersNotification` | §9 handler clamps cropper to remaining screens; no error surfaced. |
| Permission revoked while running | `didBecomeActive` re-preflight returns false after previously returning true | If `.recording`: `session.cancel()` + `notifier.presentFailure("Recording stopped: Screen Recording permission was revoked")`. Icon → red `exclamationmark.triangle.fill`. Hotkey now routes to denied alert. |
| `tccutil reset` mid-process | Same as "Permission revoked" | Same handler. |
| Disk full during encoder write | `GifskiEncoder.addFrame` throws | M4 handling: `pipeline` swallows in the drain loop with `.error` log; M5 escalates the *first* such failure into a `pipeline.stop` failure path: `notifier.presentFailure("Recording failed: disk full")`. Subsequent identical errors in the same recording are squelched in the log. |

### Failure notification API

A new `NotificationPresenter.presentFailure(_ message: String)` mirrors `presentSaved(_ url: URL)`. Same `UNUserNotificationCenter` plumbing, different content:

```swift
content.title = "Snatch — recording failed"
content.body = message
content.sound = .default
// no Reveal-in-Finder action
```

### Logging

Already-declared categories (`Log.capture`, `Log.encoder`, `Log.coordinator`, `Log.system`) cover everything. Two new categories for M5:
- `Log.menubar` — icon state changes, menu rebuilds, dropdown clicks
- `Log.permissions` — TCC state transitions, modal flow

Each at `.info` for state changes, `.error` for failures. No remote telemetry.

### Things explicitly NOT handled in v1

Inherited from spec §8:
- Recording duration cap.
- Crash recovery into watchable GIFs.
- Conflict detection on the global hotkey beyond the failed-registration log.

Plus M5-specific:
- **No retry on `ShareableContentCache` failure**, beyond the per-`recordRequested` pre-flight.
- **No fallback hotkey** if ⇧⌘6 is bound. User can use menubar; rebinding lands in v2 if a settings UI ever ships.
- **No "are you sure?" dialog on Cancel.** Esc during recording silently discards.
- **No automatic relaunch after permission revoked.** The user must trigger ⇧⌘6 again from the modal-quit path.

## 12. Testing strategy

### New TDD-able units

| Component | Test file | Coverage |
|---|---|---|
| `BridgeQueue.dequeueBlocking` / `close` / `drainAndDiscard` | `BridgeQueueBlockingTests.swift` (new) | Producer-from-thread blocks dequeuer → wakes on enqueue; close wakes a blocked dequeuer with nil; close-then-enqueue rejected; drainAndDiscard empties without delivering. |
| `RecordingSession` new states/methods | `RecordingSessionTests.swift` (extend) | `beginCropping` from each state, `cancelCropping` from each state; `start(region:)` from `.cropping` (new transition). ~6 new tests. |
| `ScalePresetStore` | `ScalePresetStoreTests.swift` (new) | Round-trip persist/load; default is `.standard`; corrupt data falls back to default. UserDefaults isolated via `suiteName`. |
| `RecentRecordingsStore` | `RecentRecordingsStoreTests.swift` (new) | `add` prepends; cap at 5; `recents()` filters non-existent files (via `FileManager` with a temp dir fixture); ordering preserved across launches. |
| `PathProvider` | `PathProviderTests.swift` (new) | `nextOutputURL(now:)` produces correct format string; injectable home directory; locale fixed. |
| `PermissionsCoordinator` | `PermissionsCoordinatorTests.swift` (new) | Branch logic with `CGScreenCapturePermissionAdapter` protocol seam: granted preflight → `.granted`; not-determined preflight + grant → `.granted` + `request()` called once; not-determined + deny → `.denied`; cached `.granted` short-circuits subsequent preflights; revocation observer transitions `.granted → .denied`. |
| `PartialFileSweeper` | `PartialFileSweeperTests.swift` (new) | Given a temp dir with `.gif.partial` files matching/not matching the pattern, sweeps the matching ones; non-matching files untouched; works on empty dir; survives unreadable file. |
| `MenubarController` icon-state mapping | `MenubarIconStateTests.swift` (new) | Pure mapping function `(PermissionState, SessionState) -> NSImage`. 15 cells across the 3 permission × 5 session product space: `.denied` permission → `permissionDeniedIcon` regardless of session (5 cells); `.granted`/`.notDetermined` + `.recording` → `recordingIcon` (2 cells); `.granted`/`.notDetermined` + non-`.recording` → `idleIcon` (8 cells). |

### Smoke-only (no unit tests)

- `HotkeyRegistrar` — Carbon registration + dispatch is impossible to mock cleanly.
- `MenubarController` UI itself (NSMenu construction, click handling, icon rendering).
- `NSAlert` modal flows (denied / relaunch).
- `NotificationPresenter` actual delivery.
- `PasteboardWriter` actual paste behavior.
- Cropper window pre-warm path latency.
- Recording overlay window reuse.
- End-to-end menubar app + signing + entitlement.

### M5 manual smoke checklist (done gate)

Run by a human at the keyboard before tagging. M5 ships when ALL hold:

1. **Build & basic tests.** `xcodebuild build -scheme App` succeeds, no warnings. `swift test` and `xcodebuild test -scheme Snatch` both pass; live-capture test still skipped without permission.
2. **Cold launch.** Double-click `Snatch.app`. Menubar icon appears within ~1s. No Dock entry. No app-switcher entry. `~/Desktop/snatch-*.gif.partial` orphans (if any) gone.
3. **First-record system prompt.** Fresh `tccutil reset ScreenCapture co.snatch.app` + relaunch. Press ⇧⌘6. System prompt fires. Click Allow. Relaunch alert appears. Click Quit & Relaunch. App comes back. ⇧⌘6 records successfully.
4. **Hotkey latency.** Time ⇧⌘6 keypress → first paint of cropper rectangle. Assert **< 100 ms** on M-series (cold-but-resident). Repeat for warm hotkey.
5. **Stop latency.** 5-second recording. Time stop trigger → notification appears. Assert **< 500 ms** on M-series.
6. **Cropper.** Drag region; resize via handles; observe dimensions label; click Record / Space / Enter / Esc — all behave correctly. Pre-drawn last-region appears on next ⇧⌘6.
7. **Hotkey from foreign contexts.** ⇧⌘6 while focused in: Safari, Slack, fullscreen video, another app's modal. Cropper appears in all cases.
8. **Stop paths.** Hotkey-stop, menubar-icon-click-stop, Stop-button-click, Carbon-Esc-cancel. Each produces correct end state.
9. **Notification.** Appears within budget. Click body → reveals in Finder. Click "Reveal in Finder" action button → reveals in Finder.
10. **Clipboard.** ⌘V into: Slack, Discord, Finder, Notes, Mail, Messages. Animation preserved (file-URL paste, not GIF data).
11. **Scale presets.** A recording at each preset (Retina/Standard/Compact). Eyeball check; dimensions match expectation.
12. **Recents menu.** Fresh-install → 6 recordings → menu shows last 5; oldest evicted. Delete one of the 5 from Desktop → reopen menu → that one no longer appears (filtered).
13. **Permission revoked mid-session.** While idle: System Settings → toggle Snatch off → return to app → menubar icon turns red; ⇧⌘6 shows denied alert. Toggle back on → icon returns to camera; ⇧⌘6 records successfully without relaunch.
14. **Crash hygiene.** `kill -9 Snatch` mid-recording → relaunch → no `*.partial` files remain on Desktop.
15. **Pre-warm under load.** Run with 5 other heavy apps (Xcode, browser, video player) → ⇧⌘6 latency still < 100 ms.
16. **Backpressure (post-refactor smoke).** 30-second recording at Retina-scale on a large region (1440p+). Assert: GIF playable; final drop count logged is bounded; encoder didn't deadlock; `swift test` still green.
17. **About + Quit.** About panel shows correct version + bundle id. Quit cleanly terminates (no leaked menubar icon).
18. **Tag.** Git tag `m5-menubar-app` exists at HEAD.
19. **CLAUDE.md.** Status section reflects M5 done.

### Latency measurement methodology

For Items 4 and 5: use `os_signpost` with intervals named `hotkey-to-cropper-paint` and `stop-to-notification`. Wrap the paths in signposts during M5 development; read via Instruments → Logging. The < 100 ms / < 500 ms assertions are visual ("did it feel instant?") for the smoke gate, but signposts give a numeric backstop.

CI-grade automation is out of scope for M5.

### TDD discipline

Every component above marked TDD'able follows the standard RED → GREEN → REFACTOR per task. The backpressure refactor (Lane A) lands first via TDD on `BridgeQueue.dequeueBlocking`, then the producer/consumer rewrite is REFACTOR with M4's existing tests as the regression guard. Lanes B–C (stores, system adapters with mockable seams) are TDD-first. Lane D (MenubarController) and most of Lane E/F are smoke-gated.

## 13. M5 done gate

M5 ships when **all** of:

1. All 19 items in the smoke checklist (§12) pass.
2. `swift test` is fully green.
3. `xcodebuild test -scheme Snatch` is fully green.
4. Hotkey-to-cropper measured < 100 ms on M-series (signpost evidence in commit message or smoke log).
5. Stop-latency measured < 500 ms on M-series.
6. `Snatch.app` is dev-signed (`Apple Development` identity), hardened-runtime ON, screen-recording entitlement present, `LSUIElement = YES`.
7. Permission-grant survives an `xcodebuild clean && xcodebuild build` cycle without re-prompting.
8. Backpressure refactor verified by 30-second sustained-Retina smoke (item 16).
9. Git tag `m5-menubar-app` at HEAD.
10. `CLAUDE.md` Status section updated.

Not required for M5: Developer ID signing, notarization, GitHub release, external-tester install, CI latency enforcement.

## 14. Carry-overs to M6

Explicit seams, not bugs:

- **Developer ID Application signing.** M5 uses Apple Development; M6 swaps in Developer ID.
- **Notarization.** `xcrun notarytool submit` against Apple's notary service; staple ticket via `xcrun stapler staple Snatch.app`.
- **Hardened runtime entitlements review.** Confirm no extra entitlements snuck in during M5 development.
- **Gatekeeper test on a fresh Mac.** Download zipped `Snatch.app` to a Mac that's never seen it; assert no "unidentified developer" warning.
- **GitHub release artifacts.** Tag `v1.0.0`. Zip `Snatch.app`. Attach to release. Generate SHA-256.
- **README/install instructions.** Download → unzip → drag to Applications → first launch grants permission.
- **CI for build verification** (optional). GitHub macOS runner: `xcodebuild build -scheme App` on every PR.
- **Latency benchmark in CI** (optional). XCTest with `XCTOSSignpostMetric`.
- **Crash reporter** (deferred from spec §8 v1 non-goals).
- **Auto-update mechanism** (Sparkle, etc.) — out of scope for v1; manual download + replace.
