import CoreGraphics
import Foundation

/// One cubic bezier segment: start, two control points, end (document space).
public struct BezierSegment: Sendable, Equatable, Codable {
  public var p0: CGPoint
  public var p1: CGPoint
  public var p2: CGPoint
  public var p3: CGPoint

  public init(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint) {
    self.p0 = p0
    self.p1 = p1
    self.p2 = p2
    self.p3 = p3
  }

  /// Point on the curve at parameter `t` in [0, 1].
  public func point(at t: Double) -> CGPoint {
    let u = 1 - t
    let b0 = u * u * u
    let b1 = 3 * u * u * t
    let b2 = 3 * u * t * t
    let b3 = t * t * t
    return CGPoint(
      x: b0 * p0.x + b1 * p1.x + b2 * p2.x + b3 * p3.x,
      y: b0 * p0.y + b1 * p1.y + b2 * p2.y + b3 * p3.y)
  }
}

/// Fits smooth cubic beziers to a point stream (Schneider, "An Algorithm for Automatically Fitting Digitized
/// Curves"): least-squares control points, Newton-Raphson reparameterization and recursive splitting. Sharp
/// corners are detected first and each run between corners is fitted on its own so corners stay sharp.
public enum BezierFitter {
  /// Turn angle (radians) above which a point counts as a corner.
  static let cornerAngle = 75.0 * .pi / 180

  /// Fits `points` within `maxError` document units. Fewer than two distinct points yield no segments.
  public static func fit(_ points: [CGPoint], maxError: Double = 2.0) -> [BezierSegment] {
    let cleaned = deduplicated(points)
    guard cleaned.count >= 2 else { return [] }
    let tolerance = maxError.isFinite ? max(maxError, 0.01) : 2.0

    var segments: [BezierSegment] = []
    var start = 0
    for corner in cornerIndices(in: cleaned) + [cleaned.count - 1] {
      let run = Array(cleaned[start...corner])
      if run.count >= 2 {
        let t1 = unit(run[1] - run[0]) ?? .zero
        let t2 = unit(run[run.count - 2] - run[run.count - 1]) ?? .zero
        segments += fitCubic(run, t1, t2, tolerance * tolerance)
      }
      start = corner
    }
    return segments
  }

  // MARK: corner detection

  private static func deduplicated(_ points: [CGPoint]) -> [CGPoint] {
    var result: [CGPoint] = []
    for p in points where p.x.isFinite && p.y.isFinite {
      if let last = result.last, last.distance(to: p) < 1e-6 { continue }
      result.append(p)
    }
    return result
  }

  /// Indices of interior points whose turn angle exceeds `cornerAngle` and is a local maximum.
  private static func cornerIndices(in pts: [CGPoint]) -> [Int] {
    let k = 2
    guard pts.count > 2 * k else { return [] }
    var angles = [Double](repeating: 0, count: pts.count)
    for i in k..<(pts.count - k) {
      guard let back = unit(pts[i] - pts[i - k]), let fwd = unit(pts[i + k] - pts[i]) else { continue }
      angles[i] = acos(max(-1, min(1, dot(back, fwd))))
    }
    var corners: [Int] = []
    for i in k..<(pts.count - k) where angles[i] > cornerAngle {
      let window = max(k, i - k)...min(pts.count - k - 1, i + k)
      guard window.allSatisfy({ angles[$0] <= angles[i] }) else { continue }
      // Equal neighbours form a plateau: keep only its first point.
      if let previous = corners.last, i - previous <= k { continue }
      corners.append(i)
    }
    return corners
  }

  // MARK: Schneider fitting

  /// Fits one run. `t1` points from the first point into the curve, `t2` from the last point back into it.
  private static func fitCubic(_ d: [CGPoint], _ t1: CGPoint, _ t2: CGPoint, _ errorSquared: Double)
    -> [BezierSegment]
  {
    if d.count == 2 {
      let third = d[0].distance(to: d[1]) / 3
      return [BezierSegment(d[0], d[0] + scaled(t1, third), d[1] + scaled(t2, third), d[1])]
    }

    var u = chordLengthParameters(d)
    var segment = generateBezier(d, u, t1, t2)
    var (maxError, split) = maxDeviation(d, segment, u)
    if maxError < errorSquared { return [segment] }

    if maxError < errorSquared * 16 {
      for _ in 0..<4 {
        u = zip(d, u).map { newtonRaphson(segment, $0, $1) }
        segment = generateBezier(d, u, t1, t2)
        (maxError, split) = maxDeviation(d, segment, u)
        if maxError < errorSquared { return [segment] }
      }
    }

    // Keep both halves non-empty and strictly inside the run.
    split = min(max(split, 1), d.count - 2)
    let center = unit(d[split - 1] - d[split + 1]) ?? unit(d[split - 1] - d[split]) ?? .zero
    let left = fitCubic(Array(d[0...split]), t1, center, errorSquared)
    let right = fitCubic(Array(d[split...]), scaled(center, -1), t2, errorSquared)
    return left + right
  }

