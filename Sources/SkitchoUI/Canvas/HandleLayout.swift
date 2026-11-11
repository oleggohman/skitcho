import CoreGraphics
import Foundation
import SkitchoCore

/// A draggable handle on the selected element.
enum Handle: Hashable, Sendable {
  case topLeft, top, topRight, left, right, bottomLeft, bottom, bottomRight
  case rotate
  /// Arrow and line endpoints.
  case start, end

  /// Which sides move for a resize handle: -1 = min edge, +1 = max edge, 0 = that axis is untouched.
  fileprivate var direction: (x: Int, y: Int)? {
    switch self {
    case .topLeft: (-1, -1)
    case .top: (0, -1)
    case .topRight: (1, -1)
    case .left: (-1, 0)
    case .right: (1, 0)
    case .bottomLeft: (-1, 1)
    case .bottom: (0, 1)
    case .bottomRight: (1, 1)
    case .rotate, .start, .end: nil
    }
  }
}

/// Where the handles of an element sit, which one a point hits, and what dragging one does.
///
/// Everything is pure and in document space so tests and the select/shape/freehand controllers share one
/// implementation. Handles of rotated elements follow the rotation (rotation is about the center of
/// `baseBounds`, matching `Element.hitTest` and the renderer).
enum HandleLayout {
  /// Handle square side in view points.
  static let handleSide: Double = 8
  /// Extra hit radius around a handle center in view points.
  static let hitRadius: Double = 8
  /// Distance of the rotate handle above the top edge in view points.
  static let rotateOffset: Double = 24
  /// Smallest side a resize can produce, in document units.
  static let minimumSide: Double = 1

  private static let corners: [Handle] = [.topLeft, .topRight, .bottomLeft, .bottomRight]
  private static let allEight: [Handle] = [
    .topLeft, .top, .topRight, .left, .right, .bottomLeft, .bottom, .bottomRight,
  ]

  /// The handles `element` offers.
  static func available(for element: Element) -> [Handle] {
    switch element.kind {
    case .arrow, .line: [.start, .end]
    case .rect, .ellipse: allEight + [.rotate]
    case .text, .stamp: corners + [.rotate]
    case .freehand: allEight
    }
  }

  /// Handles with their document-space centers at the given zoom.
  static func handles(for element: Element, zoom: Double) -> [(handle: Handle, point: CGPoint)] {
    available(for: element).compactMap { handle in
      position(of: handle, on: element, zoom: zoom).map { (handle, $0) }
    }
  }

  static func position(of handle: Handle, on element: Element, zoom: Double) -> CGPoint? {
    switch handle {
    case .start, .end:
      switch element.kind {
      case .arrow(let start, let end, _), .line(let start, let end): return handle == .start ? start : end
      default: return nil
      }
    case .rotate:
      let base = element.baseBounds
      let local = CGPoint(x: base.midX, y: base.minY - rotateOffset / max(zoom, 0.0001))
      return GeometryMath.rotate(local, about: base.center, by: element.rotation)
    default:
      guard let direction = handle.direction else { return nil }
      let base = element.baseBounds
      let local = CGPoint(
        x: direction.x < 0 ? base.minX : direction.x > 0 ? base.maxX : base.midX,
        y: direction.y < 0 ? base.minY : direction.y > 0 ? base.maxY : base.midY)
      return GeometryMath.rotate(local, about: base.center, by: element.rotation)
    }
  }

  /// The handle of `element` under `point`, preferring the closest one.
  static func hit(_ element: Element, at point: CGPoint, zoom: Double) -> Handle? {
    let radius = hitRadius / max(zoom, 0.0001)
    return handles(for: element, zoom: zoom)
      .map { ($0.handle, $0.point.distance(to: point)) }
      .filter { $0.1 <= radius }
      .min { $0.1 < $1.1 }?.0
  }

  /// The commit name for a drag of `handle`.
  static func undoName(for handle: Handle) -> String {
    switch handle {
    case .rotate: "Rotate"
    case .start, .end: "Move Endpoint"
    default: "Resize"
    }
  }

  // MARK: Dragging

  /// `original` with `handle` dragged to `pointer`. Shift snaps rotation and line angles to 15 degrees and
  /// keeps the aspect ratio when resizing a box from a corner.
  static func apply(
    _ handle: Handle, to original: Element, pointer: CGPoint, modifiers: ToolModifiers
  ) -> Element {
    switch handle {
    case .start, .end: return moveEndpoint(handle, of: original, to: pointer, modifiers: modifiers)
    case .rotate: return rotate(original, pointer: pointer, modifiers: modifiers)
    default: return resize(handle, of: original, pointer: pointer, modifiers: modifiers)
    }
  }

  private static func moveEndpoint(
    _ handle: Handle, of original: Element, to pointer: CGPoint, modifiers: ToolModifiers
  ) -> Element {
    var element = original
    func moved(fixed: CGPoint) -> CGPoint {
      modifiers.contains(.shift) ? GeometryMath.snapped(pointer, from: fixed) : pointer
    }
    switch original.kind {
    case .arrow(let start, let end, let doubleHeaded):
      element.kind =
        handle == .start
        ? .arrow(start: moved(fixed: end), end: end, doubleHeaded: doubleHeaded)
        : .arrow(start: start, end: moved(fixed: start), doubleHeaded: doubleHeaded)
    case .line(let start, let end):
      element.kind =
        handle == .start ? .line(start: moved(fixed: end), end: end) : .line(start: start, end: moved(fixed: start))
    default:
      break
    }
    return element
  }

