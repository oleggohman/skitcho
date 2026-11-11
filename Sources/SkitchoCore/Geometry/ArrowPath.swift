import CoreGraphics
import Foundation

/// Builds the arrow outline: one closed filled path whose shaft tapers into a triangular head.
public enum ArrowPath {
  /// Nominal head length as a multiple of the stroke width.
  static let headLengthFactor = 3.0
  /// The head never exceeds this fraction of the arrow length.
  public static let maxHeadFraction = 0.4

  /// Head length for an arrow of `length`: grows with `width`, capped at `0.4 * length`.
  public static func headLength(width: Double, length: Double) -> Double {
    min(max(width, 0) * headLengthFactor, length * maxHeadFraction)
  }

  /// Shortest drag that should create an arrow of this width (three nominal head lengths).
  public static func minimumLength(width: Double) -> Double {
    3 * max(width, 0) * headLengthFactor
  }

  /// Arrow from `start` to `end`. The tip is at `end`; with `doubleHeaded` the start also gets a head.
  /// Returns an empty path when the points coincide.
  public static func make(from start: CGPoint, to end: CGPoint, width: Double, doubleHeaded: Bool = false) -> CGPath {
    let length = start.distance(to: end)
    guard length > 1e-6, width > 0 else { return CGMutablePath() }

    let head = headLength(width: width, length: length)
    let headHalf = head * 0.6
    let tailHalf = max(width * 0.08, 1.5)
    let baseHalf = max(width * 0.25, tailHalf)

    // Local frame: x along the arrow from start to end, y perpendicular.
    var local: [CGPoint] = []
    if doubleHeaded {
      local = [
        CGPoint(x: 0, y: 0),
        CGPoint(x: head, y: headHalf), CGPoint(x: head, y: baseHalf),
        CGPoint(x: length - head, y: baseHalf), CGPoint(x: length - head, y: headHalf),
        CGPoint(x: length, y: 0),
        CGPoint(x: length - head, y: -headHalf), CGPoint(x: length - head, y: -baseHalf),
        CGPoint(x: head, y: -baseHalf), CGPoint(x: head, y: -headHalf),
      ]
    } else {
      local = [
        CGPoint(x: 0, y: tailHalf),
        CGPoint(x: length - head, y: baseHalf), CGPoint(x: length - head, y: headHalf),
        CGPoint(x: length, y: 0),
        CGPoint(x: length - head, y: -headHalf), CGPoint(x: length - head, y: -baseHalf),
        CGPoint(x: 0, y: -tailHalf),
      ]
    }

    let angle = atan2(end.y - start.y, end.x - start.x)
    let transform = CGAffineTransform(translationX: start.x, y: start.y).rotated(by: angle)
    let path = CGMutablePath()
    for (index, point) in local.enumerated() {
      let mapped = point.applying(transform)
      if index == 0 { path.move(to: mapped) } else { path.addLine(to: mapped) }
    }
    path.closeSubpath()
    return path
  }
}
