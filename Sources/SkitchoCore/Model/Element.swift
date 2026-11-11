import CoreGraphics
import Foundation

/// Text payload of a text element. `origin` is the top-left corner in document space.
public struct TextContent: Sendable, Equatable, Codable {
  public var string: String
  public var origin: CGPoint
  public var wrapWidth: Double?
  /// Styled text has a contrasting outline ("bubble"); plain text is fill only.
  public var styled: Bool

  public init(string: String, origin: CGPoint, wrapWidth: Double? = nil, styled: Bool = true) {
    self.string = string
    self.origin = origin
    self.wrapWidth = wrapWidth
    self.styled = styled
  }

  /// Rough text extent used for bounds until the CoreText measurer exists. Monospace-ish estimate.
  func estimatedSize(fontSize: Double) -> CGSize {
    let glyph = fontSize * 0.55
    let lineHeight = fontSize * 1.2
    let lines = string.split(separator: "\n", omittingEmptySubsequences: false)
    let longest = Double(lines.map(\.count).max() ?? 0)
    guard let wrap = wrapWidth, wrap > 0 else {
      return CGSize(width: max(glyph, longest * glyph), height: Double(max(1, lines.count)) * lineHeight)
    }
    let perLine = max(1, (wrap / glyph).rounded(.down))
    let rows = lines.reduce(0.0) { $0 + max(1, (Double($1.count) / perLine).rounded(.up)) }
    return CGSize(width: wrap, height: max(1, rows) * lineHeight)
  }
}

/// The geometry of an element, stored in document space (top-left origin, y-down).
public enum ElementKind: Sendable, Equatable, Codable {
  case arrow(start: CGPoint, end: CGPoint, doubleHeaded: Bool)
  case line(start: CGPoint, end: CGPoint)
  case rect(CGRect, rounded: Bool)
  case ellipse(CGRect)
  case freehand(segments: [BezierSegment], highlighter: Bool)
  case text(TextContent)
  case stamp(StampKind, center: CGPoint, tailAngle: Double?, labelID: UUID?)
}

/// One annotation. `rotation` (radians, about the center of `baseBounds`) is used by rect, rounded rect,
/// ellipse, text and stamp; it stays 0 for the other kinds.
public struct Element: Sendable, Equatable, Codable, Identifiable {
  public var id: UUID
  public var kind: ElementKind
  public var style: Style
  public var rotation: Double

  public init(id: UUID = UUID(), kind: ElementKind, style: Style, rotation: Double = 0) {
    self.id = id
    self.kind = kind
    self.style = style
    self.rotation = rotation
  }

  // MARK: Bounds

