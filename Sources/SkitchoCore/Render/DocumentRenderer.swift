import CoreGraphics
import Foundation

public enum RenderError: Error, Equatable {
  case contextCreationFailed
  case imageCreationFailed
}

/// Draws a `Document` into a CoreGraphics context. This is the only code that bridges the top-left, y-down
/// document space to CoreGraphics' y-up space: `draw` flips the context exactly once, and flips locally
/// wherever CoreGraphics draws content upside down (bitmaps).
public enum DocumentRenderer {
  /// Alpha of the highlighter stroke (drawn with the multiply blend mode).
  public static let highlighterAlpha = 0.4

  /// Draws background, base image and elements into `context`.
  /// - Parameters:
  ///   - context: a standard CoreGraphics (y-up) context of `canvasSize * scale` pixels.
  ///   - scale: output pixels per document unit (1 or 2 for export, the zoom for on-screen drawing).
  ///   - excluding: element IDs to skip (the one being edited in place, for example).
  ///   - shadows: draws a soft drop shadow under shapes and arrows.
  public static func draw(
    _ document: Document,
    in context: CGContext,
    scale: Double = 1,
    excluding: Set<UUID> = [],
    shadows: Bool = true
  ) {
    context.saveGState()
    defer { context.restoreGState() }

    // The single flip: document space becomes top-left origin, y-down, in document units.
    context.translateBy(x: 0, y: document.canvasSize.height * scale)
    context.scaleBy(x: scale, y: -scale)

    context.setFillColor(document.background.cgColor)
    context.fill(CGRect(origin: .zero, size: document.canvasSize))

    drawBase(document, in: context)

    for element in document.elements where !excluding.contains(element.id) {
      draw(element, in: context, scale: scale, shadows: shadows)
    }
  }

  /// Renders the whole document into a new sRGB RGBA8 premultiplied image of `canvasSize * scale` pixels.
  public static func flatten(_ document: Document, scale: Double = 1) throws -> CGImage {
    let width = max(1, Int((document.canvasSize.width * scale).rounded()))
    let height = max(1, Int((document.canvasSize.height * scale).rounded()))
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { throw RenderError.contextCreationFailed }
    context.interpolationQuality = .high
    draw(document, in: context, scale: scale, shadows: true)
    guard let image = context.makeImage() else { throw RenderError.imageCreationFailed }
    return image
  }

  // MARK: Base image

  /// Draws the bitmap at `imageOrigin`. The context is y-down here, so the image is flipped back locally.
  private static func drawBase(_ document: Document, in context: CGContext) {
    let image = document.baseImage
    let width = Double(image.width)
    let height = Double(image.height)
    context.saveGState()
    context.translateBy(x: document.imageOrigin.x, y: document.imageOrigin.y + height)
    context.scaleBy(x: 1, y: -1)
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    context.restoreGState()
  }

  // MARK: Elements

  private static func draw(_ element: Element, in context: CGContext, scale: Double, shadows: Bool) {
    let style = element.style
    let color = style.color.cgColor
    switch element.kind {
    case .arrow(let start, let end, let doubleHeaded):
      let path = ArrowPath.make(from: start, to: end, width: style.strokeWidth, doubleHeaded: doubleHeaded)
      guard !path.isEmpty else { return }
      context.saveGState()
      applyShadow(in: context, scale: scale, enabled: shadows)
      context.setFillColor(color)
      context.addPath(path)
      context.fillPath()
      context.restoreGState()

    case .line(let start, let end):
      stroke(ShapePaths.line(from: start, to: end), style: style, in: context, scale: scale, shadows: shadows)

    case .rect(let rect, let rounded):
      stroke(
        ShapePaths.rect(rect, rounded: rounded, rotation: element.rotation), style: style, in: context,
        scale: scale, shadows: shadows, join: .miter)

    case .ellipse(let rect):
      stroke(
        ShapePaths.ellipse(rect, rotation: element.rotation), style: style, in: context, scale: scale,
        shadows: shadows)

    case .freehand(let segments, let highlighter):
      let path = ShapePaths.freehand(segments)
      guard !path.isEmpty else { return }
      if highlighter {
        context.saveGState()
        context.setBlendMode(.multiply)
        context.setAlpha(highlighterAlpha)
        context.setStrokeColor(color)
        context.setLineWidth(style.strokeWidth)
        context.setLineCap(.butt)
        context.setLineJoin(.round)
        context.addPath(path)
        context.strokePath()
        context.restoreGState()
      } else {
        stroke(path, style: style, in: context, scale: scale, shadows: shadows)
      }

    case .text(let content):
      TextRenderer.draw(content, style: style, rotation: element.rotation, in: context)

    case .stamp(let stamp, let center, let tailAngle, _):
      StampRenderer.draw(
        stamp, center: center, tailAngle: tailAngle, style: style, rotation: element.rotation,
        pivot: element.baseBounds.center, in: context, scale: scale, shadows: shadows)
    }
  }

  private static func stroke(
    _ path: CGPath, style: Style, in context: CGContext, scale: Double, shadows: Bool, join: CGLineJoin = .round
  ) {
    context.saveGState()
    applyShadow(in: context, scale: scale, enabled: shadows)
    context.setStrokeColor(style.color.cgColor)
    context.setLineWidth(style.strokeWidth)
    context.setLineCap(.round)
    context.setLineJoin(join)
    context.addPath(path)
    context.strokePath()
    context.restoreGState()
  }

  /// A soft shadow falling slightly down and to the right on screen.
  static func applyShadow(in context: CGContext, scale: Double, enabled: Bool) {
    guard enabled else { return }
    let shadowColor = CGColor(gray: 0, alpha: 0.3)
    // The shadow offset is expressed in device space (y-up), so "down" is negative.
    context.setShadow(offset: CGSize(width: 1 * scale, height: -2 * scale), blur: 3 * scale, color: shadowColor)
  }
}
