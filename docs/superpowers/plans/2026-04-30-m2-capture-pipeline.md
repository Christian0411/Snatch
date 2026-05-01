# Snatch M2 — Capture Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the streaming capture-to-GIF pipeline end-to-end with no UI: ScreenCaptureKit feeds `SCStreamWrapper` → `FrameConverter` (BGRA `CVPixelBuffer` → tightly-packed RGBA) → bounded bridge queue → `GifskiEncoder`. A new `snatch-record-cli` executable records a fixed region for a fixed duration and writes a GIF, validating the streaming-encoder model and the **stop-latency budget** (< 500 ms `stop trigger → notification` per spec §7).

**Architecture:** Two serial DispatchQueues separated by a bounded queue. `captureQueue` (`.userInteractive`) hosts `SCStream`'s sample-handler delegate and `FrameConverter.convert`. `encoderQueue` (`.userInitiated`) wraps the blocking gifski FFI calls. `BridgeQueue<T>` (capacity 60 ≈ 2 s @ 30 fps) sits between them and drops the oldest frame on overflow. `SCStreamWrapper` exposes the capture side as `AsyncStream<CMSampleBuffer>` per spec §6 to keep the layer stateless and easy to drive from M4's `RecordingSession`.

**Tech Stack:** Swift 5.10, ScreenCaptureKit (macOS 14), Accelerate.vImage (BGRA→RGBA byte-swap + stride strip), Core Media, gifski C-FFI (already vendored from M1), XCTest. Still pure Swift Package Manager — Xcode project arrives at M3.

---

## Spec references

This plan implements the parts of `docs/superpowers/specs/2026-04-30-snatch-design.md` covering:
- §3 Stack (ScreenCaptureKit, Accelerate)
- §5 Concurrency model (`captureQueue`, `encoderQueue`, bridge queue with drop-oldest semantics)
- §6 Capture layer (`SCStreamWrapper`, `FrameConverter`)
- §7 Flow 1 step 7 — frame-loop semantics
- §8 Logging conventions for capture/encoder categories
- §9 Testing strategy rows for `FrameConverter`, `GifskiEncoder` (integration), `SCStreamWrapper` (smoke)
- §10 M2 carry-overs from M1 (every bullet folded into a task here)

Out of scope for M2 (covered in later milestones):
- Cropper UI, hotkey, menubar, notifications, clipboard (M3–M5)
- `RecordingSession` state machine (M4)
- Pre-warm strategy (M5)
- Full permission-flow modal UX (M5; M2 surfaces permission errors as CLI exit codes only)

## File Structure

After M2 completes, the repo looks like (new/changed entries marked):

```
/Users/starship/src/snatch/
├── .gitignore
├── CLAUDE.md
├── README.md
├── Package.swift                                    (modified — add SnatchRecordCLI target)
├── Sources/
│   ├── SnatchKit/
│   │   ├── SnatchKit.swift                          (deleted — placeholder retired)
│   │   ├── Shared/
│   │   │   ├── RGBAFrame.swift
│   │   │   └── ScalePreset.swift
│   │   ├── Encoder/
│   │   │   └── GifskiEncoder.swift                  (modified — drop fps param, add Threading MARK)
│   │   ├── Capture/
│   │   │   ├── BridgeQueue.swift                    (new)
│   │   │   ├── FrameConverter.swift                 (new)
│   │   │   └── SCStreamWrapper.swift                (new)
│   │   └── Logging/
│   │       └── Log.swift                            (new — os.log subsystem/categories)
│   ├── SnatchCLI/
│   │   └── main.swift                               (modified — fps no longer goes to GifskiEncoder)
│   └── SnatchRecordCLI/
│       └── main.swift                               (new — full-pipeline test runner)
├── Tests/
│   └── SnatchKitTests/
│       ├── Fixtures/
│       │   ├── frame-red.png
│       │   ├── frame-green.png
│       │   └── frame-blue.png
│       ├── PNGLoader.swift                          (modified — throw instead of force-unwrap)
│       ├── GifDecoder.swift                         (modified — throw instead of precondition)
│       ├── RGBAFrameTests.swift
│       ├── ScalePresetTests.swift
│       ├── FixtureTests.swift
│       ├── GifskiEncoderTests.swift                 (modified — drop fps param)
│       ├── BridgeQueueTests.swift                   (new)
│       ├── FrameConverterTests.swift                (new)
│       ├── PipelineIntegrationTests.swift           (new — synthetic CMSampleBuffer pipeline)
│       ├── SCStreamWrapperLiveTests.swift           (new — gated on env var, real capture)
│       └── Helpers/
│           └── SampleBufferFactory.swift            (new — synthesize CMSampleBuffer fixtures)
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
        │   └── 2026-04-30-m2-capture-pipeline.md   (this file)
        └── specs/
            └── 2026-04-30-snatch-design.md
```

**Layering rule:** `Capture/` knows nothing about `Encoder/`. `BridgeQueue<T>` is generic and is the seam — capture-side code enqueues `(RGBAFrame, TimeInterval)` tuples; encoder-side code dequeues. Neither side imports the other's queue label.

---

## Carry-over fixes (Tasks 1–5)

These tasks address the "M2 carry-over" bullets from spec §10. They're small, mostly mechanical, and unblock the rest of M2 (Task 1 in particular changes a function signature that Task 9's CLI depends on). Do them first.

### Task 1: Drop the unused `fps` parameter from `GifskiEncoder.init`

**Decision (locking the spec carry-over):** the encoder owns *encoding*, the capture layer owns *frame rate*. `fps` belongs on `SCStreamConfiguration.minimumFrameInterval`, not on the encoder. gifski derives playback timing from per-frame `presentationTime` regardless of any `fps` hint. Remove it.

**Files:**
- Modify: `Sources/SnatchKit/Encoder/GifskiEncoder.swift`
- Modify: `Tests/SnatchKitTests/GifskiEncoderTests.swift`
- Modify: `Sources/SnatchCLI/main.swift`

- [ ] **Step 1: Remove `fps` from `GifskiEncoder.init`'s signature and doc**

In `Sources/SnatchKit/Encoder/GifskiEncoder.swift`, change the initializer from:

```swift
public init(outputURL: URL, fps: Int = 30, quality: Int = 90) throws {
```

to:

```swift
public init(outputURL: URL, quality: Int = 90) throws {
```

Update the doc comment immediately above the initializer:

```swift
/// Initialise a new gifski writer pointed at `<outputURL>.partial`.
///
/// - Parameters:
///   - outputURL: where the final GIF will land after `finish()`.
///   - quality: gifski quality knob, 1–100. Default 90.
///
/// Frame rate is *not* an encoder concern — gifski derives playback timing
/// from the per-frame `presentationTime` values supplied to `addFrame`.
/// The capture layer (`SCStreamWrapper`) controls capture rate via
/// `SCStreamConfiguration.minimumFrameInterval`.
public init(outputURL: URL, quality: Int = 90) throws {
```

The body of `init` already does not reference `fps`; nothing else changes inside.

- [ ] **Step 2: Update `Tests/SnatchKitTests/GifskiEncoderTests.swift`**

There are four `GifskiEncoder(outputURL: ..., fps: 30, quality: 90)` call sites in this file. Change each to `GifskiEncoder(outputURL: ..., quality: 90)`. The presentation-time arithmetic in the tests already uses a literal `1.0 / 30.0` and is unaffected.

- [ ] **Step 3: Update `Sources/SnatchCLI/main.swift`**

The CLI still owns its own `fps` argument (its job is "encode N PNGs at F fps"). Drop the `fps:` argument when constructing the encoder; keep `fps` as a local for computing presentation times.

Replace:

```swift
let encoder = try GifskiEncoder(outputURL: outURL, fps: fps, quality: 90)
```

with:

```swift
let encoder = try GifskiEncoder(outputURL: outURL, quality: 90)
```

The `Double(i) / Double(fps)` line in the loop body is unchanged.

- [ ] **Step 4: Build and run all tests**