  /// Geometric bounds before `rotation` is applied (stroke width is not included).
  public var baseBounds: CGRect {
    switch kind {
    case .arrow(let start, let end, let doubleHeaded):
      let path = ArrowPath.make(from: start, to: end, width: style.strokeWidth, doubleHeaded: doubleHeaded)
      return path.isEmpty ? Element.rect(spanning: start, end) : path.boundingBoxOfPath
    case .line(let start, let end):
      return Element.rect(spanning: start, end)
    case .rect(let rect, _), .ellipse(let rect):
      return rect.standardized
    case .freehand(let segments, _):
      return Element.bounds(of: segments)
    case .text(let content):
      return CGRect(origin: content.origin, size: content.estimatedSize(fontSize: style.fontSize))
    case .stamp(_, let center, let tailAngle, _):
      let radius = StampKind.radius(strokeWidth: style.strokeWidth)
      var box = CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius)
      if let tip = Element.tailTip(center: center, radius: radius, angle: tailAngle) {
        box = box.union(CGRect(origin: tip, size: .zero))
      }
      return box
    }
  }

  /// Axis-aligned bounds including `rotation`.
  public var bounds: CGRect {
    let base = baseBounds
    guard rotation != 0 else { return base }
    let pivot = base.center
    let corners = [
      CGPoint(x: base.minX, y: base.minY), CGPoint(x: base.maxX, y: base.minY),
      CGPoint(x: base.maxX, y: base.maxY), CGPoint(x: base.minX, y: base.maxY),
    ].map { GeometryMath.rotate($0, about: pivot, by: rotation) }
    return Element.rect(containing: corners)
  }

  // MARK: Hit testing

  /// True when `point` hits the element. `tolerance` is in document units. Shapes hit on their outline only.
  public func hitTest(point: CGPoint, tolerance: Double) -> Bool {
    switch kind {
    case .arrow(let start, let end, let doubleHeaded):
      let path = ArrowPath.make(from: start, to: end, width: style.strokeWidth, doubleHeaded: doubleHeaded)
      return HitTest.filled(path: path, point: point, tolerance: tolerance)
    case .line(let start, let end):
      return HitTest.stroke(
        path: ShapePaths.line(from: start, to: end), strokeWidth: style.strokeWidth, point: point,
        tolerance: tolerance)
    case .rect(let rect, let rounded):
      return HitTest.stroke(
        path: ShapePaths.rect(rect, rounded: rounded, rotation: rotation), strokeWidth: style.strokeWidth,
        point: point, tolerance: tolerance)
    case .ellipse(let rect):
      return HitTest.stroke(
        path: ShapePaths.ellipse(rect, rotation: rotation), strokeWidth: style.strokeWidth, point: point,
        tolerance: tolerance)
    case .freehand(let segments, _):
      return HitTest.stroke(
        path: ShapePaths.freehand(segments), strokeWidth: style.strokeWidth, point: point, tolerance: tolerance)
    case .text:
      let local = unrotated(point)
      return baseBounds.insetBy(dx: -tolerance, dy: -tolerance).contains(local)
    case .stamp(_, let center, let tailAngle, _):
      let local = unrotated(point)
      let radius = StampKind.radius(strokeWidth: style.strokeWidth)
      if local.distance(to: center) <= radius + tolerance { return true }
      guard let tip = Element.tailTip(center: center, radius: radius, angle: tailAngle) else { return false }
      return GeometryMath.distance(from: local, toSegment: center, tip) <= radius * 0.4 + tolerance
    }
  }

  // MARK: Transforms

  /// A copy moved by `delta`.
  public func translated(by delta: CGPoint) -> Element {
    var copy = self
    copy.kind = mapGeometry({ $0 + delta }, size: { $0 })
    return copy
  }

  /// A copy whose geometry is scaled by `factor` about `anchor`. Rotation and style are left alone;
  /// callers that resize the image scale the style separately with `Style.scaled(by:)`.
  public func scaled(by factor: Double, about anchor: CGPoint) -> Element {
    var copy = self
    copy.kind = mapGeometry(
      { CGPoint(x: anchor.x + ($0.x - anchor.x) * factor, y: anchor.y + ($0.y - anchor.y) * factor) },
      size: { $0 * factor })
    return copy
  }

  /// Rebuilds `kind` with every point mapped by `point` and every length mapped by `size`.
  private func mapGeometry(_ point: (CGPoint) -> CGPoint, size: (Double) -> Double) -> ElementKind {
    func rect(_ value: CGRect) -> CGRect {
      let r = value.standardized
      return CGRect(origin: point(r.origin), size: CGSize(width: size(r.width), height: size(r.height)))
    }
    switch kind {
    case .arrow(let start, let end, let doubleHeaded):
      return .arrow(start: point(start), end: point(end), doubleHeaded: doubleHeaded)
    case .line(let start, let end):
      return .line(start: point(start), end: point(end))
    case .rect(let value, let rounded):
      return .rect(rect(value), rounded: rounded)
    case .ellipse(let value):
      return .ellipse(rect(value))
    case .freehand(let segments, let highlighter):
      let mapped = segments.map { BezierSegment(point($0.p0), point($0.p1), point($0.p2), point($0.p3)) }
      return .freehand(segments: mapped, highlighter: highlighter)
    case .text(var content):
      content.origin = point(content.origin)
      content.wrapWidth = content.wrapWidth.map(size)
      return .text(content)
    case .stamp(let stamp, let center, let tailAngle, let labelID):
      return .stamp(stamp, center: point(center), tailAngle: tailAngle, labelID: labelID)
    }
  }

  // MARK: Helpers

  /// Maps a point from document space into the element's unrotated frame.
  private func unrotated(_ point: CGPoint) -> CGPoint {
    guard rotation != 0 else { return point }
    return GeometryMath.rotate(point, about: baseBounds.center, by: -rotation)
  }

  /// Tip of a stamp's tail, or nil when there is no tail.
  static func tailTip(center: CGPoint, radius: Double, angle: Double?) -> CGPoint? {
    guard let angle else { return nil }
    let reach = radius * (1 + StampKind.tailExtension)
    return CGPoint(x: center.x + reach * cos(angle), y: center.y + reach * sin(angle))
  }

  private static func rect(spanning a: CGPoint, _ b: CGPoint) -> CGRect {
    CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
  }

  private static func rect(containing points: [CGPoint]) -> CGRect {
    guard let first = points.first else { return .zero }
    return points.dropFirst().reduce(CGRect(origin: first, size: .zero)) {
      $0.union(CGRect(origin: $1, size: .zero))
    }
  }

  /// Bounds of the sampled curves (tight enough for selection handles and marquee tests).
  private static func bounds(of segments: [BezierSegment]) -> CGRect {
    var points: [CGPoint] = []
    for segment in segments {
      for step in 0...16 { points.append(segment.point(at: Double(step) / 16)) }
    }
    return rect(containing: points)
  }
}
