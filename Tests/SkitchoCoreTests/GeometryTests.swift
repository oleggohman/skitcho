import CoreGraphics
import Foundation
import Testing

@testable import SkitchoCore

@Suite struct GeometryTests {
  // MARK: arrow

  @Test func arrowHeadGrowsWithWidthAndIsCapped() {
    #expect(ArrowPath.headLength(width: 10, length: 1000) == 40)
    #expect(ArrowPath.headLength(width: 20, length: 1000) == 80)
    // Capped at 0.4 * length.
    #expect(abs(ArrowPath.headLength(width: 10, length: 50) - 20) < 1e-9)
    // The minimum length is 9w and does not follow the head factor.
    #expect(ArrowPath.minimumLength(width: 10) == 90)
    #expect(ArrowPath.minimumLength(width: 0) == 0)
  }

  @Test func arrowTipAndHeadCapInPath() {
    let path = ArrowPath.make(from: .zero, to: CGPoint(x: 50, y: 0), width: 10)
    let box = path.boundingBoxOfPath
    #expect(abs(box.maxX - 50) < 1e-9)
    // The round tail cap reaches half the tail width behind the start (0.15 * 10 = 1.5).
    #expect(abs(box.minX + 1.5) < 1e-9)
    // Head base is at x = 50 - 20 = 30 (0.4 cap); the barbs are swept back to x = 27.
    #expect(path.contains(CGPoint(x: 49, y: 0)))
    #expect(!path.contains(CGPoint(x: 49, y: 5)))
    #expect(path.contains(CGPoint(x: 31, y: 10)))
  }