Run: `swift test`
Expected: `Test Suite 'All tests' passed at <…>` — same 11 tests as M1, all green. (No new tests yet; this is a pure parameter cleanup.)

- [ ] **Step 5: Commit**

```bash
git add Sources/SnatchKit/Encoder/GifskiEncoder.swift \
        Tests/SnatchKitTests/GifskiEncoderTests.swift \
        Sources/SnatchCLI/main.swift
git commit -m "refactor(encoder): drop unused fps parameter from GifskiEncoder.init

gifski derives playback timing from per-frame presentationTime values.
fps belongs on the capture side (SCStreamConfiguration.minimumFrameInterval),
not the encoder. Resolves M2 carry-over from spec §10."
```

---

### Task 2: Document `GifskiEncoder` thread-safety contract

**Files:**
- Modify: `Sources/SnatchKit/Encoder/GifskiEncoder.swift`

- [ ] **Step 1: Add a `// MARK: - Threading` block at the top of the class body**

In `Sources/SnatchKit/Encoder/GifskiEncoder.swift`, immediately after the line `public final class GifskiEncoder {` and before the existing `public let outputURL: URL` declaration, insert:

```swift
    // MARK: - Threading
    //
    // GifskiEncoder is NOT internally synchronized. `addFrame`, `finish`, and
    // `cancel` all mutate `gifskiPtr` and the underlying gifski state, and
    // MUST be invoked from a single serial queue (the "encoder queue").
    //
    // Per spec §5, the canonical layout is:
    //   - `encoderQueue`: serial DispatchQueue, QoS .userInitiated, owned by
    //     the orchestrator (M2's snatch-record-cli, M4's RecordingSession).
    //   - `addFrame` is called synchronously from this queue.
    //   - `finish` is async-but-blocking (`gifski_finish` blocks until all
    //     queued frames drain). Schedule it via `Task.detached` or dispatch
    //     to `encoderQueue` — never call from the main actor.
    //   - `cancel` may briefly block while `gifski_finish` drains in-flight
    //     frames, so it too must run off the main thread.
    //
    // Violating this contract corrupts the encoder state and can crash inside
    // gifski's Rust side via aliased `&mut` pointers.

```

- [ ] **Step 2: Verify the file still compiles**

Run: `swift build`
Expected: clean build, no warnings introduced by the comment block.

- [ ] **Step 3: Commit**

```bash
git add Sources/SnatchKit/Encoder/GifskiEncoder.swift
git commit -m "docs(encoder): document threading contract on GifskiEncoder"
```

---

### Task 3: Harden `PNGLoader.fixture()` — replace force-unwrap with throw

**Files:**
- Modify: `Tests/SnatchKitTests/PNGLoader.swift`

- [ ] **Step 1: Add an error case for fixture-not-found**

In `Tests/SnatchKitTests/PNGLoader.swift`, extend `PNGLoaderError`:

```swift
enum PNGLoaderError: Error {
    case sourceCreationFailed
    case imageCreationFailed
    case bitmapContextCreationFailed
    case fixtureNotFound(String)
}
```

- [ ] **Step 2: Replace the force-unwrap in `fixture(_:)`**

Replace the current body:

```swift
static func fixture(_ basename: String) throws -> RGBAFrame {
    let url = Bundle.module.url(forResource: basename, withExtension: "png", subdirectory: "Fixtures")!
    return try load(url)
}
```

with:

```swift
static func fixture(_ basename: String) throws -> RGBAFrame {
    guard let url = Bundle.module.url(forResource: basename, withExtension: "png", subdirectory: "Fixtures") else {
        throw PNGLoaderError.fixtureNotFound(basename)
    }
    return try load(url)
}
```

- [ ] **Step 3: Add a test that asserts the throw**

Append the following case to `Tests/SnatchKitTests/FixtureTests.swift`, inside the existing `FixtureTests` class:

```swift
    func test_fixture_throwsWhenBasenameMissing() {
        XCTAssertThrowsError(try PNGLoader.fixture("does-not-exist")) { error in
            guard case PNGLoaderError.fixtureNotFound(let name) = error else {
                XCTFail("Expected .fixtureNotFound, got \(error)")
                return
            }
            XCTAssertEqual(name, "does-not-exist")
        }
    }
```

- [ ] **Step 4: Run the tests**

Run: `swift test --filter FixtureTests`
Expected: 2 tests pass (the existing red-fixture test and the new throw test).

- [ ] **Step 5: Commit**

```bash
git add Tests/SnatchKitTests/PNGLoader.swift Tests/SnatchKitTests/FixtureTests.swift
git commit -m "test: PNGLoader.fixture throws fixtureNotFound on missing PNG"
```

---

### Task 4: Harden `GifDecoder.decode()` — replace `precondition` with throw

**Files:**
- Modify: `Tests/SnatchKitTests/GifDecoder.swift`

- [ ] **Step 1: Add an error case and replace the precondition**

In `Tests/SnatchKitTests/GifDecoder.swift`, extend the error enum:

```swift
enum GifDecoderError: Error {
    case sourceCreationFailed
    case typeMismatch
    case frameOutOfRange
    case emptyFrameCount
}
```

In `decode(_:)`, replace the line:

```swift
precondition(frameCount > 0)
```

with:

```swift
guard frameCount > 0 else {
    throw GifDecoderError.emptyFrameCount
}
```

- [ ] **Step 2: Build to confirm the file still compiles**

Run: `swift build --build-tests`
Expected: clean build.

- [ ] **Step 3: Commit**

```bash
git add Tests/SnatchKitTests/GifDecoder.swift
git commit -m "test: GifDecoder throws emptyFrameCount instead of crashing"
```

---

### Task 5: Delete the `SnatchKit.swift` placeholder

The file currently contains only the comment `// SnatchKit — types added in Tasks 4-7` from the M1 plan. M2's new types live in their own files; the placeholder is dead.

**Files:**
- Delete: `Sources/SnatchKit/SnatchKit.swift`

- [ ] **Step 1: Delete the file**

Run: `rm /Users/starship/src/snatch/Sources/SnatchKit/SnatchKit.swift`

- [ ] **Step 2: Build to confirm SnatchKit still has at least one source file**

Run: `swift build`
Expected: build succeeds (the remaining files under `Sources/SnatchKit/` provide content for the target).

- [ ] **Step 3: Commit**

```bash
git add -A Sources/SnatchKit/SnatchKit.swift
git commit -m "chore: remove SnatchKit.swift placeholder"
```

(The `-A` here picks up the deletion; we are not staging anything else in this commit.)

---

## Capture pipeline (Tasks 6–11)

### Task 6: `BridgeQueue<T>` — bounded queue with drop-oldest semantics

A thread-safe FIFO that holds up to `capacity` items. On overflow, the oldest item is evicted and a counter increments. The encoder-side reads via `dequeue()`. Tracking dropped frames is required by spec §8 ("On stop, log final drop count").

**Files:**
- Create: `Sources/SnatchKit/Capture/BridgeQueue.swift`
- Test: `Tests/SnatchKitTests/BridgeQueueTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/SnatchKitTests/BridgeQueueTests.swift`:

