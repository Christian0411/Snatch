import Foundation

/// Bounded FIFO queue for handing items from the capture queue to the encoder
/// queue. On overflow the OLDEST item is dropped and `droppedCount` is bumped.
///
/// Per spec §5, the production capacity is 60 (≈ 2 s @ 30 fps). The bridge is
/// the back-pressure relief valve — drops are graceful degradation, not a
/// fatal error.
///
/// Thread-safety: all operations are guarded by an internal NSLock. Suitable
/// for many-producer / one-consumer or one-producer / one-consumer use.
public final class BridgeQueue<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: [T] = []
    private var _droppedCount: Int = 0
    private var _isClosed: Bool = false
    /// Counts items available for dequeue. `signal()` once per enqueue and
    /// once per `close()` to wake any waiting dequeuer.
    private let availability = DispatchSemaphore(value: 0)
    public let capacity: Int

    public init(capacity: Int) {
        self.capacity = max(0, capacity)
        self.buffer.reserveCapacity(self.capacity)
    }

    /// Number of items dropped due to overflow since construction.
    public var droppedCount: Int {
        lock.withLock { _droppedCount }
    }

    /// Snapshot the current item count.
    public var count: Int {
        lock.withLock { buffer.count }
    }

    /// Whether the queue has been closed.
    public var isClosed: Bool {
        lock.withLock { _isClosed }
    }

    /// Push an item. If the buffer is at capacity, the oldest is removed
    /// (FIFO eviction) and `droppedCount` is incremented.
    /// Returns the new dropped-count *after* the call (useful for one-shot logging).
    @discardableResult
    public func enqueue(_ item: T) -> Int {
        let shouldSignal = lock.withLock { () -> Bool in
            if _isClosed { return false }
            if capacity == 0 {
                _droppedCount += 1
                return false
            }
            if buffer.count >= capacity {
                buffer.removeFirst()
                _droppedCount += 1
            }
            buffer.append(item)
            return true
        }
        if shouldSignal { availability.signal() }
        return droppedCount
    }

    /// Pop the oldest item, or nil if empty.
    public func dequeue() -> T? {
        lock.withLock {
            buffer.isEmpty ? nil : buffer.removeFirst()
        }
    }

    /// Drain everything in FIFO order. Useful at stop time before calling
    /// `GifskiEncoder.finish()`.
    public func drain() -> [T] {
        lock.withLock {
            let out = buffer
            buffer.removeAll(keepingCapacity: true)
            return out
        }
    }

    /// Blocks until an item is available, or returns nil after `close()`
    /// has been called and the queue has drained. Subsequent calls after
    /// nil also return nil immediately (cascade).
    public func dequeueBlocking() -> T? {
        availability.wait()
        var result: T?
        var shouldCascadeSignal = false
        lock.withLock {
            if !buffer.isEmpty {
                result = buffer.removeFirst()
            } else if _isClosed {
                shouldCascadeSignal = true
            }
        }
        if shouldCascadeSignal { availability.signal() }
        return result
    }

    /// Marks the queue closed. Any blocked dequeuers wake; subsequent
    /// `enqueue` calls are silently rejected. Items already in the buffer
    /// are still delivered by `dequeueBlocking` until the buffer drains.
    public func close() {
        let wasClosed = lock.withLock { () -> Bool in
            if _isClosed { return true }
            _isClosed = true
            return false
        }
        if !wasClosed { availability.signal() }
    }

    /// Empties the buffer without delivering items, and reclaims any
    /// semaphore credits the discarded items had posted. Use this on the
    /// cancel path where in-flight items must not reach the consumer.
    /// Typically followed by `close()` so any blocked dequeuer wakes
    /// promptly with nil.
    public func drainAndDiscard() {
        lock.withLock {
            let drained = buffer.count
            buffer.removeAll(keepingCapacity: true)
            // Reclaim semaphore credits posted by the now-discarded items
            // so a subsequent dequeueBlocking call won't unblock spuriously.
            for _ in 0..<drained {
                _ = availability.wait(timeout: .now())
            }
        }
    }
}
