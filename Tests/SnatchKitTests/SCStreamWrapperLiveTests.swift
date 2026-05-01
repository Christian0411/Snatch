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