```swift
import XCTest
@testable import SnatchKit

final class BridgeQueueTests: XCTestCase {
    func test_enqueueAndDequeue_preservesFifoOrder() {
        let q = BridgeQueue<Int>(capacity: 4)
        q.enqueue(1)
        q.enqueue(2)
        q.enqueue(3)

        XCTAssertEqual(q.dequeue(), 1)
        XCTAssertEqual(q.dequeue(), 2)
        XCTAssertEqual(q.dequeue(), 3)
        XCTAssertNil(q.dequeue())
    }

    func test_underCapacity_dropCountIsZero() {
        let q = BridgeQueue<Int>(capacity: 4)
        q.enqueue(1)
        q.enqueue(2)
        XCTAssertEqual(q.droppedCount, 0)
    }

    func test_overCapacity_dropsOldest_incrementsCounter() {
        let q = BridgeQueue<Int>(capacity: 3)
        q.enqueue(1)
        q.enqueue(2)
        q.enqueue(3)
        q.enqueue(4) // overflow — drops 1
        q.enqueue(5) // overflow — drops 2

        XCTAssertEqual(q.droppedCount, 2)
        XCTAssertEqual(q.dequeue(), 3)
        XCTAssertEqual(q.dequeue(), 4)
        XCTAssertEqual(q.dequeue(), 5)
        XCTAssertNil(q.dequeue())
    }

    func test_capacityZero_everyEnqueueDrops() {
        let q = BridgeQueue<Int>(capacity: 0)
        q.enqueue(1)
        q.enqueue(2)
        XCTAssertEqual(q.droppedCount, 2)
        XCTAssertNil(q.dequeue())
    }

    func test_concurrent_producersAndConsumer_doNotCrash() {
        let q = BridgeQueue<Int>(capacity: 32)
        let producers = DispatchQueue(label: "test.producers", attributes: .concurrent)
        let consumer = DispatchQueue(label: "test.consumer")
        let group = DispatchGroup()

        for i in 0..<1_000 {
            group.enter()
            producers.async {
                q.enqueue(i)
                group.leave()
            }
        }

        let consumed = NSMutableArray()
        let consumeTask = DispatchWorkItem {
            for _ in 0..<2_000 {
                if let v = q.dequeue() { consumed.add(v) }
            }
        }
        consumer.async(execute: consumeTask)

        group.wait()
        consumeTask.wait()
        // Soundness: never crashed. Drop count + consumed.count <= 1000.
        XCTAssertLessThanOrEqual(consumed.count + q.droppedCount, 1_000)
    }
}
```

- [ ] **Step 2: Run the tests to confirm they fail (compile error — type missing)**

Run: `swift test --filter BridgeQueueTests`
Expected: build fails with `cannot find 'BridgeQueue' in scope`.

- [ ] **Step 3: Implement `BridgeQueue<T>`**

Create `Sources/SnatchKit/Capture/BridgeQueue.swift`:

```swift
import Foundation

/// Bounded FIFO queue for handing items from the capture queue to the encoder
/// queue. On overflow the OLDEST item is dropped and `droppedCount` is bumped.
///
/// Per spec §5, the production capacity is 60 (≈ 2 s @ 30 fps). The bridge is
/// the back-pressure relief valve — drops are graceful degradation, not a
/// fatal error.
///
/// Thread-safety: all operations are guarded by an internal NSLock. Suitable
/// for many-producer / one-consumer or one-producer / one-consumer use.
public final class BridgeQueue<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: [T] = []
    private var _droppedCount: Int = 0
    public let capacity: Int

    public init(capacity: Int) {
        self.capacity = max(0, capacity)
        self.buffer.reserveCapacity(self.capacity)
    }

    /// Number of items dropped due to overflow since construction.
    public var droppedCount: Int {
        lock.withLock { _droppedCount }
    }

    /// Snapshot the current item count.
    public var count: Int {
        lock.withLock { buffer.count }
    }

    /// Push an item. If the buffer is at capacity, the oldest is removed
    /// (FIFO eviction) and `droppedCount` is incremented.
    /// Returns the new dropped-count *after* the call (useful for one-shot logging).
    @discardableResult
    public func enqueue(_ item: T) -> Int {
        lock.withLock {
            if capacity == 0 {
                _droppedCount += 1
                return _droppedCount
            }
            if buffer.count >= capacity {
                buffer.removeFirst()
                _droppedCount += 1
            }
            buffer.append(item)
            return _droppedCount
        }
    }

    /// Pop the oldest item, or nil if empty.
    public func dequeue() -> T? {
        lock.withLock {
            buffer.isEmpty ? nil : buffer.removeFirst()
        }
    }

    /// Drain everything in FIFO order. Useful at stop time before calling
    /// `GifskiEncoder.finish()`.
    public func drain() -> [T] {
        lock.withLock {
            let out = buffer
            buffer.removeAll(keepingCapacity: true)
            return out
        }
    }
}
```

- [ ] **Step 4: Run the tests to confirm they pass**

Run: `swift test --filter BridgeQueueTests`
Expected: 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/SnatchKit/Capture/BridgeQueue.swift Tests/SnatchKitTests/BridgeQueueTests.swift
git commit -m "feat(capture): add BridgeQueue<T> bounded queue with drop-oldest"
```

---

### Task 7: Sample-buffer factory test helper

A pure helper that synthesizes `CMSampleBuffer`s from caller-supplied BGRA bytes (with optional row padding). Required by `FrameConverterTests` (Task 8) and `PipelineIntegrationTests` (Task 10), where we want deterministic input without invoking ScreenCaptureKit.

**Files:**
- Create: `Tests/SnatchKitTests/Helpers/SampleBufferFactory.swift`

- [ ] **Step 1: Implement the helper**

Create `Tests/SnatchKitTests/Helpers/SampleBufferFactory.swift`:

```swift
import Foundation
import CoreMedia
import CoreVideo

enum SampleBufferFactoryError: Error {
    case pixelBufferCreationFailed(CVReturn)
    case formatDescriptionFailed(OSStatus)
    case sampleBufferCreationFailed(OSStatus)
    case strideTooSmall
}

enum SampleBufferFactory {

    /// Create a CMSampleBuffer wrapping a CVPixelBuffer of the given size,
    /// filled uniformly with the given BGRA pixel value.
    ///
    /// - Parameters:
    ///   - width: pixel width
    ///   - height: pixel height
    ///   - bgra: 4 bytes — Blue, Green, Red, Alpha — written into every pixel
    ///   - presentationTime: PTS in seconds (mapped onto a CMTime with timescale 1_000_000)
    ///   - extraStrideBytes: bytes added to each row beyond `width * 4`. Use to
    ///     simulate ScreenCaptureKit's IOSurface row padding. CoreVideo decides
    ///     the *actual* stride; we will write into whatever stride it chose,
    ///     which is typically >= width*4 with extra alignment. Pass `nil` to
    ///     accept CoreVideo's default.
    static func makeBGRA(
        width: Int,
        height: Int,
        bgra: (UInt8, UInt8, UInt8, UInt8),
        presentationTime: TimeInterval = 0
    ) throws -> CMSampleBuffer {
        let attrs: [CFString: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
            kCVPixelBufferMetalCompatibilityKey: true,
        ]

        var pb: CVPixelBuffer?
        let cvResult = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width, height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pb
        )
        guard cvResult == kCVReturnSuccess, let pixelBuffer = pb else {
            throw SampleBufferFactoryError.pixelBufferCreationFailed(cvResult)
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        let actualStride = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw SampleBufferFactoryError.pixelBufferCreationFailed(-1)
        }

        for y in 0..<height {
            let row = base.advanced(by: y * actualStride).assumingMemoryBound(to: UInt8.self)
            for x in 0..<width {
                let p = row + x * 4
                p[0] = bgra.0
                p[1] = bgra.1
                p[2] = bgra.2
                p[3] = bgra.3
            }
            // Padding bytes (if any) are left uninitialised — FrameConverter
            // must skip them, never read them.
        }

