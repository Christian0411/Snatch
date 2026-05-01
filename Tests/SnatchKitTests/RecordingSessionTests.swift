import XCTest
import CoreGraphics
@testable import SnatchKit

final class RecordingSessionTests: XCTestCase {

    private var pipeline: FakeRecordingPipeline!
    private var regionStore: RegionStore!
    private var defaults: UserDefaults!
    private var suiteName: String!
    /// Fake clock; bumped by helper to simulate elapsed time.
    private var fakeNow: CFAbsoluteTime = 0

    override func setUp() {
        super.setUp()
        pipeline = FakeRecordingPipeline()
        suiteName = "co.snatch.tests.RecordingSession.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        regionStore = RegionStore(defaults: defaults)
        fakeNow = 1000.0
    }

    override func tearDown() {
        defaults?.removePersistentDomain(forName: suiteName)
        defaults = nil
        regionStore = nil
        pipeline = nil
        suiteName = nil
        super.tearDown()
    }

    @MainActor
    private func makeSession() -> RecordingSession {
        RecordingSession(
            pipeline: pipeline,
            regionStore: regionStore,
            clock: { [weak self] in self?.fakeNow ?? 0 }
        )
    }

    @MainActor
    func test_initialState_isIdle() {
        let session = makeSession()
        XCTAssertEqual(session.state, .idle)
    }

    @MainActor
    func test_start_fromIdle_transitionsToRecordingAndCallsPipeline() async throws {
        let session = makeSession()
        let region = CGRect(x: 10, y: 20, width: 300, height: 200)
        let url = URL(fileURLWithPath: "/tmp/m4-test.gif")

        try await session.start(
            region: region, scale: .standard, fps: 30,
            outputURL: url, excludingWindows: []
        )

        XCTAssertEqual(session.state, .recording)
        XCTAssertEqual(pipeline.startCalls.count, 1)
        let call = pipeline.startCalls[0]
        XCTAssertEqual(call.region, region)
        XCTAssertEqual(call.scale, .standard)
        XCTAssertEqual(call.fps, 30)
        XCTAssertEqual(call.outputURL, url)
        XCTAssertEqual(call.excludingWindowCount, 0)
    }

    @MainActor
    func test_start_persistsRegion() async throws {
        let session = makeSession()
        let region = CGRect(x: 7, y: 11, width: 320, height: 240)

        try await session.start(
            region: region, scale: .standard, fps: 30,
            outputURL: URL(fileURLWithPath: "/tmp/m4.gif"),
            excludingWindows: []
        )

        XCTAssertEqual(regionStore.lastRegion, region)
    }

    @MainActor
    func test_stop_fromRecording_transitionsToIdleAndReturnsResult() async throws {
        let session = makeSession()
        let outURL = URL(fileURLWithPath: "/tmp/m4-result.gif")
        let returnedURL = URL(fileURLWithPath: "/tmp/m4-actual.gif")
        pipeline.stopReturnURL = returnedURL
        pipeline.droppedFramesValue = 4

        try await session.start(
            region: CGRect(x: 0, y: 0, width: 100, height: 100),
            scale: .standard, fps: 30,
            outputURL: outURL, excludingWindows: []
        )
        XCTAssertEqual(session.state, .recording)

        // Advance the fake clock by 0.123 seconds between start-of-stop and end-of-stop
        let beforeStop = fakeNow
        // pipeline.stop runs synchronously in the fake — bump the clock with a closure injection
        // so RecordingSession's measurement covers the elapsed window. The session reads the
        // clock once at entry to stop() (T0) and once after pipeline.stop returns (T1).
        // The fake's stop() is fast, so we bump fakeNow by the gate to simulate elapsed time.
        // Simpler approach: stop the closure mid-flight via a one-shot stopGate-equivalent.
        // For now, bump fakeNow before calling stop and re-read after to keep the test honest.
        // (The session reads clock() at entry; we control fakeNow before that call.)
        fakeNow = beforeStop + 0.123

        let result = try await session.stop()

        XCTAssertEqual(session.state, .idle)
        XCTAssertEqual(result.outputURL, returnedURL)
        XCTAssertEqual(result.droppedFrames, 4)
        // stopLatencyMs measured from T0 (entry to stop()) to T1 (after pipeline.stop) — both
        // read fakeNow which doesn't change inside the synchronous fake stop, so we expect 0.
        // (We'll exercise non-zero latency in the live integration test in Task 12.)
        XCTAssertEqual(result.stopLatencyMs, 0.0, accuracy: 0.001)
    }

    @MainActor
    func test_stop_passesThroughPipelineDroppedFrames() async throws {
        let session = makeSession()
        pipeline.droppedFramesValue = 17

        try await session.start(
            region: CGRect(x: 0, y: 0, width: 50, height: 50),
            scale: .standard, fps: 30,
            outputURL: URL(fileURLWithPath: "/tmp/m4.gif"),
            excludingWindows: []
        )
        let result = try await session.stop()

        XCTAssertEqual(result.droppedFrames, 17)
    }

    @MainActor
    func test_cancel_fromIdle_isNoOp() async {
        let session = makeSession()
        XCTAssertEqual(session.state, .idle)

        await session.cancel()

        XCTAssertEqual(session.state, .idle)
        XCTAssertEqual(pipeline.cancelCallCount, 0,
                       "pipeline.cancel must not be called when session is idle")
        XCTAssertEqual(pipeline.startCalls.count, 0)
        XCTAssertEqual(pipeline.stopCallCount, 0)
    }

    @MainActor
    func test_cancel_fromRecording_transitionsToIdleAndCallsPipelineCancel() async throws {
        let session = makeSession()
        try await session.start(
            region: CGRect(x: 0, y: 0, width: 100, height: 100),
            scale: .standard, fps: 30,
            outputURL: URL(fileURLWithPath: "/tmp/m4.gif"),
            excludingWindows: []
        )
        XCTAssertEqual(session.state, .recording)

        await session.cancel()

        XCTAssertEqual(session.state, .idle)
        XCTAssertEqual(pipeline.cancelCallCount, 1)
    }

    @MainActor
    func test_cancel_fromRecording_doesNotCallPipelineStop() async throws {
        let session = makeSession()
        try await session.start(
            region: CGRect(x: 0, y: 0, width: 100, height: 100),
            scale: .standard, fps: 30,
            outputURL: URL(fileURLWithPath: "/tmp/m4.gif"),
            excludingWindows: []
        )

        await session.cancel()

        XCTAssertEqual(pipeline.stopCallCount, 0,
                       "cancel must use pipeline.cancel, not pipeline.stop")
    }
}