  private static func rotate(_ original: Element, pointer: CGPoint, modifiers: ToolModifiers) -> Element {
    var element = original
    let center = original.baseBounds.center
    // The handle sits straight above the center at rotation 0 (angle -pi/2 in y-down space).
    var angle = atan2(pointer.y - center.y, pointer.x - center.x) + .pi / 2
    if modifiers.contains(.shift) { angle = GeometryMath.snapAngle(angle) }
    element.rotation = normalized(angle)
    return element
  }

  /// Wraps an angle into (-pi, pi].
  static func normalized(_ angle: Double) -> Double {
    var value = angle.truncatingRemainder(dividingBy: 2 * .pi)
    if value > .pi { value -= 2 * .pi }
    if value <= -.pi { value += 2 * .pi }
    return value
  }

  private static func resize(
    _ handle: Handle, of original: Element, pointer: CGPoint, modifiers: ToolModifiers
  ) -> Element {
    guard let direction = handle.direction else { return original }
    let base = original.baseBounds
    let pivot = base.center
    let local = GeometryMath.rotate(pointer, about: pivot, by: -original.rotation)
    let anchor = CGPoint(
      x: direction.x < 0 ? base.maxX : direction.x > 0 ? base.minX : base.midX,
      y: direction.y < 0 ? base.maxY : direction.y > 0 ? base.minY : base.midY)

    switch original.kind {
    case .text, .stamp:
      return scaleUniformly(original, anchor: anchor, local: local, direction: direction, base: base)
    default:
      break
    }

    // New rectangle in the element's unrotated frame; the opposite edge/corner stays at `anchor`.
    var minX = base.minX
    var maxX = base.maxX
    var minY = base.minY
    var maxY = base.maxY
    if direction.x != 0 {
      minX = min(anchor.x, local.x)
      maxX = max(anchor.x, local.x)
    }
    if direction.y != 0 {
      minY = min(anchor.y, local.y)
      maxY = max(anchor.y, local.y)
    }
    var width = max(maxX - minX, minimumSide)
    var height = max(maxY - minY, minimumSide)
    let keepsAspect = modifiers.contains(.shift) && direction.x != 0 && direction.y != 0
    if keepsAspect, base.width > 0, base.height > 0 {
      let factor = max(width / base.width, height / base.height)
      width = base.width * factor
      height = base.height * factor
    }
    let signX = local.x >= anchor.x ? 1.0 : -1.0
    let signY = local.y >= anchor.y ? 1.0 : -1.0
    if direction.x != 0 { minX = signX > 0 ? anchor.x : anchor.x - width }
    if direction.y != 0 { minY = signY > 0 ? anchor.y : anchor.y - height }
    let newLocal = CGRect(
      x: direction.x != 0 ? minX : base.minX, y: direction.y != 0 ? minY : base.minY,
      width: direction.x != 0 ? width : base.width, height: direction.y != 0 ? height : base.height)

    var element = original
    switch original.kind {
    case .rect(_, let rounded):
      element.kind = .rect(recentered(newLocal, about: pivot, rotation: original.rotation), rounded: rounded)
    case .ellipse:
      element.kind = .ellipse(recentered(newLocal, about: pivot, rotation: original.rotation))
    case .freehand(let segments, let highlighter):
      let sx = base.width > 1e-9 ? newLocal.width / base.width : 1
      let sy = base.height > 1e-9 ? newLocal.height / base.height : 1
      func map(_ p: CGPoint) -> CGPoint {
        CGPoint(x: newLocal.minX + (p.x - base.minX) * sx, y: newLocal.minY + (p.y - base.minY) * sy)
      }
      let mapped = segments.map { BezierSegment(map($0.p0), map($0.p1), map($0.p2), map($0.p3)) }
      element.kind = .freehand(segments: mapped, highlighter: highlighter)
    default:
      break
    }
    return element
  }

  /// `local` (a rect in the unrotated frame about `pivot`) as the stored rect: same size, centered where the
  /// rotated center lands, so the opposite corner stays put on screen.
  private static func recentered(_ local: CGRect, about pivot: CGPoint, rotation: Double) -> CGRect {
    let center = GeometryMath.rotate(local.center, about: pivot, by: rotation)
    return CGRect(
      x: center.x - local.width / 2, y: center.y - local.height / 2, width: local.width, height: local.height)
  }

  /// Text and stamps scale uniformly (geometry and frozen style) about the opposite corner.
  private static func scaleUniformly(
    _ original: Element, anchor: CGPoint, local: CGPoint, direction: (x: Int, y: Int), base: CGRect
  ) -> Element {
    let corner = CGPoint(x: direction.x > 0 ? base.maxX : base.minX, y: direction.y > 0 ? base.maxY : base.minY)
    let axis = corner - anchor
    let lengthSquared = axis.x * axis.x + axis.y * axis.y
    guard lengthSquared > 1e-12 else { return original }
    let offset = local - anchor
    let factor = max((offset.x * axis.x + offset.y * axis.y) / lengthSquared, 0.05)
    var element = original
    element.style = original.style.scaled(by: factor)
    element.kind = original.scaled(by: factor, about: anchor).kind
    let pivot = base.center
    let worldCenter = GeometryMath.rotate(element.baseBounds.center, about: pivot, by: original.rotation)
    let shift = worldCenter - element.baseBounds.center
    return element.translated(by: shift)
  }
}

extension CGPoint {
  fileprivate static func - (lhs: CGPoint, rhs: CGPoint) -> CGPoint { CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y) }
  fileprivate func distance(to other: CGPoint) -> Double { hypot(x - other.x, y - other.y) }
}

extension CGRect {
  fileprivate var center: CGPoint { CGPoint(x: midX, y: midY) }
}