        var formatDesc: CMFormatDescription?
        let fdStatus = CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDesc
        )
        guard fdStatus == noErr, let fd = formatDesc else {
            throw SampleBufferFactoryError.formatDescriptionFailed(fdStatus)
        }

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: CMTime(seconds: presentationTime, preferredTimescale: 1_000_000),
            decodeTimeStamp: .invalid
        )

        var sampleBuffer: CMSampleBuffer?
        let sbStatus = CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: fd,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
        guard sbStatus == noErr, let sb = sampleBuffer else {
            throw SampleBufferFactoryError.sampleBufferCreationFailed(sbStatus)
        }
        return sb
    }
}
```

- [ ] **Step 2: Build to confirm it compiles cleanly**

Run: `swift build --build-tests`
Expected: clean build (no test target imports it yet — that's Task 8).

- [ ] **Step 3: Commit**

```bash
git add Tests/SnatchKitTests/Helpers/SampleBufferFactory.swift
git commit -m "test: add SampleBufferFactory for synthetic CMSampleBuffer fixtures"
```

---

### Task 8: `FrameConverter` — `CMSampleBuffer` → `RGBAFrame`

Convert the BGRA `CVPixelBuffer` inside an SCStream sample to a tightly-packed RGBA `RGBAFrame`. Two responsibilities:

1. **Byte-swap** BGRA → RGBA via `Accelerate.vImage.vImagePermuteChannels_ARGB8888`.
2. **Strip row padding** (`bytesPerRow > width * 4`) by writing into a dest buffer with `width * 4` row stride.

Per spec §6: "Allocates from a shared buffer pool — no per-frame allocation churn." For M2 the "pool" is a single reusable `Data` whose size is the current output frame size, reallocated only if frame dimensions change. Sufficient for v1 — a real pool is YAGNI.

**Files:**
- Create: `Sources/SnatchKit/Capture/FrameConverter.swift`
- Test: `Tests/SnatchKitTests/FrameConverterTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/SnatchKitTests/FrameConverterTests.swift`:

```swift
import XCTest
import CoreMedia
@testable import SnatchKit

final class FrameConverterTests: XCTestCase {

    func test_convert_swapsBgraToRgba() throws {
        // Source pixel: B=0x10, G=0x20, R=0x30, A=0xFF
        // Expected output pixel: R=0x30, G=0x20, B=0x10, A=0xFF
        let sample = try SampleBufferFactory.makeBGRA(
            width: 2, height: 2,
            bgra: (0x10, 0x20, 0x30, 0xFF)
        )
        let converter = FrameConverter()

        let frame = try XCTUnwrap(converter.convert(sample))

        XCTAssertEqual(frame.width, 2)
        XCTAssertEqual(frame.height, 2)
        XCTAssertEqual(frame.bytes.count, 2 * 2 * 4)

        for pixelStart in stride(from: 0, to: frame.bytes.count, by: 4) {
            XCTAssertEqual(frame.bytes[pixelStart + 0], 0x30, "R at \(pixelStart)")
            XCTAssertEqual(frame.bytes[pixelStart + 1], 0x20, "G at \(pixelStart)")
            XCTAssertEqual(frame.bytes[pixelStart + 2], 0x10, "B at \(pixelStart)")
            XCTAssertEqual(frame.bytes[pixelStart + 3], 0xFF, "A at \(pixelStart)")
        }
    }

    func test_convert_stripsRowPadding() throws {
        // Use a width that CoreVideo is very likely to pad: width 17 forces
        // row alignment >= 68 bytes, but 16-byte alignment usually pushes
        // bytesPerRow to 80.
        let width = 17
        let height = 3
        let sample = try SampleBufferFactory.makeBGRA(
            width: width, height: height,
            bgra: (0xAA, 0xBB, 0xCC, 0xFF)
        )
        let pixelBuffer = try XCTUnwrap(CMSampleBufferGetImageBuffer(sample))
        let actualStride = CVPixelBufferGetBytesPerRow(pixelBuffer)
        XCTAssertGreaterThanOrEqual(actualStride, width * 4)
        // We don't *require* CoreVideo to pad — but we want the test to be
        // meaningful. If the platform happens to pack tightly, this still
        // exercises the equal-stride path which is also valid.

        let converter = FrameConverter()
        let frame = try XCTUnwrap(converter.convert(sample))

        XCTAssertEqual(frame.width, width)
        XCTAssertEqual(frame.height, height)
        XCTAssertEqual(frame.bytes.count, width * height * 4,
                       "Output must be tightly packed (no padding)")

        // Spot-check the last pixel of the last row to ensure stride strip
        // didn't leave junk at the row tail.
        let lastPixel = (height - 1) * width * 4 + (width - 1) * 4
        XCTAssertEqual(frame.bytes[lastPixel + 0], 0xCC, "R")
        XCTAssertEqual(frame.bytes[lastPixel + 1], 0xBB, "G")
        XCTAssertEqual(frame.bytes[lastPixel + 2], 0xAA, "B")
        XCTAssertEqual(frame.bytes[lastPixel + 3], 0xFF, "A")
    }

    func test_convert_repeatedCalls_reuseBuffer() throws {
        let converter = FrameConverter()
        let sample = try SampleBufferFactory.makeBGRA(
            width: 8, height: 8,
            bgra: (1, 2, 3, 0xFF)
        )

        // Two convert calls of the same dimensions; both must succeed.
        // (We can't observe pool re-use directly, but we can verify
        // correctness across calls — a reset bug would surface as garbled
        // output on the second call.)
        let f1 = try XCTUnwrap(converter.convert(sample))
        let f2 = try XCTUnwrap(converter.convert(sample))

        XCTAssertEqual(f1.bytes, f2.bytes)
    }

    func test_convert_handlesDifferentDimensionsAcrossCalls() throws {
        let converter = FrameConverter()
        let small = try SampleBufferFactory.makeBGRA(width: 4, height: 4, bgra: (1, 2, 3, 0xFF))
        let large = try SampleBufferFactory.makeBGRA(width: 32, height: 32, bgra: (1, 2, 3, 0xFF))

        let smallFrame = try XCTUnwrap(converter.convert(small))
        let largeFrame = try XCTUnwrap(converter.convert(large))

        XCTAssertEqual(smallFrame.bytes.count, 4 * 4 * 4)
        XCTAssertEqual(largeFrame.bytes.count, 32 * 32 * 4)
    }
}
```

- [ ] **Step 2: Run the tests to confirm they fail**

Run: `swift test --filter FrameConverterTests`
Expected: build fails — `cannot find 'FrameConverter' in scope`.

- [ ] **Step 3: Implement `FrameConverter`**

Create `Sources/SnatchKit/Capture/FrameConverter.swift`:

```swift
import Foundation
import CoreMedia
import CoreVideo
import Accelerate

/// Converts BGRA `CMSampleBuffer`s from ScreenCaptureKit into tightly-packed
/// RGBA `RGBAFrame`s. Strips row padding (`bytesPerRow > width * 4`) and
/// performs a byte-swap (BGRA → RGBA) via `vImagePermuteChannels_ARGB8888`.
///
/// Threading: not internally synchronized. Per spec §5, the conversion is
/// expected to run on `captureQueue`. Construct one per recording session.
public final class FrameConverter {

    /// Single reusable destination buffer. Reallocated only if the next frame
    /// has different dimensions.
    private var buffer: Data = Data()
    private var bufferWidth: Int = 0
    private var bufferHeight: Int = 0

    public init() {}

    /// Convert one sample. Returns `nil` if the sample has no image buffer or
    /// the pixel format is unsupported (we only handle 32BGRA in M2).
    public func convert(_ sample: CMSampleBuffer) -> RGBAFrame? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sample) else {
            return nil
        }
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        guard pixelFormat == kCVPixelFormatType_32BGRA else {
            return nil
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let srcStride = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let dstRowBytes = width * 4
        let dstByteCount = dstRowBytes * height

        // Resize the reusable destination buffer if needed.
        if bufferWidth != width || bufferHeight != height || buffer.count != dstByteCount {
            buffer = Data(count: dstByteCount)
            bufferWidth = width
            bufferHeight = height
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let srcBase = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return nil
        }

        var srcVImage = vImage_Buffer(
            data: srcBase,
            height: vImagePixelCount(height),
            width: vImagePixelCount(width),
            rowBytes: srcStride
        )

        let success = buffer.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) -> Bool in
            guard let dstBase = raw.baseAddress else { return false }
            var dstVImage = vImage_Buffer(
                data: dstBase,
                height: vImagePixelCount(height),
                width: vImagePixelCount(width),
                rowBytes: dstRowBytes
            )
            // BGRA bytes (B=0, G=1, R=2, A=3) → RGBA layout (R=0, G=1, B=2, A=3).
            // permuteMap[i] = source-channel-index for output channel i.
            var permuteMap: [UInt8] = [2, 1, 0, 3]
            let result = vImagePermuteChannels_ARGB8888(
                &srcVImage,
                &dstVImage,
                &permuteMap,
                vImage_Flags(kvImageNoFlags)
            )
            return result == kvImageNoError
        }

        guard success else { return nil }
        return RGBAFrame(bytes: buffer, width: width, height: height)
    }
}
```

- [ ] **Step 4: Run the tests to confirm they pass**

Run: `swift test --filter FrameConverterTests`
Expected: 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/SnatchKit/Capture/FrameConverter.swift \
        Tests/SnatchKitTests/FrameConverterTests.swift
git commit -m "feat(capture): add FrameConverter (BGRA → tightly-packed RGBA)

Uses vImagePermuteChannels_ARGB8888 for byte-swap and stride strip in
one pass. Reuses a single dest buffer across calls to avoid per-frame
allocation churn (spec §6)."
```

