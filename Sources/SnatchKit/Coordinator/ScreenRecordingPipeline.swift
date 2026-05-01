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
                let dropped = bridge.enqueue((frame, pts - base))
                if dropped > 0 && dropped % 10 == 0 {
                    Log.capture.debug("bridge drops at \(dropped, privacy: .public)")
                }
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
