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

    /// Push an item. If the buffer is at capacity, the oldest is removed
    /// (FIFO eviction) and `droppedCount` is incremented.
    /// Returns the new dropped-count *after* the call (useful for one-shot logging).
    @discardableResult
    public func enqueue(_ item: T) -> Int {
        lock.withLock {
            if capacity == 0 {
                _droppedCount += 1
                return _droppedCount
            }
            if buffer.count >= capacity {
                buffer.removeFirst()
                _droppedCount += 1
            }
            buffer.append(item)
            return _droppedCount
        }
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
}
