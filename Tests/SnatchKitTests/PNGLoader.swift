// Tests/SnatchKitTests/PNGLoader.swift
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import SnatchKit

enum PNGLoaderError: Error {
    case sourceCreationFailed
    case imageCreationFailed
    case bitmapContextCreationFailed
}

enum PNGLoader {
    /// Decode a PNG file at `url` into a tightly packed RGBA8 `RGBAFrame`.
    static func load(_ url: URL) throws -> RGBAFrame {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw PNGLoaderError.sourceCreationFailed
        }
        guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw PNGLoaderError.imageCreationFailed
        }

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = width * 4
        var bytes = Data(count: bytesPerRow * height)

        let result = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard result else { throw PNGLoaderError.bitmapContextCreationFailed }

        return RGBAFrame(bytes: bytes, width: width, height: height)
    }

    /// Resolve a fixture by basename (e.g., "frame-red") under Tests/SnatchKitTests/Fixtures.
    static func fixture(_ basename: String) throws -> RGBAFrame {
        let url = Bundle.module.url(forResource: basename, withExtension: "png", subdirectory: "Fixtures")!
        return try load(url)
    }
}
