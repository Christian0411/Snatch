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
