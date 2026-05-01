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
