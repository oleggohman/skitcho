import CoreGraphics
import Foundation

/// Exponential low-pass filter for the live freehand stream. Each accepted input moves the output a fraction
/// `alpha` of the way towards it, which removes hand jitter. Points that would land within `minDistance` of the
/// previously emitted point are dropped. All values are in document space.
public struct LowPassFilter: Sendable {
  /// Smoothing factor in (0, 1]. 1 passes input through unchanged; smaller values smooth more.
  public let alpha: Double
  /// Output points closer than this to the previous output point are dropped.
  public let minDistance: Double
  private var last: CGPoint?

  public init(alpha: Double = 0.5, minDistance: Double = 0.5) {
    self.alpha = alpha.isFinite ? min(1, max(0.01, alpha)) : 0.5
    self.minDistance = minDistance.isFinite ? max(0, minDistance) : 0.5
  }

  /// Feeds one raw point. Returns the filtered point to append to the stroke, or nil if it was dropped
  /// (non-finite, or within `minDistance` of the previous output).
  public mutating func add(_ point: CGPoint) -> CGPoint? {
    guard point.x.isFinite, point.y.isFinite else { return nil }
    guard let previous = last else {
      last = point
      return point
    }
    let filtered = CGPoint(
      x: previous.x + alpha * (point.x - previous.x),
      y: previous.y + alpha * (point.y - previous.y))
    guard filtered.distance(to: previous) >= minDistance else { return nil }
    last = filtered
    return filtered
  }

  /// Clears the filter state so the next point starts a new stroke.
  public mutating func reset() { last = nil }

  /// Filters a whole stroke. The final raw point is always kept so the stroke ends where the pointer was released.
  public static func filter(_ points: [CGPoint], alpha: Double = 0.5, minDistance: Double = 0.5) -> [CGPoint] {
    var filter = LowPassFilter(alpha: alpha, minDistance: minDistance)
    var output = points.compactMap { filter.add($0) }
    guard let end = points.last(where: { $0.x.isFinite && $0.y.isFinite }), let tail = output.last, tail != end
    else { return output }
    if output.count > 1, tail.distance(to: end) < filter.minDistance {
      output[output.count - 1] = end
    } else {
      output.append(end)
    }
    return output
  }
}
