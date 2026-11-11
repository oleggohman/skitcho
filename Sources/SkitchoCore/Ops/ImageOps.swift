import CoreGraphics
import Foundation

/// Failures of the raster image operations.
public enum ImageOpError: Error, Equatable {
  /// The result would have a side longer than `ImageOps.maxSide` pixels.
  case tooLarge
  /// The rectangle is empty, not finite or does not overlap the image/canvas.
  case invalidRect
  /// A non-rectangle argument is unusable (non-positive scale, block size or amount).
  case invalidArgument
  /// A bitmap context could not be created.
  case renderFailed
}

/// The canvas edge that `ImageOps.expandCanvas` grows.
public enum CanvasEdge: Sendable, Equatable, CaseIterable {
  case top, left, bottom, right
}

/// The axis along which `ImageOps.flip` mirrors the document.
public enum FlipAxis: Sendable, Equatable {
  /// Mirror left to right.
  case horizontal
  /// Mirror top to bottom.
  case vertical
}

/// Raster operations on a `Document`. Each returns a new document: the bitmap is changed and every element's
/// geometry follows. Annotation sizes (`strokeWidth`, `fontSize`) stay frozen for crop, expand, rotate and
/// flip, and are multiplied by `resize`. All coordinates are document space (top-left origin, y-down).
public enum ImageOps {
  /// Longest allowed side of a result, in pixels.
  public static let maxSide = 16384

  // MARK: Pixelate

  /// Replaces `rect` (document space, clipped to the base image) with block averages of `blockSize` pixels.
  /// Blocks are aligned to the clipped rect's top-left corner; edge blocks average only their own pixels.
  /// Elements are untouched: annotations stay crisp on top of the pixelated bitmap.
  public static func pixelate(_ document: Document, rect: CGRect, blockSize: Int) throws -> Document {
    guard blockSize >= 1 else { throw ImageOpError.invalidArgument }
    let image = document.baseImage
    let local = rect.offsetBy(dx: -document.imageOrigin.x, dy: -document.imageOrigin.y)
    let region = try pixelRegion(of: local, within: image.width, image.height)

    let context = try makeContext(width: image.width, height: image.height)
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else { throw ImageOpError.renderFailed }
    let stride = context.bytesPerRow

    var blockY = region.minY
    while blockY < region.maxY {
      let blockMaxY = min(blockY + blockSize, region.maxY)
      var blockX = region.minX
      while blockX < region.maxX {
        let blockMaxX = min(blockX + blockSize, region.maxX)
        let count = (blockMaxX - blockX) * (blockMaxY - blockY)
        var sums = [Int](repeating: 0, count: 4)
        for y in blockY..<blockMaxY {
          for x in blockX..<blockMaxX {
            let i = y * stride + x * 4
            for channel in 0..<4 { sums[channel] += Int(data[i + channel]) }
          }
        }
        let averages = sums.map { UInt8(($0 + count / 2) / count) }
        for y in blockY..<blockMaxY {
          for x in blockX..<blockMaxX {
            let i = y * stride + x * 4
            for channel in 0..<4 { data[i + channel] = averages[channel] }
          }
        }
        blockX = blockMaxX
      }
      blockY = blockMaxY
    }
    guard let result = context.makeImage() else { throw ImageOpError.renderFailed }
    var copy = document
    copy.baseImage = result
    return copy
  }

  // MARK: Crop

  /// Crops the canvas to `rect` (document space, clipped to the canvas and rounded outward to whole pixels).
  /// The background is baked into the bitmap; elements move by `-rect.origin`.
  public static func crop(_ document: Document, rect: CGRect) throws -> Document {
    let canvas = try canvasPixels(of: document)
    let region = try pixelRegion(of: rect, within: canvas.width, canvas.height)
    let flat = try flattened(document)
    let box = CGRect(x: region.minX, y: region.minY, width: region.width, height: region.height)
    guard let cropped = flat.cropping(to: box) else { throw ImageOpError.invalidRect }
    let delta = CGPoint(x: -Double(region.minX), y: -Double(region.minY))
    return rebuilt(
      document, image: cropped, elements: document.elements.map { $0.translated(by: delta) })
  }

