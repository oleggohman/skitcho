import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ExportError: Error, Equatable {
  case invalidScale
  case encodingFailed
}

public enum ExportFormat: Sendable, Equatable {
  case png
  /// Quality in 0...1.
  case jpeg(quality: Double)
  case tiff

  var type: UTType {
    switch self {
    case .png: .png
    case .jpeg: .jpeg
    case .tiff: .tiff
    }
  }
}

/// Encodes the flattened document (or any bitmap) with `CGImageDestination`.
public enum Exporter {
  /// Flattens `document` at `scale` (1 or 2) and encodes it.
  public static func data(_ document: Document, format: ExportFormat, scale: Int = 1) throws -> Data {
    guard scale == 1 || scale == 2 else { throw ExportError.invalidScale }
    let image = try DocumentRenderer.flatten(document, scale: Double(scale))
    return try encode(image, format: format)
  }

  /// Encodes a bitmap. JPEG has no alpha, so the image is composited over white first.
  public static func encode(_ image: CGImage, format: ExportFormat) throws -> Data {
    var source = image
    var properties: [CFString: Any] = [:]
    if case .jpeg(let quality) = format {
      source = try opaque(image)
      properties[kCGImageDestinationLossyCompressionQuality] = min(1, max(0, quality))
    }
    let data = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(data, format.type.identifier as CFString, 1, nil) else {
      throw ExportError.encodingFailed
    }
    CGImageDestinationAddImage(dest, source, properties as CFDictionary)
    guard CGImageDestinationFinalize(dest) else { throw ExportError.encodingFailed }
    return data as Data
  }

  private static func opaque(_ image: CGImage) throws -> CGImage {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { throw ExportError.encodingFailed }
    let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
    context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    context.fill(rect)
    context.draw(image, in: rect)
    guard let result = context.makeImage() else { throw ExportError.encodingFailed }
    return result
  }
}