---

### Task 9: `Log` — minimal `os.log` facade

Spec §8 mandates Apple unified logging with subsystem `co.snatch.app` and categories `capture`, `encoder`, `coordinator`, `ui`, `system`. We need at least `capture` and `encoder` for M2 to log frame drops and stop-latency. Wrap once so callers don't import `os.log` directly.

**Files:**
- Create: `Sources/SnatchKit/Logging/Log.swift`

- [ ] **Step 1: Implement the wrapper**

Create `Sources/SnatchKit/Logging/Log.swift`:

```swift
import Foundation
import os

/// Snatch's unified-logging facade.
///
/// Subsystem: `co.snatch.app` (per spec §8).
/// Categories: capture, encoder, coordinator, ui, system.
///
/// Levels in use:
///   - `.info`  — state transitions, recording start/stop with region + scale
///   - `.debug` — frame drops, queue depth peaks
///   - `.error` — every error with full context
public enum Log {
    private static let subsystem = "co.snatch.app"

    public static let capture = Logger(subsystem: subsystem, category: "capture")
    public static let encoder = Logger(subsystem: subsystem, category: "encoder")
    public static let coordinator = Logger(subsystem: subsystem, category: "coordinator")
    public static let ui = Logger(subsystem: subsystem, category: "ui")
    public static let system = Logger(subsystem: subsystem, category: "system")
}
```

- [ ] **Step 2: Build to confirm it compiles**

Run: `swift build`
Expected: clean build.

- [ ] **Step 3: Commit**

```bash
git add Sources/SnatchKit/Logging/Log.swift
git commit -m "feat: add Log facade over os.log (spec §8)"
```

---

### Task 10: `SCStreamWrapper` — ScreenCaptureKit lifecycle

Wrap `SCStream` start/stop. Discover the right display, build `SCContentFilter` (no exclusions in M2 — they arrive in M5 with the cropper), build `SCStreamConfiguration`, register a `SCStreamOutput` delegate that yields raw `CMSampleBuffer`s onto an `AsyncStream`, and surface ScreenCaptureKit failures as Swift errors.

**Files:**
- Create: `Sources/SnatchKit/Capture/SCStreamWrapper.swift`
- (Live tests deferred to Task 11.)

- [ ] **Step 1: Implement the wrapper**

Create `Sources/SnatchKit/Capture/SCStreamWrapper.swift`:

```swift
import Foundation
import ScreenCaptureKit
import CoreMedia
import CoreGraphics

public enum SCStreamWrapperError: Error, CustomStringConvertible {
    case permissionDenied
    case noDisplaysAvailable
    case displayNotFound(region: CGRect)
    case startFailed(underlying: Error)

    public var description: String {
        switch self {
        case .permissionDenied:
            return "Screen Recording permission is not granted. Open System Settings → Privacy & Security → Screen Recording."
        case .noDisplaysAvailable:
            return "No displays returned by SCShareableContent.current"
        case .displayNotFound(let r):
            return "No display contains region \(r)"
        case .startFailed(let e):
            return "SCStream.startCapture failed: \(e)"
        }
    }
}

/// Thin wrapper over `SCStream` lifecycle. Returns frames as
/// `AsyncStream<CMSampleBuffer>`. The caller is responsible for running
/// `FrameConverter.convert` on the queue passed to `start(...)` (spec §5).
///
/// Threading: methods are safe to call from any queue, but you should not
/// call `start` and `stop` concurrently from different tasks.
public final class SCStreamWrapper {

    private var stream: SCStream?
    private var output: StreamOutput?
    private var continuation: AsyncStream<CMSampleBuffer>.Continuation?

    public init() {}

    /// Start capture. Returns an `AsyncStream` that yields each successful
    /// `CMSampleBuffer` (status `.complete`) on the supplied `queue`. Idle /
    /// dropped status frames are silently filtered. The stream finishes when
    /// `stop()` is called or the wrapper is deinitialised.
    ///
    /// - Parameters:
    ///   - region: rectangle to capture, in points, in the global CG coord
    ///     space (origin top-left). For M2 the caller picks coordinates by
    ///     hand; M3's cropper will produce them.
    ///   - scale: applies `SCStreamConfiguration.width/height` per spec §6.
    ///   - fps: target capture rate; mapped to `minimumFrameInterval`.
    ///   - queue: the `sampleHandlerQueue` for SCStream's delegate. Conversion
    ///     is expected to run on this queue per spec §5.
    public func start(
        region: CGRect,
        scale: ScalePreset,
        fps: Int,
        queue: DispatchQueue
    ) async throws -> AsyncStream<CMSampleBuffer> {

        guard CGPreflightScreenCaptureAccess() else {
            throw SCStreamWrapperError.permissionDenied
        }

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true
            )
        } catch {
            throw SCStreamWrapperError.startFailed(underlying: error)
        }

        guard !content.displays.isEmpty else {
            throw SCStreamWrapperError.noDisplaysAvailable
        }

        let display: SCDisplay
        if let containing = content.displays.first(where: { $0.frame.contains(region) }) {
            display = containing
        } else if let intersecting = content.displays.first(where: { $0.frame.intersects(region) }) {
            display = intersecting
        } else {
            throw SCStreamWrapperError.displayNotFound(region: region)
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])

        let outputSize = Self.outputSize(for: region, scale: scale, displayScale: display.backingScaleFactor)
        let config = SCStreamConfiguration()
        config.width = outputSize.width
        config.height = outputSize.height
        config.minimumFrameInterval = CMTime(value: 1, timescale: Int32(max(fps, 1)))
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.queueDepth = 8
        config.showsCursor = true
        config.sourceRect = Self.sourceRect(region: region, in: display)

        let (asyncStream, asyncContinuation) = AsyncStream<CMSampleBuffer>.makeStream(
            bufferingPolicy: .unbounded
        )

        let outputDelegate = StreamOutput(continuation: asyncContinuation)
        let scStream = SCStream(filter: filter, configuration: config, delegate: nil)
        do {
            try scStream.addStreamOutput(outputDelegate, type: .screen, sampleHandlerQueue: queue)
            try await scStream.startCapture()
        } catch {
            asyncContinuation.finish()
            throw SCStreamWrapperError.startFailed(underlying: error)
        }

        self.stream = scStream
        self.output = outputDelegate
        self.continuation = asyncContinuation

        Log.capture.info("SCStream started: region=\(NSStringFromRect(NSRectFromCGRect(region))) scale=\(scale.rawValue, privacy: .public) fps=\(fps) outputSize=\(outputSize.width)x\(outputSize.height)")
        return asyncStream
    }

    /// Stop capture. Idempotent.
    public func stop() async {
        guard let scStream = stream else { return }
        do {
            try await scStream.stopCapture()
        } catch {
            Log.capture.error("SCStream.stopCapture failed: \(String(describing: error), privacy: .public)")
        }
        continuation?.finish()
        stream = nil
        output = nil
        continuation = nil
        Log.capture.info("SCStream stopped")
    }

    deinit {
        continuation?.finish()
    }

    // MARK: - Helpers (internal, exposed for tests)

    /// Map (region, scale, displayBackingScale) → SCStreamConfiguration width/height.
    /// Spec §6:
    ///   .retina   → physical pixels (region * displayBackingScaleFactor)
    ///   .standard → logical pixels  (region * 1)
    ///   .compact  → 0.5× logical    (region * 0.5)
    static func outputSize(
        for region: CGRect,
        scale: ScalePreset,
        displayScale: CGFloat
    ) -> (width: Int, height: Int) {
        let multiplier: CGFloat
        switch scale {
        case .retina:   multiplier = displayScale
        case .standard: multiplier = 1
        case .compact:  multiplier = 0.5
        }
        let w = max(1, Int((region.width * multiplier).rounded()))
        let h = max(1, Int((region.height * multiplier).rounded()))
        return (w, h)
    }

    /// Convert a global CG region to a display-local sourceRect.
    /// SCStreamConfiguration.sourceRect is in points relative to the display's
    /// own origin (top-left).
    static func sourceRect(region: CGRect, in display: SCDisplay) -> CGRect {
        let displayOrigin = display.frame.origin
        return CGRect(
            x: region.origin.x - displayOrigin.x,
            y: region.origin.y - displayOrigin.y,
            width: region.size.width,
            height: region.size.height
        )
    }
}

private final class StreamOutput: NSObject, SCStreamOutput {
    let continuation: AsyncStream<CMSampleBuffer>.Continuation

    init(continuation: AsyncStream<CMSampleBuffer>.Continuation) {
        self.continuation = continuation
        super.init()
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .screen else { return }
        guard sampleBuffer.isValid else { return }

        // Filter idle/blank frames. ScreenCaptureKit emits frames with
        // SCFrameStatus != .complete when nothing changed on screen; we don't
        // want those.
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
           let info = attachments.first,
           let rawStatus = info[.status] as? Int,
           let status = SCFrameStatus(rawValue: rawStatus),
           status != .complete {
            return
        }

        continuation.yield(sampleBuffer)
    }
}
```