  // MARK: Resize

  /// Scales the canvas by `scale` (> 0). Element geometry and the frozen sizes are multiplied by `scale`.
  public static func resize(_ document: Document, scale: Double) throws -> Document {
    guard scale.isFinite, scale > 0 else { throw ImageOpError.invalidArgument }
    let canvas = try canvasPixels(of: document)
    let width = (Double(canvas.width) * scale).rounded()
    let height = (Double(canvas.height) * scale).rounded()
    guard width <= Double(maxSide), height <= Double(maxSide) else { throw ImageOpError.tooLarge }
    let newWidth = max(1, Int(width))
    let newHeight = max(1, Int(height))

    let flat = try flattened(document)
    let context = try makeContext(width: newWidth, height: newHeight)
    context.interpolationQuality = .high
    context.draw(flat, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
    guard let result = context.makeImage() else { throw ImageOpError.renderFailed }
    let elements = document.elements.map { element -> Element in
      var scaled = element.scaled(by: scale, about: .zero)
      scaled.style = element.style.scaled(by: scale)
      return scaled
    }
    return rebuilt(document, image: result, elements: elements)
  }

  // MARK: Expand canvas

  /// Grows the canvas by `amount` pixels on `edge`, filled with the background color. The bitmap itself is
  /// untouched (`imageOrigin` moves); elements shift when the new space is added above or to the left.
  public static func expandCanvas(_ document: Document, edge: CanvasEdge, amount: Int) throws -> Document {
    guard amount >= 1 else { throw ImageOpError.invalidArgument }
    let canvas = try canvasPixels(of: document)
    let horizontal = edge == .left || edge == .right
    let newWidth = canvas.width + (horizontal ? amount : 0)
    let newHeight = canvas.height + (horizontal ? 0 : amount)
    guard newWidth <= maxSide, newHeight <= maxSide else { throw ImageOpError.tooLarge }

    var copy = document
    copy.canvasSize = CGSize(width: newWidth, height: newHeight)
    let shift: CGPoint
    switch edge {
    case .left: shift = CGPoint(x: Double(amount), y: 0)
    case .top: shift = CGPoint(x: 0, y: Double(amount))
    case .right, .bottom: shift = .zero
    }
    copy.imageOrigin = document.imageOrigin + shift
    copy.elements = document.elements.map { shift == .zero ? $0 : $0.translated(by: shift) }
    return copy
  }

  // MARK: Rotate

  /// Rotates the canvas by 90 degrees. Boxes, text and stamps keep their size and gain a quarter turn of
  /// `rotation`; points of arrows, lines and freehand strokes are mapped.
  public static func rotate90(_ document: Document, clockwise: Bool) throws -> Document {
    let canvas = try canvasPixels(of: document)
    let flat = try flattened(document)
    let source = try makeContext(width: canvas.width, height: canvas.height)
    source.draw(flat, in: CGRect(x: 0, y: 0, width: canvas.width, height: canvas.height))
    let destination = try makeContext(width: canvas.height, height: canvas.width)
    guard let from = source.data?.assumingMemoryBound(to: UInt8.self),
      let to = destination.data?.assumingMemoryBound(to: UInt8.self)
    else { throw ImageOpError.renderFailed }
    let fromStride = source.bytesPerRow
    let toStride = destination.bytesPerRow
    for y in 0..<canvas.height {
      for x in 0..<canvas.width {
        let dx = clockwise ? canvas.height - 1 - y : y
        let dy = clockwise ? x : canvas.width - 1 - x
        for channel in 0..<4 {
          to[dy * toStride + dx * 4 + channel] = from[y * fromStride + x * 4 + channel]
        }
      }
    }
    guard let result = destination.makeImage() else { throw ImageOpError.renderFailed }

    let width = Double(canvas.width)
    let height = Double(canvas.height)
    let map: (CGPoint) -> CGPoint =
      clockwise
      ? { CGPoint(x: height - $0.y, y: $0.x) }
      : { CGPoint(x: $0.y, y: width - $0.x) }
    let quarter = clockwise ? Double.pi / 2 : -Double.pi / 2
    let elements = document.elements.map {
      transformed($0, map: map, rotation: { normalized($0 + quarter) }, tailAngle: { $0 }, mirrored: false)
    }
    return rebuilt(document, image: result, elements: elements)
  }

  // MARK: Flip

  /// Mirrors the canvas. Text and stamp glyphs are not mirrored: their box moves to the mirrored spot and
  /// their `rotation` (and a stamp's tail) is mirrored.
  public static func flip(_ document: Document, axis: FlipAxis) throws -> Document {
    let canvas = try canvasPixels(of: document)
    let flat = try flattened(document)
    let source = try makeContext(width: canvas.width, height: canvas.height)
    source.draw(flat, in: CGRect(x: 0, y: 0, width: canvas.width, height: canvas.height))
    let destination = try makeContext(width: canvas.width, height: canvas.height)
    guard let from = source.data?.assumingMemoryBound(to: UInt8.self),
      let to = destination.data?.assumingMemoryBound(to: UInt8.self)
    else { throw ImageOpError.renderFailed }
    let fromStride = source.bytesPerRow
    let toStride = destination.bytesPerRow
    for y in 0..<canvas.height {
      for x in 0..<canvas.width {
        let dx = axis == .horizontal ? canvas.width - 1 - x : x
        let dy = axis == .vertical ? canvas.height - 1 - y : y
        for channel in 0..<4 {
          to[dy * toStride + dx * 4 + channel] = from[y * fromStride + x * 4 + channel]
        }
      }
    }
    guard let result = destination.makeImage() else { throw ImageOpError.renderFailed }

    let width = Double(canvas.width)
    let height = Double(canvas.height)
    let map: (CGPoint) -> CGPoint =
      axis == .horizontal ? { CGPoint(x: width - $0.x, y: $0.y) } : { CGPoint(x: $0.x, y: height - $0.y) }
    let mirrorAngle: (Double) -> Double = axis == .horizontal ? { .pi - $0 } : { -$0 }
    let elements = document.elements.map {
      transformed($0, map: map, rotation: { -$0 }, tailAngle: mirrorAngle, mirrored: true)
    }
    return rebuilt(document, image: result, elements: elements)
  }

  // MARK: Helpers

  /// Integer pixel size of the canvas, validated against the size guard.
  private static func canvasPixels(of document: Document) throws -> (width: Int, height: Int) {
    let width = document.canvasSize.width.rounded()
    let height = document.canvasSize.height.rounded()
    guard width.isFinite, height.isFinite, width >= 1, height >= 1 else { throw ImageOpError.invalidRect }
    guard width <= Double(maxSide), height <= Double(maxSide) else { throw ImageOpError.tooLarge }
    return (Int(width), Int(height))
  }

  /// Rounds `rect` outward to whole pixels and clips it to `0..<width` x `0..<height`.
  private static func pixelRegion(of rect: CGRect, within width: Int, _ height: Int) throws -> PixelRegion {
    let r = rect.standardized
    guard r.origin.x.isFinite, r.origin.y.isFinite, r.width.isFinite, r.height.isFinite else {
      throw ImageOpError.invalidRect
    }
    func clamp(_ value: Double, _ limit: Int) -> Int { Int(min(max(value, 0), Double(limit))) }
    let minX = clamp(r.minX.rounded(.down), width)
    let minY = clamp(r.minY.rounded(.down), height)
    let maxX = clamp(r.maxX.rounded(.up), width)
    let maxY = clamp(r.maxY.rounded(.up), height)
    guard maxX > minX, maxY > minY, r.width > 0, r.height > 0 else { throw ImageOpError.invalidRect }
    return PixelRegion(minX: minX, minY: minY, maxX: maxX, maxY: maxY)
  }

  /// The canvas (background plus base image at `imageOrigin`) as one bitmap with origin zero.
  private static func flattened(_ document: Document) throws -> CGImage {
    let canvas = try canvasPixels(of: document)
    let image = document.baseImage
    if document.imageOrigin == .zero && image.width == canvas.width && image.height == canvas.height {
      return image
    }
    let context = try makeContext(width: canvas.width, height: canvas.height)
    context.setFillColor(document.background.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: canvas.width, height: canvas.height))
    // The context is y-up; imageOrigin is the image's top-left in y-down document space.
    let y = Double(canvas.height) - document.imageOrigin.y - Double(image.height)
    context.draw(
      image, in: CGRect(x: document.imageOrigin.x, y: y, width: Double(image.width), height: Double(image.height)))
    guard let result = context.makeImage() else { throw ImageOpError.renderFailed }
    return result
  }

