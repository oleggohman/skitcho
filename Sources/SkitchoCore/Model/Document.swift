import CoreGraphics
import Foundation

/// Placeholder element type; the full model arrives with the document model task.
public struct Element: Sendable, Equatable, Codable {
  public var id: UUID

  public init(id: UUID = UUID()) {
    self.id = id
  }
}

/// Minimal Sendable document value: a base bitmap, its canvas size and the annotation elements.
/// Document space is top-left origin, y-down, in image pixels.
public struct Document: Sendable {
  public var baseImage: CGImage
  public var canvasSize: CGSize
  public var elements: [Element]

  public init(baseImage: CGImage, canvasSize: CGSize? = nil, elements: [Element] = []) {
    self.baseImage = baseImage
    self.canvasSize = canvasSize ?? CGSize(width: baseImage.width, height: baseImage.height)
    self.elements = elements
  }

  /// A blank white canvas.
  public static func blank(size: CGSize = CGSize(width: 800, height: 600)) -> Document {
    let width = max(1, Int(size.width))
    let height = max(1, Int(size.height))
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let info = CGImageAlphaInfo.premultipliedLast.rawValue
    let context = CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info)!
    context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return Document(baseImage: context.makeImage()!)
  }
}
