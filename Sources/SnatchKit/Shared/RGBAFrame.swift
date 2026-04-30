import Foundation

/// One tightly packed RGBA8 frame. No row padding.
public struct RGBAFrame: Sendable, Equatable {
    public let bytes: Data
    public let width: Int
    public let height: Int

    public init(bytes: Data, width: Int, height: Int) {
        self.bytes = bytes
        self.width = width
        self.height = height
    }
}