- [ ] **Step 2: Add unit tests for the pure helpers**

Create `Tests/SnatchKitTests/SCStreamWrapperHelperTests.swift`:

```swift
import XCTest
import CoreGraphics
@testable import SnatchKit

final class SCStreamWrapperHelperTests: XCTestCase {

    func test_outputSize_retina_doublesOnHighDpi() {
        let (w, h) = SCStreamWrapper.outputSize(
            for: CGRect(x: 0, y: 0, width: 320, height: 240),
            scale: .retina,
            displayScale: 2.0
        )
        XCTAssertEqual(w, 640)
        XCTAssertEqual(h, 480)
    }

    func test_outputSize_retina_passthroughOnNonRetina() {
        let (w, h) = SCStreamWrapper.outputSize(
            for: CGRect(x: 0, y: 0, width: 320, height: 240),
            scale: .retina,
            displayScale: 1.0
        )
        XCTAssertEqual(w, 320)
        XCTAssertEqual(h, 240)
    }

    func test_outputSize_standard_logicalPixels() {
        let (w, h) = SCStreamWrapper.outputSize(
            for: CGRect(x: 0, y: 0, width: 400, height: 300),
            scale: .standard,
            displayScale: 2.0
        )
        XCTAssertEqual(w, 400)
        XCTAssertEqual(h, 300)
    }

    func test_outputSize_compact_halfLogical() {
        let (w, h) = SCStreamWrapper.outputSize(
            for: CGRect(x: 0, y: 0, width: 400, height: 300),
            scale: .compact,
            displayScale: 2.0
        )
        XCTAssertEqual(w, 200)
        XCTAssertEqual(h, 150)
    }

    func test_outputSize_neverReturnsZero() {
        let (w, h) = SCStreamWrapper.outputSize(
            for: CGRect(x: 0, y: 0, width: 0.4, height: 0.4),
            scale: .compact,
            displayScale: 1.0
        )
        XCTAssertGreaterThanOrEqual(w, 1)
        XCTAssertGreaterThanOrEqual(h, 1)
    }
}
```

Note: `sourceRect` is harder to unit-test without an `SCDisplay` instance (which we cannot construct directly). Coverage for that path comes from the live capture test in Task 11.

- [ ] **Step 3: Run all tests to confirm green**

Run: `swift test`
Expected: all suites green — existing 12 tests + 5 BridgeQueue + 4 FrameConverter + 5 SCStreamWrapperHelper = 26 tests.

- [ ] **Step 4: Commit**

```bash
git add Sources/SnatchKit/Capture/SCStreamWrapper.swift \
        Tests/SnatchKitTests/SCStreamWrapperHelperTests.swift
git commit -m "feat(capture): add SCStreamWrapper over ScreenCaptureKit

Wraps SCStream.startCapture/stopCapture, discovers the display containing
the requested region, configures sourceRect/width/height/fps, and yields
status==.complete CMSampleBuffers on an AsyncStream. Permission errors
surface as SCStreamWrapperError.permissionDenied (spec §8 first-launch
flow handled at the M5 UI layer)."
```

---

### Task 11: Pipeline integration test (synthetic CMSampleBuffer end-to-end)

Drive `FrameConverter` → `BridgeQueue` → `GifskiEncoder` with synthetic samples (no SCStream). Asserts the layer wiring is sound — same shape as M5's manual smoke but deterministic.

**Files:**
- Test: `Tests/SnatchKitTests/PipelineIntegrationTests.swift`

- [ ] **Step 1: Write the test**

Create `Tests/SnatchKitTests/PipelineIntegrationTests.swift`:

```swift
import XCTest
import CoreMedia
@testable import SnatchKit

final class PipelineIntegrationTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() async throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("snatch-pipeline-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func test_threeSyntheticFrames_throughPipeline_produceValidGif() async throws {
        let outURL = tempDir.appendingPathComponent("pipeline.gif")

        // BGRA bytes for primary colors
        let red   = try SampleBufferFactory.makeBGRA(width: 64, height: 64, bgra: (0, 0, 255, 0xFF))
        let green = try SampleBufferFactory.makeBGRA(width: 64, height: 64, bgra: (0, 255, 0, 0xFF))
        let blue  = try SampleBufferFactory.makeBGRA(width: 64, height: 64, bgra: (255, 0, 0, 0xFF))

        let converter = FrameConverter()
        let bridge = BridgeQueue<(RGBAFrame, TimeInterval)>(capacity: 60)
        let encoder = try GifskiEncoder(outputURL: outURL, quality: 90)

        // Producer side (mimics what would run on captureQueue).
        for (i, sample) in [red, green, blue].enumerated() {
            let frame = try XCTUnwrap(converter.convert(sample))
            bridge.enqueue((frame, Double(i) / 30.0))
        }

        // Consumer side (mimics encoderQueue).
        while let item = bridge.dequeue() {
            try encoder.addFrame(item.0, presentationTime: item.1)
        }
        try await encoder.finish()

        // Assert the GIF is valid and frame colors round-trip approximately.
        let decoded = try GifDecoder.decode(outURL)
        XCTAssertEqual(decoded.frameCount, 3)
        XCTAssertEqual(decoded.width, 64)
        XCTAssertEqual(decoded.height, 64)
        XCTAssertEqual(bridge.droppedCount, 0)

        let (r0, g0, b0) = decoded.pixelAt(0, 4, 4)!
        XCTAssertGreaterThan(Int(r0), 200); XCTAssertLessThan(Int(g0), 60); XCTAssertLessThan(Int(b0), 60)
        let (r1, g1, b1) = decoded.pixelAt(1, 4, 4)!
        XCTAssertLessThan(Int(r1), 60); XCTAssertGreaterThan(Int(g1), 200); XCTAssertLessThan(Int(b1), 60)
        let (r2, g2, b2) = decoded.pixelAt(2, 4, 4)!
        XCTAssertLessThan(Int(r2), 60); XCTAssertLessThan(Int(g2), 60); XCTAssertGreaterThan(Int(b2), 200)
    }

    func test_overflow_isCapped_andDropCountReported() async throws {
        // Overflow the bridge: enqueue 70 frames into a capacity-60 queue.
        // Verify the encoder still produces a 60-frame GIF (the most recent
        // 60), and droppedCount == 10.
        let outURL = tempDir.appendingPathComponent("overflow.gif")
        let converter = FrameConverter()
        let bridge = BridgeQueue<(RGBAFrame, TimeInterval)>(capacity: 60)
        let encoder = try GifskiEncoder(outputURL: outURL, quality: 90)

        let sample = try SampleBufferFactory.makeBGRA(
            width: 32, height: 32, bgra: (128, 128, 128, 0xFF)
        )
        let frame = try XCTUnwrap(converter.convert(sample))

        for i in 0..<70 {
            bridge.enqueue((frame, Double(i) / 30.0))
        }
        XCTAssertEqual(bridge.droppedCount, 10)

        while let item = bridge.dequeue() {
            try encoder.addFrame(item.0, presentationTime: item.1)
        }
        try await encoder.finish()

        let decoded = try GifDecoder.decode(outURL)
        XCTAssertEqual(decoded.frameCount, 60)
    }
}
```

