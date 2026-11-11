import CoreGraphics
import Foundation

/// Builds the arrow outline: one closed filled path whose shaft tapers into a swept, triangular head.
///
/// All proportions are multiples of the stroke width `w` (or of the head length) and live in this enum only:
/// - head length `headLengthFactor * w`, capped at `maxHeadFraction` of the arrow length
/// - head half-width `headHalfWidthFactor * head`
/// - barbs sit `barbSweepFactor * head` behind the head base, which gives the swept look
/// - shaft half-width `baseHalfWidthFactor * w` at the head base, `tailHalfWidthFactor * w` at the tail
///   (the single-headed tail ends in a round cap)
public enum ArrowPath {
  /// Nominal head length as a multiple of the stroke width.
  static let headLengthFactor = 4.0
  /// Head half-width as a multiple of the head length.
  static let headHalfWidthFactor = 0.7
  /// How far the barbs sit behind the head base, as a multiple of the head length.
  static let barbSweepFactor = 0.15
  /// Shaft half-width at the head base, as a multiple of the stroke width.
  static let baseHalfWidthFactor = 0.45
  /// Shaft half-width at the tail, as a multiple of the stroke width.
  static let tailHalfWidthFactor = 0.15
  /// Shortest drag that creates an arrow, as a multiple of the stroke width (independent of the head size).
  static let minimumLengthFactor = 9.0
  /// The head never exceeds this fraction of the arrow length.
  public static let maxHeadFraction = 0.4
  /// The white outline's half-width is `max(outlineMinimum, outlineFactor * w)`.
  static let outlineFactor = 0.12
  static let outlineMinimum = 1.5

  /// Head length for an arrow of `length`: grows with `width`, capped at `0.4 * length`.
  public static func headLength(width: Double, length: Double) -> Double {
    min(max(width, 0) * headLengthFactor, length * maxHeadFraction)
  }

  /// Shortest drag that should create an arrow of this width.
  public static func minimumLength(width: Double) -> Double {
    max(width, 0) * minimumLengthFactor
  }

  /// Line width of the white outline stroked under the fill (it extends `outlineWidth / 2` past the fill).
  public static func outlineWidth(width: Double) -> Double {
    2 * max(outlineMinimum, max(width, 0) * outlineFactor)
  }

  /// Arrow from `start` to `end`. The tip is at `end`; with `doubleHeaded` the start also gets a head.
  /// Returns an empty path when the points coincide.
  public static func make(from start: CGPoint, to end: CGPoint, width: Double, doubleHeaded: Bool = false) -> CGPath {
    let length = start.distance(to: end)
    guard length > 1e-6, width > 0 else { return CGMutablePath() }

    let head = headLength(width: width, length: length)
    let headHalf = head * headHalfWidthFactor
    let sweep = head * barbSweepFactor
    // The shaft never gets wider than the head (short, wide arrows cap the head at a fraction of the length).
    let baseHalf = min(width * baseHalfWidthFactor, headHalf)
    let tailHalf = min(width * tailHalfWidthFactor, baseHalf)

    // Local frame: x along the arrow from start to end, y perpendicular.
    let local = CGMutablePath()
    if doubleHeaded {
      let points = [
        CGPoint(x: 0, y: 0),
        CGPoint(x: head + sweep, y: headHalf), CGPoint(x: head, y: baseHalf),
        CGPoint(x: length - head, y: baseHalf), CGPoint(x: length - head - sweep, y: headHalf),
        CGPoint(x: length, y: 0),
        CGPoint(x: length - head - sweep, y: -headHalf), CGPoint(x: length - head, y: -baseHalf),
        CGPoint(x: head, y: -baseHalf), CGPoint(x: head + sweep, y: -headHalf),
      ]
      local.addLines(between: points)
    } else {
      let points = [
        CGPoint(x: 0, y: tailHalf),
        CGPoint(x: length - head, y: baseHalf), CGPoint(x: length - head - sweep, y: headHalf),
        CGPoint(x: length, y: 0),
        CGPoint(x: length - head - sweep, y: -headHalf), CGPoint(x: length - head, y: -baseHalf),
        CGPoint(x: 0, y: -tailHalf),
      ]
      local.addLines(between: points)
      // Round tail cap: a half circle from (0, -tailHalf) around (-tailHalf, 0) back to (0, tailHalf).
      local.addArc(
        center: .zero, radius: tailHalf, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: true)
    }
    local.closeSubpath()

    let angle = atan2(end.y - start.y, end.x - start.x)
    var transform = CGAffineTransform(translationX: start.x, y: start.y).rotated(by: angle)
    return local.copy(using: &transform) ?? CGMutablePath()
  }
}
