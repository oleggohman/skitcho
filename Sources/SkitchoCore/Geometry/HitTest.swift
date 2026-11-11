import CoreGraphics
import Foundation

/// Hit testing against paths. Tolerance and widths are in document units (the canvas divides view pixels by zoom).
public enum HitTest {
  /// True when `point` lies within `tolerance` of a stroke of `strokeWidth` along `path`.
  public static func stroke(path: CGPath, strokeWidth: Double, point: CGPoint, tolerance: Double) -> Bool {
    let width = max(strokeWidth, 0) + 2 * max(tolerance, 0)
    guard width > 0, !path.isEmpty else { return false }
    let stroked = path.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 10)
    return stroked.contains(point, using: .winding)
  }

  /// True when `point` is inside the closed `path`, or within `tolerance` of its outline stroked at `strokeWidth`.
  public static func filled(path: CGPath, strokeWidth: Double = 0, point: CGPoint, tolerance: Double) -> Bool {
    guard !path.isEmpty else { return false }
    if path.contains(point, using: .winding) { return true }
    return stroke(path: path, strokeWidth: strokeWidth, point: point, tolerance: tolerance)
  }

  /// True when the stroked `path` (or its filled interior when `filled`) intersects `rect`.
  public static func intersects(path: CGPath, strokeWidth: Double, filled: Bool = false, rect: CGRect) -> Bool {
    let reach = path.boundingBoxOfPath.insetBy(dx: -strokeWidth, dy: -strokeWidth)
    guard !path.isEmpty, !rect.isEmpty, reach.intersects(rect) else { return false }
    let region = CGPath(rect: rect, transform: nil)
    if filled {
      if !path.intersection(region, using: .winding).isEmpty { return true }
    }
    guard strokeWidth > 0 else { return false }
    let stroked = path.copy(strokingWithWidth: strokeWidth, lineCap: .round, lineJoin: .round, miterLimit: 10)
    return !stroked.intersection(region, using: .winding).isEmpty
  }
}
