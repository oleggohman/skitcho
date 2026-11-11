import CoreGraphics
import Foundation

/// Sendable document value: a base bitmap, the canvas it sits on and the annotation elements.
/// Document space is top-left origin, y-down, in image pixels of the canvas.
public struct Document: Sendable, Equatable {
  /// The file-format version written by this build.
  public static let currentVersion = 1

  public var baseImage: CGImage
  public var canvasSize: CGSize
  /// Where the base image's top-left corner sits on the canvas (non-zero after expanding the canvas).
  public var imageOrigin: CGPoint
  /// Fill shown where the canvas is not covered by the base image.
  public var background: AnnotationColor
  /// Z-order is array order: later elements draw on top.
  public var elements: [Element]
  public var version: Int

  public init(
    baseImage: CGImage,
    canvasSize: CGSize? = nil,
    imageOrigin: CGPoint = .zero,
    background: AnnotationColor = .white,
    elements: [Element] = [],
    version: Int = Document.currentVersion
  ) {
    self.baseImage = baseImage
    self.canvasSize = canvasSize ?? CGSize(width: baseImage.width, height: baseImage.height)
    self.imageOrigin = imageOrigin
    self.background = background
    self.elements = elements
    self.version = version
  }

  /// Images are compared by identity plus size (pixel contents are never compared); other fields by value.
  public static func == (lhs: Document, rhs: Document) -> Bool {
    lhs.baseImage === rhs.baseImage
      && lhs.baseImage.width == rhs.baseImage.width && lhs.baseImage.height == rhs.baseImage.height
      && lhs.canvasSize == rhs.canvasSize && lhs.imageOrigin == rhs.imageOrigin
      && lhs.background == rhs.background && lhs.elements == rhs.elements && lhs.version == rhs.version
  }

  /// A blank canvas filled with `background`.
  public static func blank(
    size: CGSize = CGSize(width: 800, height: 600), background: AnnotationColor = .white
  ) -> Document {
    let width = max(1, Int(size.width))
    let height = max(1, Int(size.height))
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let info = CGImageAlphaInfo.premultipliedLast.rawValue
    let context = CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info)!
    context.setFillColor(background.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return Document(baseImage: context.makeImage()!, background: background)
  }
}