  /// The document with a new base bitmap that fills the whole canvas.
  private static func rebuilt(_ document: Document, image: CGImage, elements: [Element]) -> Document {
    var copy = document
    copy.baseImage = image
    copy.canvasSize = CGSize(width: image.width, height: image.height)
    copy.imageOrigin = .zero
    copy.elements = elements
    return copy
  }

  /// sRGB RGBA8 premultiplied bitmap context, zero-filled (row 0 is the top row of memory).
  private static func makeContext(width: Int, height: Int) throws -> CGContext {
    guard width <= maxSide, height <= maxSide, let space = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { throw ImageOpError.renderFailed }
    return context
  }

  /// Maps an element through a rotate/flip. Arrows, lines and freehand strokes map their points. Boxes, text
  /// and stamps keep their shape (never mirrored), get `rotation` updated and are placed so that the center of
  /// their unrotated bounds lands where the mapped center of the old bounds is.
  private static func transformed(
    _ element: Element, map: (CGPoint) -> CGPoint, rotation: (Double) -> Double, tailAngle: (Double) -> Double,
    mirrored: Bool
  ) -> Element {
    var result = element
    switch element.kind {
    case .arrow(let start, let end, let doubleHeaded):
      result.kind = .arrow(start: map(start), end: map(end), doubleHeaded: doubleHeaded)
    case .line(let start, let end):
      result.kind = .line(start: map(start), end: map(end))
    case .freehand(let segments, let highlighter):
      let mapped = segments.map { BezierSegment(map($0.p0), map($0.p1), map($0.p2), map($0.p3)) }
      result.kind = .freehand(segments: mapped, highlighter: highlighter)
    case .rect, .ellipse, .text, .stamp:
      if case .stamp(let stamp, let center, let angle, let label) = element.kind {
        // A rotation turns the whole stamp, tail included, so only a mirror changes the stored tail angle.
        let newAngle = mirrored ? angle.map(tailAngle) : angle
        result.kind = .stamp(stamp, center: center, tailAngle: newAngle, labelID: label)
      }
      result.rotation = rotation(element.rotation)
      let target = map(element.baseBounds.center)
      let delta = target - result.baseBounds.center
      result = result.translated(by: delta)
    }
    return result
  }

  /// Folds an angle into (-pi, pi] so repeated quarter turns return to exactly zero.
  private static func normalized(_ angle: Double) -> Double {
    var value = angle.truncatingRemainder(dividingBy: 2 * .pi)
    if value > .pi { value -= 2 * .pi }
    if value <= -.pi { value += 2 * .pi }
    return value
  }
}

/// Half-open pixel region `minX..<maxX` x `minY..<maxY`.
private struct PixelRegion {
  var minX: Int
  var minY: Int
  var maxX: Int
  var maxY: Int
  var width: Int { maxX - minX }
  var height: Int { maxY - minY }
}
