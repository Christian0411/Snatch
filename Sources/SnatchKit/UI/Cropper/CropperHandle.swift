import Foundation

/// One of the 9 grab points on a cropper rectangle: the 8 resize handles
/// arranged around the perimeter, plus `.body` meaning "the user grabbed
/// inside the rect to move it whole-cloth".
public enum CropperHandle: Hashable, Sendable, CaseIterable {
    case topLeft, top, topRight
    case left,        right
    case bottomLeft, bottom, bottomRight
    case body

    /// The 8 resize cases in clockwise-ish order (corners + edges).
    /// `body` is intentionally excluded — these are the cases that map to
    /// a rendered grip in the UI and to a directional resize behavior in
    /// `CropperGeometry.resize`.
    public static let resizeCases: [CropperHandle] = [
        .topLeft, .top, .topRight,
        .left,           .right,
        .bottomLeft, .bottom, .bottomRight,
    ]
}