  private static func generateBezier(_ d: [CGPoint], _ u: [Double], _ t1: CGPoint, _ t2: CGPoint)
    -> BezierSegment
  {
    let first = d[0]
    let last = d[d.count - 1]
    var c00 = 0.0
    var c01 = 0.0
    var c11 = 0.0
    var x0 = 0.0
    var x1 = 0.0
    for i in 0..<d.count {
      let t = u[i]
      let s = 1 - t
      let b0 = s * s * s
      let b1 = 3 * t * s * s
      let b2 = 3 * t * t * s
      let b3 = t * t * t
      let a1 = scaled(t1, b1)
      let a2 = scaled(t2, b2)
      c00 += dot(a1, a1)
      c01 += dot(a1, a2)
      c11 += dot(a2, a2)
      let rest = CGPoint(
        x: d[i].x - (first.x * (b0 + b1) + last.x * (b2 + b3)),
        y: d[i].y - (first.y * (b0 + b1) + last.y * (b2 + b3)))
      x0 += dot(a1, rest)
      x1 += dot(a2, rest)
    }

    let det = c00 * c11 - c01 * c01
    let chord = first.distance(to: last)
    var alpha1 = 0.0
    var alpha2 = 0.0
    if abs(det) > 1e-12 {
      alpha1 = (x0 * c11 - x1 * c01) / det
      alpha2 = (c00 * x1 - c01 * x0) / det
    }
    // Degenerate or backwards solution: fall back to the Wu/Barsky heuristic.
    let epsilon = 1e-6 * chord
    if !alpha1.isFinite || !alpha2.isFinite || alpha1 < epsilon || alpha2 < epsilon {
      alpha1 = chord / 3
      alpha2 = chord / 3
    }
    return BezierSegment(first, first + scaled(t1, alpha1), last + scaled(t2, alpha2), last)
  }

  private static func chordLengthParameters(_ d: [CGPoint]) -> [Double] {
    var u = [0.0]
    for i in 1..<d.count { u.append(u[i - 1] + d[i].distance(to: d[i - 1])) }
    let total = u[u.count - 1]
    guard total > 0 else { return u.indices.map { Double($0) / Double(max(1, u.count - 1)) } }
    return u.map { $0 / total }
  }

  /// Largest squared distance between a point and the curve at its parameter, with the index where it occurs.
  private static func maxDeviation(_ d: [CGPoint], _ s: BezierSegment, _ u: [Double]) -> (Double, Int) {
    var worst = 0.0
    var index = d.count / 2
    for i in 1..<(d.count - 1) {
      let p = s.point(at: u[i])
      let dx = p.x - d[i].x
      let dy = p.y - d[i].y
      let dist = dx * dx + dy * dy
      if dist >= worst {
        worst = dist
        index = i
      }
    }
    return (worst, index)
  }

  private static func newtonRaphson(_ s: BezierSegment, _ p: CGPoint, _ t: Double) -> Double {
    let q = s.point(at: t)
    let u = 1 - t
    // First and second derivatives of the curve at t.
    let q1 = CGPoint(
      x: 3 * (u * u * (s.p1.x - s.p0.x) + 2 * u * t * (s.p2.x - s.p1.x) + t * t * (s.p3.x - s.p2.x)),
      y: 3 * (u * u * (s.p1.y - s.p0.y) + 2 * u * t * (s.p2.y - s.p1.y) + t * t * (s.p3.y - s.p2.y)))
    let q2 = CGPoint(
      x: 6 * (u * (s.p2.x - 2 * s.p1.x + s.p0.x) + t * (s.p3.x - 2 * s.p2.x + s.p1.x)),
      y: 6 * (u * (s.p2.y - 2 * s.p1.y + s.p0.y) + t * (s.p3.y - 2 * s.p2.y + s.p1.y)))
    let diff = q - p
    let numerator = dot(diff, q1)
    let denominator = dot(q1, q1) + dot(diff, q2)
    guard abs(denominator) > 1e-12 else { return t }
    let next = t - numerator / denominator
    return next.isFinite ? min(1, max(0, next)) : t
  }

  // MARK: small vector helpers

  private static func dot(_ a: CGPoint, _ b: CGPoint) -> Double { a.x * b.x + a.y * b.y }
  private static func scaled(_ p: CGPoint, _ f: Double) -> CGPoint { CGPoint(x: p.x * f, y: p.y * f) }

  private static func unit(_ v: CGPoint) -> CGPoint? {
    let length = hypot(v.x, v.y)
    guard length > 1e-12, length.isFinite else { return nil }
    return CGPoint(x: v.x / length, y: v.y / length)
  }
}
