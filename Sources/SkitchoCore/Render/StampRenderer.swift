import CoreGraphics
import Foundation

/// Draws stamp badges: a filled circle, a glyph built from drawn geometry (never SF Symbols) and an optional
/// tail triangle pointing along `tailAngle`.
enum StampRenderer {
  /// Half-angle (radians) of the tail triangle's base as seen from the badge center.
  static let tailHalfAngle = 0.55

  /// Draws into a y-down document-space context. `rotation` turns the whole stamp about `pivot`.
  static func draw(
    _ kind: StampKind, center: CGPoint, tailAngle: Double?, style: Style, rotation: Double, pivot: CGPoint,
    in context: CGContext, scale: Double, shadows: Bool
  ) {
    let radius = StampKind.radius(strokeWidth: style.strokeWidth)
    guard radius > 0 else { return }

    context.saveGState()
    defer { context.restoreGState() }
    if rotation != 0 {
      context.translateBy(x: pivot.x, y: pivot.y)
      context.rotate(by: rotation)
      context.translateBy(x: -pivot.x, y: -pivot.y)
    }

    // One shadow for the whole badge: draw badge, tail and glyph inside a single transparency layer.
    if shadows {
      DocumentRenderer.applyShadow(in: context, scale: scale, enabled: true)
      context.beginTransparencyLayer(auxiliaryInfo: nil)
    }

    context.setFillColor(style.color.cgColor)
    if let tailAngle {
      context.addPath(tailPath(center: center, radius: radius, angle: tailAngle))
      context.fillPath()
    }
    context.fillEllipse(
      in: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius))

    drawGlyph(kind, center: center, radius: radius, color: style.color.contrastingOutline.cgColor, in: context)

    if shadows { context.endTransparencyLayer() }
  }

  /// Triangle from two points on the badge edge to the tip.
  static func tailPath(center: CGPoint, radius: Double, angle: Double) -> CGPath {
    let reach = radius * (1 + StampKind.tailExtension)
    func point(_ distance: Double, _ direction: Double) -> CGPoint {
      CGPoint(x: center.x + distance * cos(direction), y: center.y + distance * sin(direction))
    }
    let path = CGMutablePath()
    path.move(to: point(radius, angle - tailHalfAngle))
    path.addLine(to: point(reach, angle))
    path.addLine(to: point(radius, angle + tailHalfAngle))
    path.closeSubpath()
    return path
  }

  /// The glyph in unit coordinates (badge radius 1, y-down): a stroked part and a filled part.
  static func glyph(for kind: StampKind) -> (stroke: CGPath, fill: CGPath) {
    let stroke = CGMutablePath()
    let fill = CGMutablePath()
    switch kind {
    case .approve:
      stroke.move(to: CGPoint(x: -0.42, y: 0.02))
      stroke.addLine(to: CGPoint(x: -0.12, y: 0.32))
      stroke.addLine(to: CGPoint(x: 0.42, y: -0.32))
    case .reject:
      stroke.move(to: CGPoint(x: -0.34, y: -0.34))
      stroke.addLine(to: CGPoint(x: 0.34, y: 0.34))
      stroke.move(to: CGPoint(x: 0.34, y: -0.34))
      stroke.addLine(to: CGPoint(x: -0.34, y: 0.34))
    case .question:
      // Hook: a three-quarter arc from the upper left over the top to the bottom of its circle, then the stem.
      let arcCenter = CGPoint(x: 0, y: -0.25)
      let arcRadius = 0.3
      let steps = 24
      let start = 0.9 * Double.pi
      let end = 2.5 * Double.pi
      for step in 0...steps {
        let angle = start + (end - start) * Double(step) / Double(steps)
        let point = CGPoint(x: arcCenter.x + arcRadius * cos(angle), y: arcCenter.y + arcRadius * sin(angle))
        if step == 0 { stroke.move(to: point) } else { stroke.addLine(to: point) }
      }
      stroke.addLine(to: CGPoint(x: 0, y: 0.2))
      fill.addEllipse(in: CGRect(x: -0.1, y: 0.45, width: 0.2, height: 0.2))
    case .attention:
      stroke.move(to: CGPoint(x: 0, y: -0.55))
      stroke.addLine(to: CGPoint(x: 0, y: 0.15))
      fill.addEllipse(in: CGRect(x: -0.1, y: 0.4, width: 0.2, height: 0.2))
    case .perfect:
      let outer = 0.62
      let inner = 0.26
      for index in 0..<10 {
        let angle = -Double.pi / 2 + Double(index) * Double.pi / 5
        let length = index.isMultiple(of: 2) ? outer : inner
        let point = CGPoint(x: length * cos(angle), y: length * sin(angle))
        if index == 0 { fill.move(to: point) } else { fill.addLine(to: point) }
      }
      fill.closeSubpath()
    }
    return (stroke, fill)
  }

  private static func drawGlyph(
    _ kind: StampKind, center: CGPoint, radius: Double, color: CGColor, in context: CGContext
  ) {
    let shapes = glyph(for: kind)
    context.saveGState()
    context.translateBy(x: center.x, y: center.y)
    context.scaleBy(x: radius, y: radius)
    context.setFillColor(color)
    context.setStrokeColor(color)
    context.setLineWidth(0.17)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    if !shapes.stroke.isEmpty {
      context.addPath(shapes.stroke)
      context.strokePath()
    }
    if !shapes.fill.isEmpty {
      context.addPath(shapes.fill)
      context.fillPath()
    }
    context.restoreGState()
  }
}
