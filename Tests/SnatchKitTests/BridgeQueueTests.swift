import XCTest
@testable import SnatchKit

final class BridgeQueueTests: XCTestCase {
    func test_enqueueAndDequeue_preservesFifoOrder() {
        let q = BridgeQueue<Int>(capacity: 4)
        q.enqueue(1)
        q.enqueue(2)
        q.enqueue(3)

        XCTAssertEqual(q.dequeue(), 1)
        XCTAssertEqual(q.dequeue(), 2)
        XCTAssertEqual(q.dequeue(), 3)
        XCTAssertNil(q.dequeue())
    }

    func test_underCapacity_dropCountIsZero() {
        let q = BridgeQueue<Int>(capacity: 4)
        q.enqueue(1)
        q.enqueue(2)
        XCTAssertEqual(q.droppedCount, 0)
    }

    func test_overCapacity_dropsOldest_incrementsCounter() {
        let q = BridgeQueue<Int>(capacity: 3)
        q.enqueue(1)
        q.enqueue(2)
        q.enqueue(3)
        q.enqueue(4) // overflow — drops 1
        q.enqueue(5) // overflow — drops 2

        XCTAssertEqual(q.droppedCount, 2)
        XCTAssertEqual(q.dequeue(), 3)
        XCTAssertEqual(q.dequeue(), 4)
        XCTAssertEqual(q.dequeue(), 5)
        XCTAssertNil(q.dequeue())
    }

    func test_capacityZero_everyEnqueueDrops() {
        let q = BridgeQueue<Int>(capacity: 0)
        q.enqueue(1)
        q.enqueue(2)
        XCTAssertEqual(q.droppedCount, 2)
        XCTAssertNil(q.dequeue())
    }

    func test_concurrent_producersAndConsumer_doNotCrash() {
        let q = BridgeQueue<Int>(capacity: 32)
        let producers = DispatchQueue(label: "test.producers", attributes: .concurrent)
        let consumer = DispatchQueue(label: "test.consumer")
        let group = DispatchGroup()

        for i in 0..<1_000 {
            group.enter()
            producers.async {
                q.enqueue(i)
                group.leave()
            }
        }

        let consumed = NSMutableArray()
        let consumeTask = DispatchWorkItem {
            for _ in 0..<2_000 {
                if let v = q.dequeue() { consumed.add(v) }
            }
        }
        consumer.async(execute: consumeTask)

        group.wait()
        consumeTask.wait()
        // Soundness: never crashed. Drop count + consumed.count <= 1000.
        XCTAssertLessThanOrEqual(consumed.count + q.droppedCount, 1_000)
    }
}
