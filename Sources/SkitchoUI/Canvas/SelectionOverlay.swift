import AppKit
import CoreGraphics
import Foundation
import SkitchoCore

/// Draws selection outlines (dashed "marching ants"), handles and the marquee. Handles are blue with a white
/// outline (CloudZone). `context` is in document space.
enum SelectionOverlay {
  static func draw(elements: [Element], marquee: CGRect?, in context: CGContext, zoom: Double) {
    let blue = BrandColor.blue.nsColor().cgColor
    let white = BrandColor.white.nsColor().cgColor
    let px = 1 / max(zoom, 0.0001)
    context.saveGState()
    defer { context.restoreGState() }

    for element in elements { strokeOutline(of: element, blue: blue, white: white, px: px, in: context) }

    if elements.count == 1, let element = elements.first {
      drawHandles(of: element, zoom: zoom, blue: blue, white: white, in: context)
    }
    if let marquee {
      context.setFillColor(BrandColor.blue.nsColor(alpha: 0.12).cgColor)
      context.fill(marquee)
      context.setStrokeColor(blue)
      context.setLineWidth(1 * px)
      context.setLineDash(phase: 0, lengths: [4 * px, 3 * px])
      context.stroke(marquee)
    }
  }

  /// White under-stroke plus a dashed blue stroke; the outline follows the element's rotation.
  private static func strokeOutline(
    of element: Element, blue: CGColor, white: CGColor, px: Double, in context: CGContext
  ) {
    let path = CGMutablePath()
    switch element.kind {
    case .arrow, .line, .freehand:
      path.addRect(element.bounds)
    default:
      let base = element.baseBounds
      let transform = CGAffineTransform(translationX: base.midX, y: base.midY)
        .rotated(by: element.rotation)
        .translatedBy(x: -base.midX, y: -base.midY)
      path.addRect(base, transform: transform)
    }
    context.addPath(path)
    strokeAnts(blue: blue, white: white, px: px, in: context)
  }

  private static func strokeAnts(blue: CGColor, white: CGColor, px: Double, in context: CGContext) {
    guard let path = context.path else { return }
    context.setLineWidth(1.5 * px)
    context.setLineDash(phase: 0, lengths: [])
    context.setStrokeColor(white)
    context.strokePath()
    context.addPath(path)
    context.setLineDash(phase: 0, lengths: [5 * px, 4 * px])
    context.setStrokeColor(blue)
    context.strokePath()
    context.setLineDash(phase: 0, lengths: [])
  }

  private static func drawHandles(
    of element: Element, zoom: Double, blue: CGColor, white: CGColor, in context: CGContext
  ) {
    let px = 1 / max(zoom, 0.0001)
    let side = HandleLayout.handleSide * px
    context.setLineDash(phase: 0, lengths: [])
    context.setLineWidth(1.5 * px)
    for (handle, point) in HandleLayout.handles(for: element, zoom: zoom) {
      let box = CGRect(x: point.x - side / 2, y: point.y - side / 2, width: side, height: side)
      context.setFillColor(blue)
      context.setStrokeColor(white)
      if handle == .rotate || handle == .start || handle == .end {
        context.fillEllipse(in: box)
        context.strokeEllipse(in: box)
      } else {
        context.fill(box)
        context.stroke(box)
      }
    }
  }
}
