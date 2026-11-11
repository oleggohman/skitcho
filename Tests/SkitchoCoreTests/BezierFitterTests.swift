import CoreGraphics
import Foundation
import Testing

@testable import SkitchoCore

@Suite struct BezierFitterTests {
  private func sample(_ segments: [BezierSegment], steps: Int = 20) -> [CGPoint] {
    segments.flatMap { s in (0...steps).map { s.point(at: Double($0) / Double(steps)) } }
  }

  private func allFinite(_ segments: [BezierSegment]) -> Bool {
    segments.allSatisfy { s in
      [s.p0, s.p1, s.p2, s.p3].allSatisfy { $0.x.isFinite && $0.y.isFinite }
    }
  }

  // MARK: low-pass filter

  @Test func filterDropsPointsWithinHalfUnitAndSmooths() {
    var filter = LowPassFilter(alpha: 0.5, minDistance: 0.5)
    #expect(filter.add(CGPoint(x: 0, y: 0)) == CGPoint(x: 0, y: 0))
    // Filtered step would be 0.2 < 0.5: dropped.
    #expect(filter.add(CGPoint(x: 0.4, y: 0)) == nil)
    // Moves half the way: 5 units.
    let moved = filter.add(CGPoint(x: 10, y: 0))
    #expect(moved == CGPoint(x: 5, y: 0))
  }

  @Test func filterIgnoresNonFiniteAndResets() {
    var filter = LowPassFilter()
    #expect(filter.add(CGPoint(x: Double.nan, y: 0)) == nil)
    _ = filter.add(CGPoint(x: 1, y: 1))
    filter.reset()
    #expect(filter.add(CGPoint(x: 50, y: 50)) == CGPoint(x: 50, y: 50))
  }

  @Test func filterWholeStrokeKeepsEndpoint() {
    let input = (0...20).map { CGPoint(x: Double($0) * 5, y: 0) }
    let output = LowPassFilter.filter(input, alpha: 0.3)
    #expect(output.first == input.first)
    #expect(output.last == input.last)
    #expect(LowPassFilter.filter([]).isEmpty)
    #expect(LowPassFilter.filter([CGPoint(x: 3, y: 3)]) == [CGPoint(x: 3, y: 3)])
  }

  // MARK: fitting

  @Test func straightLineFitsOneSegment() {
    let points = (0...50).map { CGPoint(x: Double($0) * 4, y: Double($0) * 2) }
    let segments = BezierFitter.fit(points)
    #expect(segments.count == 1)
    #expect(segments[0].p0 == points.first)
    #expect(segments[0].p3 == points.last)
  }

  @Test func circleFitsWithinTolerance() {
    let center = CGPoint(x: 100, y: 100)
    let radius = 50.0
    let points = (0...120).map { i -> CGPoint in
      let a = Double(i) / 120 * 2 * .pi
      return CGPoint(x: center.x + radius * cos(a), y: center.y + radius * sin(a))
    }
    let segments = BezierFitter.fit(points, maxError: 1.0)
    #expect(segments.count >= 2)
    #expect(allFinite(segments))
    for p in sample(segments) {
      #expect(abs(p.distance(to: center) - radius) < 1.5)
    }
  }

  @Test func vCornerIsKeptSharp() {
    let apex = CGPoint(x: 100, y: 100)
    var points: [CGPoint] = []
    for i in 0...30 { points.append(CGPoint(x: 40 + Double(i) * 2, y: 40 + Double(i) * 2)) }
    for i in 1...30 { points.append(CGPoint(x: 100 + Double(i) * 2, y: 100 - Double(i) * 2)) }
    let segments = BezierFitter.fit(points)
    // A segment boundary sits on the apex, so the corner is not rounded off.
    #expect(segments.count >= 2)
    #expect(segments.contains { $0.p3.distance(to: apex) < 1e-6 })
    for p in sample(segments) {
      let nearest = points.map { $0.distance(to: p) }.min() ?? .infinity
      #expect(nearest < 2.5)
    }
  }

  // MARK: edge cases

  @Test func tooFewPointsYieldNoSegments() {
    #expect(BezierFitter.fit([]).isEmpty)
    #expect(BezierFitter.fit([CGPoint(x: 1, y: 1)]).isEmpty)
  }

  @Test func twoPointsYieldOneStraightSegment() {
    let segments = BezierFitter.fit([CGPoint(x: 0, y: 0), CGPoint(x: 30, y: 0)])
    #expect(segments.count == 1)
    #expect(allFinite(segments))
    #expect(segments[0].p3 == CGPoint(x: 30, y: 0))
  }

  @Test func duplicatePointsAreCollapsed() {
    let same = Array(repeating: CGPoint(x: 5, y: 5), count: 10)
    #expect(BezierFitter.fit(same).isEmpty)
    let withDuplicates = [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 0), CGPoint(x: 20, y: 0), CGPoint(x: 20, y: 0)]
    let segments = BezierFitter.fit(withDuplicates)
    #expect(segments.count == 1)
    #expect(allFinite(segments))
  }

  @Test func noNaNForNonFiniteOrCollinearBacktrackingInput() {
    let nan = Double.nan
    let infinity = Double.infinity
    let points = [
      CGPoint(x: 0, y: 0), CGPoint(x: nan, y: 3), CGPoint(x: 10, y: 0), CGPoint(x: 5, y: 0),
      CGPoint(x: 20, y: infinity), CGPoint(x: 0, y: 0), CGPoint(x: 30, y: 1),
    ]
    let segments = BezierFitter.fit(points, maxError: nan)
    #expect(allFinite(segments))
    #expect(allFinite(BezierFitter.fit(points, maxError: 0)))
  }

  @Test func bezierSegmentCodableRoundTrip() throws {
    let s = BezierSegment(CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 2), CGPoint(x: 3, y: 4), CGPoint(x: 5, y: 6))
    let data = try JSONEncoder().encode(s)
    #expect(try JSONDecoder().decode(BezierSegment.self, from: data) == s)
    #expect(s.point(at: 0) == s.p0)
    #expect(s.point(at: 1) == s.p3)
  }
}
