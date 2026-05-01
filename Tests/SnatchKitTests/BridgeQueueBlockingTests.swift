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
        let waiterEntered = DispatchSemaphore(value: 0)
        let exp = expectation(description: "dequeueBlocking returns")

        DispatchQueue.global(qos: .userInitiated).async {
            waiterEntered.signal()
            let r = q.dequeueBlocking()   // must block until enqueue below
            XCTAssertEqual(r, 7)
            exp.fulfill()
        }

        // Wait for the dequeuer to enter (and presumably start waiting on
        // the queue). This is the rendezvous — proves the dequeuer hadn't
        // returned before the enqueue happens.
        waiterEntered.wait()
        // Tiny sleep so the dequeuer reaches `availability.wait()` after
        // signalling waiterEntered. 1ms is enough; this is the only timing
        // assumption left, and it's a reverse-direction race (the test
        // would still fail correctly without it, just less reliably).
        Thread.sleep(forTimeInterval: 0.001)

        q.enqueue(7)
        wait(for: [exp], timeout: 1.0)
    }

    func test_dequeueBlocking_returnsNil_afterClose() {
        let q = BridgeQueue<Int>(capacity: 4)
        let waiterEntered = DispatchSemaphore(value: 0)
        let exp = expectation(description: "dequeueBlocking returns nil")

        DispatchQueue.global(qos: .userInitiated).async {
            waiterEntered.signal()
            let r = q.dequeueBlocking()
            XCTAssertNil(r)
            exp.fulfill()
        }

        waiterEntered.wait()
        Thread.sleep(forTimeInterval: 0.001)

        q.close()
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

    func test_close_wakesMultipleBlockedDequeuers() {
        let q = BridgeQueue<Int>(capacity: 4)
        let waitersEntered = DispatchSemaphore(value: 0)
        let exp1 = expectation(description: "waiter 1 wakes with nil")
        let exp2 = expectation(description: "waiter 2 wakes with nil")
        let exp3 = expectation(description: "waiter 3 wakes with nil")

        for exp in [exp1, exp2, exp3] {
            DispatchQueue.global(qos: .userInitiated).async {
                waitersEntered.signal()
                XCTAssertNil(q.dequeueBlocking())
                exp.fulfill()
            }
        }

        // Rendezvous: wait for all three waiters to enter their async block
        // before issuing close(). Three signals total.
        for _ in 0..<3 { waitersEntered.wait() }
        Thread.sleep(forTimeInterval: 0.005)  // let them reach availability.wait()

        q.close()

        wait(for: [exp1, exp2, exp3], timeout: 2.0)
    }
}
