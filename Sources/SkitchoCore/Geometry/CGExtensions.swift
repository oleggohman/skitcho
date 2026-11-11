import CoreGraphics
import Foundation

extension CGPoint {
  /// Component-wise sum.
  static func + (lhs: CGPoint, rhs: CGPoint) -> CGPoint { CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y) }
  /// Component-wise difference.
  static func - (lhs: CGPoint, rhs: CGPoint) -> CGPoint { CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y) }

  /// Euclidean distance to another point.
  func distance(to other: CGPoint) -> Double { hypot(x - other.x, y - other.y) }
}

extension CGRect {
  /// Center of the rectangle.
  var center: CGPoint { CGPoint(x: midX, y: midY) }
}

/// Small geometry helpers shared by the shape, hit-test and tool code. All values are in document space.
public enum GeometryMath {
  /// Distance from `point` to the closed segment `a`-`b`. A degenerate segment measures to `a`.
  public static func distance(from point: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> Double {
    let dx = b.x - a.x
    let dy = b.y - a.y
    let lengthSquared = dx * dx + dy * dy
    guard lengthSquared > 1e-12 else { return point.distance(to: a) }
    let t = max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared))
    return point.distance(to: CGPoint(x: a.x + t * dx, y: a.y + t * dy))
  }

  /// Rotates `point` by `angle` radians about `pivot` (document space is y-down, so positive is clockwise on screen).
  public static func rotate(_ point: CGPoint, about pivot: CGPoint, by angle: Double) -> CGPoint {
    let c = cos(angle)
    let s = sin(angle)
    let dx = point.x - pivot.x
    let dy = point.y - pivot.y
    return CGPoint(x: pivot.x + dx * c - dy * s, y: pivot.y + dx * s + dy * c)
  }

  /// Returns the point at the same distance from `origin` as `point`, with its direction snapped to the nearest
  /// multiple of `step` radians (default 15 degrees). A point equal to `origin` is returned unchanged.
  public static func snapped(_ point: CGPoint, from origin: CGPoint, step: Double = .pi / 12) -> CGPoint {
    let length = point.distance(to: origin)
    guard length > 1e-12, step > 0 else { return point }
    let angle = atan2(point.y - origin.y, point.x - origin.x)
    let snappedAngle = (angle / step).rounded() * step
    return CGPoint(x: origin.x + length * cos(snappedAngle), y: origin.y + length * sin(snappedAngle))
  }

  /// Snaps an angle in radians to the nearest multiple of `step` (default 15 degrees).
  public static func snapAngle(_ angle: Double, step: Double = .pi / 12) -> Double {
    guard step > 0 else { return angle }
    return (angle / step).rounded() * step
  }
}
