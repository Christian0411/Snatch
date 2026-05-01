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