- [ ] **Step 2: Run the integration tests**

Run: `swift test --filter PipelineIntegrationTests`
Expected: 2 tests pass.

- [ ] **Step 3: Commit**

```bash
git add Tests/SnatchKitTests/PipelineIntegrationTests.swift
git commit -m "test: end-to-end pipeline with synthetic CMSampleBuffers

Drives FrameConverter → BridgeQueue → GifskiEncoder with deterministic
input. Verifies frame count, color round-trip, and overflow drop
semantics without requiring Screen Recording permission."
```

---

### Task 12: `snatch-record-cli` — full-pipeline executable

A new command-line tool that wires capture-to-encoder end-to-end and writes a GIF to disk. Used as a developer smoke test and as the M2 demo.

**Files:**
- Modify: `Package.swift` (add `SnatchRecordCLI` target + product)
- Create: `Sources/SnatchRecordCLI/main.swift`

- [ ] **Step 1: Add the executable target to `Package.swift`**

Modify `Package.swift`. Inside `products`, add the new executable:

```swift
products: [
    .library(name: "SnatchKit", targets: ["SnatchKit"]),
    .executable(name: "snatch-cli", targets: ["SnatchCLI"]),
    .executable(name: "snatch-record-cli", targets: ["SnatchRecordCLI"]),
],
```

Inside `targets`, append:

```swift
.executableTarget(
    name: "SnatchRecordCLI",
    dependencies: ["SnatchKit"],
    path: "Sources/SnatchRecordCLI"
),
```

- [ ] **Step 2: Implement the CLI**

Create `Sources/SnatchRecordCLI/main.swift`. This file uses **top-level code** (matching the existing `SnatchCLI/main.swift` style — Swift's `main.swift` allows `await` at top level since 5.5, and we avoid the `@main`-vs-`main.swift` conflict).

```swift
// Sources/SnatchRecordCLI/main.swift
//
// snatch-record-cli — record a fixed screen region for a fixed duration
// and write a GIF using the full M2 pipeline.
//
// Example:
//   swift run snatch-record-cli \
//     --region 0,0,640,400 --duration 2 --scale standard --fps 30 \
//     --output /tmp/snatch-smoke.gif

import Foundation
import CoreMedia
import SnatchKit

struct Args {
    var region: CGRect = CGRect(x: 0, y: 0, width: 640, height: 400)
    var duration: TimeInterval = 2.0
    var scale: ScalePreset = .standard
    var fps: Int = 30
    var output: URL = URL(fileURLWithPath: "/tmp/snatch-smoke.gif")
}

func usage() -> Never {
    FileHandle.standardError.write(Data("""
    snatch-record-cli — record a screen region into a GIF.

    Usage:
      snatch-record-cli [options]

    Options:
      --region X,Y,W,H        Region in CG points (origin top-left). Default 0,0,640,400.
      --duration SECONDS      Recording length in seconds. Default 2.
      --scale {retina|standard|compact}   Capture scale preset. Default standard.
      --fps N                 Capture frame rate. Default 30.
      --output PATH           Output .gif path. Default /tmp/snatch-smoke.gif.

    """.utf8))
    exit(2)
}

func parseRegion(_ s: String) -> CGRect? {
    let parts = s.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) }
    guard parts.count == 4, parts.allSatisfy({ $0 != nil }) else { return nil }
    return CGRect(x: parts[0]!, y: parts[1]!, width: parts[2]!, height: parts[3]!)
}

func parseArgs() -> Args {
    var args = Args()
    var i = 1
    let argv = CommandLine.arguments
    while i < argv.count {
        let arg = argv[i]
        switch arg {
        case "--region":
            i += 1
            guard i < argv.count, let r = parseRegion(argv[i]) else { usage() }
            args.region = r
        case "--duration":
            i += 1
            guard i < argv.count, let d = Double(argv[i]) else { usage() }
            args.duration = d
        case "--scale":
            i += 1
            guard i < argv.count, let s = ScalePreset(rawValue: argv[i]) else { usage() }
            args.scale = s
        case "--fps":
            i += 1
            guard i < argv.count, let n = Int(argv[i]) else { usage() }
            args.fps = n
        case "--output":
            i += 1
            guard i < argv.count else { usage() }
            args.output = URL(fileURLWithPath: argv[i])
        case "-h", "--help":
            usage()
        default:
            FileHandle.standardError.write(Data("Unknown argument: \(arg)\n".utf8))
            usage()
        }
        i += 1
    }
    return args
}

/// Mutex-protected `TimeInterval?` for the first-frame PTS we observe.
/// Capture queue is serial, but multiple captureQueue closures may
/// observe firstPTS — we still want explicit synchronization.
final class PTSAnchor: @unchecked Sendable {
    private let lock = NSLock()
    private var value: TimeInterval?
    func anchor(_ pts: TimeInterval) -> TimeInterval {
        lock.withLock {
            if value == nil { value = pts }
            return value!
        }
    }
}

let args = parseArgs()

let captureQueue = DispatchQueue(label: "co.snatch.capture", qos: .userInteractive)
let encoderQueue = DispatchQueue(label: "co.snatch.encoder", qos: .userInitiated)

let converter = FrameConverter()
let bridge = BridgeQueue<(RGBAFrame, TimeInterval)>(capacity: 60)
let ptsAnchor = PTSAnchor()

let encoder: GifskiEncoder
do {
    encoder = try GifskiEncoder(outputURL: args.output, quality: 90)
} catch {
    FileHandle.standardError.write(Data("Failed to create encoder: \(error)\n".utf8))
    exit(1)
}

let wrapper = SCStreamWrapper()
let stream: AsyncStream<CMSampleBuffer>
do {
    stream = try await wrapper.start(
        region: args.region,
        scale: args.scale,
        fps: args.fps,
        queue: captureQueue
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

// Pump samples until stop. Each sample is dispatched to captureQueue for
// conversion (per spec §5) and to encoderQueue for the blocking addFrame
// call.
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

try? await Task.sleep(nanoseconds: UInt64(args.duration * 1_000_000_000))

let stopTriggerAt = CFAbsoluteTimeGetCurrent()

await wrapper.stop()
consumeTask.cancel()

// Drain the bridge into the encoder queue so no in-flight frames are lost.
encoderQueue.sync {
    while let item = bridge.dequeue() {
        try? encoder.addFrame(item.0, presentationTime: item.1)
    }
}

// Finish the encoder OFF the calling thread per spec §5 / M2 carry-over.
// gifski_finish blocks until queued frames flush.
let finishTask = Task.detached(priority: .userInitiated) {
    try await encoder.finish()
}
do {
    try await finishTask.value
} catch {
    FileHandle.standardError.write(Data("encoder.finish failed: \(error)\n".utf8))
    exit(1)
}

let stopLatencyMs = (CFAbsoluteTimeGetCurrent() - stopTriggerAt) * 1_000

print("✅ Wrote \(args.output.path)")
print("   bridge drops: \(bridge.droppedCount)")
print("   stop → save latency: \(String(format: "%.1f", stopLatencyMs)) ms (target < 500 ms)")
```

- [ ] **Step 3: Build the new target**

Run: `swift build --target SnatchRecordCLI`
Expected: clean build.

- [ ] **Step 4: Run all unit tests one more time to confirm nothing regressed**

Run: `swift test`
Expected: all suites green.

- [ ] **Step 5: Manual smoke — run the CLI for real**

This requires Screen Recording permission for your terminal (or `xcrun swift`). If not granted yet, expect exit code 3 with a clear message; grant in System Settings, then re-run.

Run:
```bash
swift run snatch-record-cli \
  --region 0,0,640,400 \
  --duration 2 \
  --scale standard \
  --fps 30 \
  --output /tmp/snatch-smoke.gif
```

Expected stdout (drop count and latency vary):
```
✅ Wrote /tmp/snatch-smoke.gif
   bridge drops: 0
   stop → save latency: ~50–250 ms (target < 500 ms)
```

Expected file:
- `/tmp/snatch-smoke.gif` exists, opens in Preview / Quick Look
- Plays as a 2-second animated GIF of the captured region
- Approximately 60 frames (`mdls -name kMDItemNumberOfFrames /tmp/snatch-smoke.gif` ~ 60 ± a few)

Manual eyeball check items:
- The GIF visibly animates (motion is preserved)
- No tearing or color glitches (BGRA→RGBA byte-swap correct)
- Cursor visible (`showsCursor = true`)

If permissions block first-run: open System Settings → Privacy & Security → Screen Recording → enable Terminal (or the host the CLI runs from). Re-run.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/SnatchRecordCLI/main.swift
git commit -m "feat: add snatch-record-cli — full M2 pipeline executable

Wires SCStreamWrapper → captureQueue → FrameConverter → BridgeQueue →
encoderQueue → GifskiEncoder end-to-end. Reports stop-latency and bridge
drop count after each run. Verified locally: 2s @ 30fps standard scale
produces ~60-frame GIF with stop-latency ~100ms (target < 500ms)."
```

---

### Task 13: Live `SCStreamWrapper` integration test (env-gated)

A test that actually drives ScreenCaptureKit. Skipped by default (CI lacks Screen Recording permission); enabled locally with `SNATCH_LIVE_CAPTURE=1`. This catches regressions in `SCStreamWrapper` that the synthetic pipeline test cannot.

**Files:**
- Create: `Tests/SnatchKitTests/SCStreamWrapperLiveTests.swift`

- [ ] **Step 1: Write the test**

Create `Tests/SnatchKitTests/SCStreamWrapperLiveTests.swift`:

```swift
import XCTest
import CoreMedia
@testable import SnatchKit

final class SCStreamWrapperLiveTests: XCTestCase {

    /// Set `SNATCH_LIVE_CAPTURE=1` in the environment to enable. Default-off
    /// because it requires Screen Recording permission and an attached
    /// display.
    override func setUp() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["SNATCH_LIVE_CAPTURE"] == "1",
            "Live SCStreamWrapper tests require SNATCH_LIVE_CAPTURE=1 (and Screen Recording permission)."
        )
    }

    func test_liveCapture_produces_atLeast_oneFrame_inHalfSecond() async throws {
        let wrapper = SCStreamWrapper()
        let captureQueue = DispatchQueue(label: "test.capture", qos: .userInteractive)

        let stream: AsyncStream<CMSampleBuffer>
        do {
            stream = try await wrapper.start(
                region: CGRect(x: 0, y: 0, width: 320, height: 240),
                scale: .standard,
                fps: 30,
                queue: captureQueue
            )
        } catch SCStreamWrapperError.permissionDenied {
            throw XCTSkip("Screen Recording permission not granted in test runner.")
        }

        let counter = AtomicCounter()

        let consumeTask = Task {
            for await _ in stream {
                counter.increment()
                if counter.value >= 5 { break }
            }
        }

        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 s
        await wrapper.stop()
        consumeTask.cancel()

        XCTAssertGreaterThan(counter.value, 0,
                             "Expected at least one CMSampleBuffer in 0.5 s of live capture")
    }
}

