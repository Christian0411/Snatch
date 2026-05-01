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
