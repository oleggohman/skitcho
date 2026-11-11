import CoreGraphics
import Foundation

/// Paths for the basic shapes, in document space. A non-zero `rotation` turns the shape about the rect center.
public enum ShapePaths {
  /// Corner radius of the rounded rectangle for a given rect.
  public static func cornerRadius(for rect: CGRect) -> Double {
    min(abs(rect.width), abs(rect.height)) * 0.2
  }

  public static func rect(_ rect: CGRect, rounded: Bool = false, rotation: Double = 0) -> CGPath {
    let r = rect.standardized
    let path: CGPath
    if rounded {
      let radius = cornerRadius(for: r)
      path = CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
    } else {
      path = CGPath(rect: r, transform: nil)
    }
    return rotated(path, about: r.center, by: rotation)
  }

  public static func ellipse(_ rect: CGRect, rotation: Double = 0) -> CGPath {
    let r = rect.standardized
    return rotated(CGPath(ellipseIn: r, transform: nil), about: r.center, by: rotation)
  }

  public static func line(from start: CGPoint, to end: CGPoint) -> CGPath {
    let path = CGMutablePath()
    path.move(to: start)
    path.addLine(to: end)
    return path
  }

  private static func rotated(_ path: CGPath, about pivot: CGPoint, by angle: Double) -> CGPath {
    guard angle != 0 else { return path }
    var transform = CGAffineTransform(translationX: pivot.x, y: pivot.y)
      .rotated(by: angle)
      .translatedBy(x: -pivot.x, y: -pivot.y)
    return path.copy(using: &transform) ?? path
  }
}
