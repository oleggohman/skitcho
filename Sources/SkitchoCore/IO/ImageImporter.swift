import CoreGraphics
import Foundation
import ImageIO

/// Errors thrown while importing a raster image.
public enum ImageImportError: Error, Equatable {
  /// The bytes are not a decodable image.
  case unreadable
  /// The image decodes but has no pixels.
  case zeroSize
  /// A side is longer than `ImageOps.maxSide` pixels (checked from the header, before decoding).
  case tooLarge
}

/// The single image-decoding path: decodes bytes, applies the EXIF orientation and converts to sRGB RGBA8.
public enum ImageImporter {
  /// Decodes image bytes (PNG, JPEG, TIFF, HEIC, ...) into an upright sRGB bitmap.
  public static func decodeImage(_ data: Data) throws -> CGImage {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0 else {
      throw ImageImportError.unreadable
    }
    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    let pixelWidth = (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
    let pixelHeight = (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
    guard pixelWidth > 0, pixelHeight > 0 else {
      // Missing properties mean the decoder cannot read the image at all; a decoded empty image is zero-sized.
      if properties == nil { throw ImageImportError.unreadable }
      throw ImageImportError.zeroSize
    }
    // Reject oversized images before the decoder allocates them (a tiny file can declare a huge size).
    guard pixelWidth <= ImageOps.maxSide, pixelHeight <= ImageOps.maxSide else { throw ImageImportError.tooLarge }
    // The thumbnail API applies the orientation transform; a max size of the long side keeps full resolution.
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: max(pixelWidth, pixelHeight),
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
      throw ImageImportError.unreadable
    }
    return try normalizedSRGB(image)
  }

  /// Draws `image` into an sRGB RGBA8 premultiplied bitmap.
  static func normalizedSRGB(_ image: CGImage) throws -> CGImage {
    guard image.width > 0, image.height > 0 else { throw ImageImportError.zeroSize }
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { throw ImageImportError.unreadable }
    context.interpolationQuality = .none
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    guard let result = context.makeImage() else { throw ImageImportError.unreadable }
    return result
  }

  /// A document whose base image is the decoded bytes.
  public static func load(data: Data) throws -> Document {
    Document(baseImage: try decodeImage(data))
  }

  public static func load(url: URL) throws -> Document {
    guard let data = try? Data(contentsOf: url) else { throw ImageImportError.unreadable }
    return try load(data: data)
  }

  /// An empty 800x600 white canvas.
  public static func blank() -> Document {
    Document.blank(size: CGSize(width: 800, height: 600), background: .white)
  }
}
