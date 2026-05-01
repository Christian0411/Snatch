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