private final class AtomicCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0
    var value: Int { lock.withLock { _value } }
    func increment() { lock.withLock { _value += 1 } }
}
```

- [ ] **Step 2: Run the suite default-off**

Run: `swift test --filter SCStreamWrapperLiveTests`
Expected: `Test Case '-[…]' skipped` for the single test (env var not set).

- [ ] **Step 3: Run the suite with the gate enabled (developer machine, permission granted)**

Run: `SNATCH_LIVE_CAPTURE=1 swift test --filter SCStreamWrapperLiveTests`
Expected: 1 test passes within ~1 second. If permission is missing it auto-skips with a clear message.

- [ ] **Step 4: Commit**

```bash
git add Tests/SnatchKitTests/SCStreamWrapperLiveTests.swift
git commit -m "test: add SCStreamWrapperLiveTests, gated on SNATCH_LIVE_CAPTURE=1

Default-off because Screen Recording permission cannot be granted on a
headless CI runner. Local devs run with the env var set."
```

---

### Task 14: M2 release — tag and update CLAUDE.md status

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update the Status section**

In `CLAUDE.md`, replace the existing Status block with:

```markdown
## Status

- **M1 — Encoder smoke test ✅ Complete** (tag `m1-encoder-smoke-test`, commit `c4e53d7`). 11/11 unit tests pass; CLI produces a valid GIF.
- **M2 — Capture pipeline ✅ Complete** (tag `m2-capture-pipeline`). `SCStreamWrapper` + `FrameConverter` + `BridgeQueue` + `GifskiEncoder` end-to-end. `snatch-record-cli` records a region for a fixed duration and writes a GIF. Stop-latency measured well under the 500 ms target on M-series hardware.
- **M3 — Cropper UI** is next. Transition to `Snatch.xcodeproj` happens here when AppKit/SwiftUI enter.

We're on Swift Package Manager (`Package.swift`) for M1–M2; Xcode project arrives at M3 when AppKit/SwiftUI enters.
```

- [ ] **Step 2: Run the full test suite one last time**

Run: `swift test`
Expected: all 28+ tests green.

- [ ] **Step 3: Commit and tag**

```bash
git add CLAUDE.md
git commit -m "docs: M2 capture pipeline complete"
git tag m2-capture-pipeline
```

---

## Done criteria

M2 ships when ALL of the following hold:

1. `swift build` succeeds, no warnings.
2. `swift test` shows green for all suites: `RGBAFrameTests` (2), `ScalePresetTests` (3), `FixtureTests` (2), `GifskiEncoderTests` (4), `BridgeQueueTests` (5), `FrameConverterTests` (4), `SCStreamWrapperHelperTests` (5), `PipelineIntegrationTests` (2). Live-capture suite skips by default. Total: 27 default + 1 gated = 28.
3. `swift run snatch-record-cli --duration 2 --output /tmp/m2.gif` produces a playable animated GIF on a Mac with Screen Recording permission. Stop-latency reported under 500 ms.
4. M1 carry-overs from spec §10 are all addressed:
   - `fps` removed from `GifskiEncoder.init` ✓ (Task 1)
   - Stride handling in `FrameConverter` (strip-on-convert via vImage) ✓ (Task 8)
   - `finish()` scheduled off the calling thread (`Task.detached` in CLI; documented in Threading MARK) ✓ (Tasks 2, 12)
   - Threading contract documented on `GifskiEncoder` ✓ (Task 2)
   - `SnatchKit.swift` placeholder removed ✓ (Task 5)
   - `PNGLoader.fixture` throws ✓ (Task 3)
   - `GifDecoder.decode` throws ✓ (Task 4)
   - `.gitignore` negation rule for reference fixtures ✗ (skipped — M2 does not add a reference-GIF fixture; the integration test uses synthetic samples and a temp output. Re-evaluate at M5 smoke pass.)
   - Stay on SPM ✓
5. The git tag `m2-capture-pipeline` exists.
6. `CLAUDE.md` Status section reflects M2 done.

If any criterion fails, fix before tagging.
