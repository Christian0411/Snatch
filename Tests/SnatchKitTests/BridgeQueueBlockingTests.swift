import XCTest
@testable import SnatchKit

final class BridgeQueueBlockingTests: XCTestCase {

    func test_dequeueBlocking_returnsItem_whenAlreadyAvailable() {
        let q = BridgeQueue<Int>(capacity: 4)
        q.enqueue(42)

        let result = q.dequeueBlocking()

        XCTAssertEqual(result, 42)
    }

    func test_dequeueBlocking_blocksUntilEnqueue() {
        let q = BridgeQueue<Int>(capacity: 4)
        let exp = expectation(description: "dequeueBlocking returns")

        DispatchQueue.global(qos: .userInitiated).async {
            let r = q.dequeueBlocking()
            XCTAssertEqual(r, 7)
            exp.fulfill()
        }

        // Enqueue from a different thread after a short delay — proves the
        // dequeueBlocking call was actually waiting.
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.05) {
            q.enqueue(7)
        }

        wait(for: [exp], timeout: 1.0)
    }

    func test_dequeueBlocking_returnsNil_afterClose() {
        let q = BridgeQueue<Int>(capacity: 4)
        let exp = expectation(description: "dequeueBlocking returns nil")

        DispatchQueue.global(qos: .userInitiated).async {
            let r = q.dequeueBlocking()
            XCTAssertNil(r)
            exp.fulfill()
        }

        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.05) {
            q.close()
        }

        wait(for: [exp], timeout: 1.0)
    }

    func test_dequeueBlocking_drainsRemainingItems_afterClose() {
        let q = BridgeQueue<Int>(capacity: 4)
        q.enqueue(1)
        q.enqueue(2)
        q.enqueue(3)
        q.close()

        XCTAssertEqual(q.dequeueBlocking(), 1)
        XCTAssertEqual(q.dequeueBlocking(), 2)
        XCTAssertEqual(q.dequeueBlocking(), 3)
        XCTAssertNil(q.dequeueBlocking())   // empty + closed
    }

    func test_drainAndDiscard_clearsItemsWithoutDelivering() {
        let q = BridgeQueue<Int>(capacity: 4)
        q.enqueue(10)
        q.enqueue(20)

        q.drainAndDiscard()

        XCTAssertEqual(q.count, 0)
        // After drainAndDiscard + close, dequeueBlocking returns nil immediately.
        q.close()
        XCTAssertNil(q.dequeueBlocking())
    }

    func test_enqueueAfterClose_isRejected_silently() {
        let q = BridgeQueue<Int>(capacity: 4)
        q.close()
        q.enqueue(99)

        // dequeueBlocking should return nil, not 99.
        XCTAssertNil(q.dequeueBlocking())
    }
}