  @Test func arrowIsSymmetricAboutItsAxis() {
    let path = ArrowPath.make(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 210, y: 10), width: 12)
    for x in stride(from: 15.0, to: 205.0, by: 17.0) {
      for dy in stride(from: 0.5, to: 12.0, by: 1.5) {
        let up = path.contains(CGPoint(x: x, y: 10 - dy))
        let down = path.contains(CGPoint(x: x, y: 10 + dy))
        #expect(up == down)
      }
    }
    let box = path.boundingBoxOfPath
    #expect(abs(box.midY - 10) < 1e-9)
  }

  @Test func arrowTapersFromTailToHead() {
    let path = ArrowPath.make(from: .zero, to: CGPoint(x: 300, y: 0), width: 20)
    // Half-width near the tail is smaller than just before the head.
    #expect(path.contains(CGPoint(x: 2, y: 2)))
    #expect(!path.contains(CGPoint(x: 2, y: 4)))
    #expect(path.contains(CGPoint(x: 200, y: 8)))
    #expect(path.contains(CGPoint(x: 230, y: 12)))
  }

  @Test func arrowRotatesWithDirection() {
    let path = ArrowPath.make(from: .zero, to: CGPoint(x: 0, y: 100), width: 10)
    let box = path.boundingBoxOfPath
    #expect(abs(box.maxY - 100) < 1e-9)
    #expect(abs(box.width - 56) < 1e-6)  // head half-width = 0.7 * 40
  }

  @Test func doubleHeadedHasHeadAtStart() {
    let single = ArrowPath.make(from: .zero, to: CGPoint(x: 200, y: 0), width: 10)
    let double = ArrowPath.make(from: .zero, to: CGPoint(x: 200, y: 0), width: 10, doubleHeaded: true)
    // Near the start a head is wide, a single-headed tail is thin.
    let probe = CGPoint(x: 28, y: 12)
    #expect(!single.contains(probe))
    #expect(double.contains(probe))
  }

  @Test func shortWideArrowShaftIsNeverWiderThanItsHead() {
    // Length 15 at width 20: the head is capped at 6 long, so its half-width is 4.2 (< 0.45 * width = 9).
    for doubleHeaded in [false, true] {
      let path = ArrowPath.make(from: .zero, to: CGPoint(x: 15, y: 0), width: 20, doubleHeaded: doubleHeaded)
      let headHalf = ArrowPath.headLength(width: 20, length: 15) * 0.7
      #expect(abs(path.boundingBoxOfPath.height - 2 * headHalf) < 1e-9, "\(path.boundingBoxOfPath)")
    }
  }

  /// Vertices of the straight segments of `path` (move and line elements), in the path's own space.
  private func vertices(of path: CGPath) -> [CGPoint] {
    var points: [CGPoint] = []
    path.applyWithBlock { element in
      let kind = element.pointee.type
      if kind == .moveToPoint || kind == .addLineToPoint { points.append(element.pointee.points[0]) }
    }
    return points
  }

  private func has(_ points: [CGPoint], _ x: Double, _ y: Double) -> Bool {
    points.contains { abs($0.x - x) < 1e-9 && abs($0.y - y) < 1e-9 }
  }

  @Test func arrowNumbersArePinned() {
    // w = 10, length 300: head 40, head half-width 28, barb sweep 6, base half 4.5, tail half 1.5.
    let single = vertices(of: ArrowPath.make(from: .zero, to: CGPoint(x: 300, y: 0), width: 10))
    #expect(has(single, 300, 0))  // tip
    #expect(has(single, 254, 28) && has(single, 254, -28))  // swept barbs: head base 260 - 0.15 * 40
    #expect(has(single, 260, 4.5) && has(single, 260, -4.5))  // shaft half-width at the head base
    #expect(has(single, 0, 1.5) && has(single, 0, -1.5))  // tail half-width

    let double = vertices(of: ArrowPath.make(from: .zero, to: CGPoint(x: 300, y: 0), width: 10, doubleHeaded: true))
    #expect(has(double, 0, 0) && has(double, 300, 0))
    #expect(has(double, 46, 28) && has(double, 254, -28))
    #expect(has(double, 40, 4.5) && has(double, 260, -4.5))
  }

  @Test func arrowTailHasARoundCap() {
    let path = ArrowPath.make(from: .zero, to: CGPoint(x: 300, y: 0), width: 20)
    // Tail half-width 3: the cap bulges 3 behind the start and stays round (a corner would contain (-2.2, 2.2)).
    #expect(path.contains(CGPoint(x: -2.5, y: 0)))
    #expect(!path.contains(CGPoint(x: -3.5, y: 0)))
    #expect(!path.contains(CGPoint(x: -2.2, y: 2.2)))
  }

  @Test func arrowOutlineWidthScalesWithStrokeWithAFloor() {
    #expect(ArrowPath.outlineWidth(width: 4) == 3)  // floor: 2 * 1.5
    #expect(abs(ArrowPath.outlineWidth(width: 20) - 4.8) < 1e-9)  // 2 * 0.12 * 20
  }

  @Test func shortDoubleHeadedArrowOutlineDoesNotSelfIntersect() {
    for length in [9.0, 15, 30, 60] {
      for width in [4.0, 10, 20] {
        let path = ArrowPath.make(from: .zero, to: CGPoint(x: length, y: 0), width: width, doubleHeaded: true)
        var points = vertices(of: path)
        if points.count > 1, points.first == points.last { points.removeLast() }
        #expect(points.count == 10)
        expectNoSelfIntersection(path, "length \(length) width \(width)")
      }
    }
  }

  @Test func shortWideSingleHeadedArrowOutlineDoesNotSelfIntersect() {
    // Below about 1.6w the head is capped and the shaft would reach the barbs (e.g. length 90 at width 100).
    for length in [9.0, 15, 30, 60, 90, 150] {
      for width in [4.0, 10, 20, 100] {
        let path = ArrowPath.make(from: .zero, to: CGPoint(x: length, y: 0), width: width)
        expectNoSelfIntersection(path, "length \(length) width \(width)")
      }
    }
  }

  @Test func shaftStaysInsideTheHeadAtTheHeadBase() {
    // Length 90 at width 100: head 36, half-width 25.2, barb sweep 5.4. At the head base (x = 54) the barb edge
    // is at 25.2 / 1.15 = 21.9, so the shaft half-width there (0.75 * 25.2 = 18.9) must be below it.
    let points = vertices(of: ArrowPath.make(from: .zero, to: CGPoint(x: 90, y: 0), width: 100))
    #expect(has(points, 54, 18.9) && has(points, 54, -18.9))
    #expect(has(points, 48.6, 25.2) && has(points, 90, 0))
  }

  /// Checks the straight edges of `path` (the round tail cap is not a vertex) for proper crossings.
  private func expectNoSelfIntersection(_ path: CGPath, _ label: String) {
    var points = vertices(of: path)
    if points.count > 1, points.first == points.last { points.removeLast() }
    let count = points.count
    #expect(count >= 4, "\(label)")
    for i in 0..<count {
      for j in (i + 1)..<count {
        // Edges i -> i+1 and j -> j+1; adjacent edges share a vertex and are skipped.
        let adjacent = j == i + 1 || (i == 0 && j == count - 1)
        if adjacent { continue }
        let crossing = segmentsIntersect(
          points[i], points[(i + 1) % count], points[j], points[(j + 1) % count])
        #expect(!crossing, "\(label): edge \(i) crosses edge \(j)")
      }
    }
  }

  /// Proper (interior) intersection of segments p1-p2 and p3-p4.
  private func segmentsIntersect(_ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, _ p4: CGPoint) -> Bool {
    func cross(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Double {
      (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
    }
    let d1 = cross(p3, p4, p1)
    let d2 = cross(p3, p4, p2)
    let d3 = cross(p1, p2, p3)
    let d4 = cross(p1, p2, p4)
    return d1 * d2 < -1e-9 && d3 * d4 < -1e-9
  }

  @Test func zeroLengthOrWidthArrowIsEmpty() {
    #expect(ArrowPath.make(from: CGPoint(x: 5, y: 5), to: CGPoint(x: 5, y: 5), width: 10).isEmpty)
    #expect(ArrowPath.make(from: .zero, to: CGPoint(x: 50, y: 0), width: 0).isEmpty)
    #expect(ArrowPath.make(from: .zero, to: CGPoint(x: 50, y: 0), width: -3).isEmpty)
  }

  // MARK: shapes

  @Test func rectAndEllipseBounds() {
    let rect = CGRect(x: 10, y: 20, width: 100, height: 50)
    #expect(ShapePaths.rect(rect).boundingBoxOfPath == rect)
    #expect(ShapePaths.ellipse(rect).boundingBoxOfPath == rect)
    // A negative-size rect is standardized.
    let flipped = CGRect(x: 110, y: 70, width: -100, height: -50)
    #expect(ShapePaths.rect(flipped).boundingBoxOfPath == rect)
  }

  @Test func roundedRectCutsCorners() {
    let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
    #expect(ShapePaths.rect(rect).contains(CGPoint(x: 1, y: 1)))
    #expect(!ShapePaths.rect(rect, rounded: true).contains(CGPoint(x: 1, y: 1)))
    #expect(ShapePaths.rect(rect, rounded: true).contains(CGPoint(x: 50, y: 50)))
  }

  @Test func rotationIsAboutCenter() {
    let rect = CGRect(x: 0, y: 0, width: 100, height: 20)
    let path = ShapePaths.rect(rect, rotation: .pi / 2)
    let box = path.boundingBoxOfPath
    #expect(abs(box.midX - 50) < 1e-9)
    #expect(abs(box.midY - 10) < 1e-9)
    #expect(abs(box.width - 20) < 1e-9)
    #expect(abs(box.height - 100) < 1e-9)
    let ellipse = ShapePaths.ellipse(rect, rotation: .pi / 2).boundingBoxOfPath
    #expect(abs(ellipse.height - 100) < 1e-6)
  }

  @Test func linePathEndpoints() {
    let path = ShapePaths.line(from: CGPoint(x: 1, y: 2), to: CGPoint(x: 11, y: 22))
    #expect(path.boundingBoxOfPath == CGRect(x: 1, y: 2, width: 10, height: 20))
  }

  // MARK: hit testing

  @Test func strokeHitInsideAndOutsideTolerance() {
    let line = ShapePaths.line(from: .zero, to: CGPoint(x: 100, y: 0))
    // Half stroke 2 + tolerance 3 = 5.
    #expect(HitTest.stroke(path: line, strokeWidth: 4, point: CGPoint(x: 50, y: 4.5), tolerance: 3))
    #expect(!HitTest.stroke(path: line, strokeWidth: 4, point: CGPoint(x: 50, y: 6), tolerance: 3))
    #expect(!HitTest.stroke(path: line, strokeWidth: 4, point: CGPoint(x: 150, y: 0), tolerance: 3))
  }

  @Test func rectStrokeVersusFilledInterior() {
    let path = ShapePaths.rect(CGRect(x: 0, y: 0, width: 100, height: 100))
    let center = CGPoint(x: 50, y: 50)
    #expect(!HitTest.stroke(path: path, strokeWidth: 4, point: center, tolerance: 2))
    #expect(HitTest.filled(path: path, strokeWidth: 4, point: center, tolerance: 2))
    #expect(HitTest.stroke(path: path, strokeWidth: 4, point: CGPoint(x: 1, y: 50), tolerance: 2))
    #expect(!HitTest.filled(path: path, strokeWidth: 4, point: CGPoint(x: 120, y: 50), tolerance: 2))
  }

  @Test func filledHitOnArrowUsesTolerance() {
    let arrow = ArrowPath.make(from: .zero, to: CGPoint(x: 200, y: 0), width: 10)
    #expect(HitTest.filled(path: arrow, point: CGPoint(x: 100, y: 0), tolerance: 0))
    #expect(!HitTest.filled(path: arrow, point: CGPoint(x: 100, y: 6), tolerance: 0))
    #expect(HitTest.filled(path: arrow, point: CGPoint(x: 100, y: 6), tolerance: 6))
  }

  @Test func emptyPathNeverHits() {
    let empty = CGMutablePath()
    #expect(!HitTest.stroke(path: empty, strokeWidth: 5, point: .zero, tolerance: 5))
    #expect(!HitTest.filled(path: empty, point: .zero, tolerance: 5))
    #expect(!HitTest.intersects(path: empty, strokeWidth: 5, rect: CGRect(x: -1, y: -1, width: 2, height: 2)))
  }

  @Test func rectIntersection() {
    let path = ShapePaths.rect(CGRect(x: 0, y: 0, width: 100, height: 100))
    // Marquee entirely inside the interior: only a filled test hits.
    let inside = CGRect(x: 40, y: 40, width: 10, height: 10)
    #expect(!HitTest.intersects(path: path, strokeWidth: 2, rect: inside))
    #expect(HitTest.intersects(path: path, strokeWidth: 2, filled: true, rect: inside))
    // Marquee crossing the outline.
    #expect(HitTest.intersects(path: path, strokeWidth: 2, rect: CGRect(x: 90, y: 40, width: 20, height: 10)))
    // Marquee far away.
    let far = CGRect(x: 200, y: 200, width: 10, height: 10)
    #expect(!HitTest.intersects(path: path, strokeWidth: 2, filled: true, rect: far))
  }

  // MARK: helpers

  @Test func distanceToSegment() {
    let a = CGPoint(x: 0, y: 0)
    let b = CGPoint(x: 10, y: 0)
    #expect(GeometryMath.distance(from: CGPoint(x: 5, y: 3), toSegment: a, b) == 3)
    #expect(GeometryMath.distance(from: CGPoint(x: 13, y: 4), toSegment: a, b) == 5)
    #expect(GeometryMath.distance(from: CGPoint(x: -3, y: 4), toSegment: a, b) == 5)
    // Degenerate segment measures to the point.
    #expect(GeometryMath.distance(from: CGPoint(x: 3, y: 4), toSegment: a, a) == 5)
  }

  @Test func rotateAboutPoint() {
    let p = GeometryMath.rotate(CGPoint(x: 2, y: 1), about: CGPoint(x: 1, y: 1), by: .pi / 2)
    #expect(abs(p.x - 1) < 1e-9)
    #expect(abs(p.y - 2) < 1e-9)
    let same = GeometryMath.rotate(CGPoint(x: 5, y: 5), about: CGPoint(x: 5, y: 5), by: 1.234)
    #expect(same == CGPoint(x: 5, y: 5))
  }

  @Test func snapToFifteenDegrees() {
    let origin = CGPoint(x: 10, y: 10)
    // About 7 degrees snaps to 0 degrees, keeping the distance.
    let length = 100.0
    let angle = 7.0 * .pi / 180
    let target = CGPoint(x: origin.x + length * cos(angle), y: origin.y + length * sin(angle))
    let snapped = GeometryMath.snapped(target, from: origin)
    #expect(abs(snapped.x - (origin.x + length)) < 1e-9)
    #expect(abs(snapped.y - origin.y) < 1e-9)
    // About 40 degrees snaps to 45 degrees.
    let a45 = 40.0 * .pi / 180
    let t45 = CGPoint(x: origin.x + length * cos(a45), y: origin.y + length * sin(a45))
    let s45 = GeometryMath.snapped(t45, from: origin)
    #expect(abs(s45.x - origin.x - length * cos(.pi / 4)) < 1e-9)
    #expect(abs(s45.distance(to: origin) - length) < 1e-9)
    // Zero length is unchanged.
    #expect(GeometryMath.snapped(origin, from: origin) == origin)
    #expect(abs(GeometryMath.snapAngle(0.3) - .pi / 12) < 1e-9)
  }
}
