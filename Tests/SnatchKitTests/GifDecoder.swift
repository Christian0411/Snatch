// Tests/SnatchKitTests/GifDecoder.swift
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct DecodedGif {
    let frameCount: Int
    let width: Int
    let height: Int
    /// (R, G, B) of pixel (x, y) in the given frame, after dequantization.
    let pixelAt: (_ frame: Int, _ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8)?
}

enum GifDecoderError: Error {
    case sourceCreationFailed
    case typeMismatch
    case frameOutOfRange
}

enum GifDecoder {
    static func decode(_ url: URL) throws -> DecodedGif {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw GifDecoderError.sourceCreationFailed
        }
        let type = CGImageSourceGetType(source) as String?
        guard type == (UTType.gif.identifier as String) else {
            throw GifDecoderError.typeMismatch
        }

        let frameCount = CGImageSourceGetCount(source)
        precondition(frameCount > 0)

        let firstImage = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        let width = firstImage.width
        let height = firstImage.height

        // Pre-decode every frame's pixel data into a flat array of (R, G, B) tuples
        // so the caller can index by (frame, x, y).
        var rasters: [Data] = []
        rasters.reserveCapacity(frameCount)
        for i in 0..<frameCount {
            guard let cg = CGImageSourceCreateImageAtIndex(source, i, nil) else {
                throw GifDecoderError.frameOutOfRange
            }
            let bytesPerRow = width * 4
            var bytes = Data(count: bytesPerRow * height)
            bytes.withUnsafeMutableBytes { buf in
                let ctx = CGContext(
                    data: buf.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )!
                ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            }
            rasters.append(bytes)
        }

        return DecodedGif(
            frameCount: frameCount,
            width: width,
            height: height,
            pixelAt: { frame, x, y in
                guard frame >= 0, frame < rasters.count,
                      x >= 0, x < width, y >= 0, y < height else { return nil }
                let base = (y * width + x) * 4
                let raster = rasters[frame]
                return (raster[base], raster[base + 1], raster[base + 2])
            }
        )
    }
}
