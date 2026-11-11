import CoreGraphics
import Foundation
import Testing

@testable import SkitchoCore

@Suite struct RendererStampTests {
  // Stroke 10 gives a badge radius of 40.
  private let center = CGPoint(x: 100, y: 100)

  private func render(
    _ kind: StampKind, tailAngle: Double? = nil, color: AnnotationColor = .red, rotation: Double = 0,
    shadows: Bool = false
  ) -> PixelReader {
    let element = Element(
      kind: .stamp(kind, center: center, tailAngle: tailAngle, labelID: nil), style: testStyle(color),
      rotation: rotation)
    let document = Document(baseImage: makeBitmap(width: 200, height: 200, fill: .white), elements: [element])
    let context = makeContext(width: 200, height: 200)
    DocumentRenderer.draw(document, in: context, shadows: shadows)
    return PixelReader(context.makeImage()!)
  }

  private func isWhite(_ p: (r: Int, g: Int, b: Int, a: Int)) -> Bool { p.r > 250 && p.g > 250 && p.b > 250 }

  @Test func badgeFilledWithStyleColorNearEdge() {
    for kind in StampKind.allCases {
      let pixels = render(kind, color: kind.defaultColor)
      expectColor(pixels.pixel(100 + 34, 100), kind.defaultColor)
      expectColor(pixels.pixel(100, 100 + 34), kind.defaultColor)
      #expect(isWhite(pixels.pixel(100 + 45, 100)), "\(kind) must not paint outside the badge")
    }
  }

  @Test func centerPixelIsGlyphForCrossExclamationStar() {
    for kind in [StampKind.reject, .attention, .perfect] {
      let color = kind.defaultColor
      expectColor(render(kind, color: color).pixel(100, 100), color.contrastingOutline)
    }
  }

  @Test func checkMarkInkIsOnTheCheckNotTheEmptyCorner() {
    let pixels = render(.approve, color: .green)
    // Lower vertex of the check at unit (-0.12, 0.32) times the radius 40.
    expectColor(pixels.pixel(100 - 5, 100 + 13), AnnotationColor.green.contrastingOutline)
    // Upper left corner of the badge interior holds no glyph.
    expectColor(pixels.pixel(100 - 26, 100 - 26), .green)
  }

  @Test func questionMarkHasDotAndHook() {
    let pixels = render(.question, color: .blue)
    let glyph = AnnotationColor.blue.contrastingOutline
    expectColor(pixels.pixel(100, 100 + 22), glyph)  // dot
    expectColor(pixels.pixel(100, 100 - 22), glyph)  // top of the hook
  }

  @Test func tailAddsInkOnlyInTailDirection() {
    let withoutTail = render(.approve, color: .red)
    let withTail = render(.approve, tailAngle: 0, color: .red)  // pointing right on screen
    // Beyond the badge edge (40) toward the tip (64).
    #expect(isWhite(withoutTail.pixel(100 + 50, 100)))
    expectColor(withTail.pixel(100 + 50, 100), .red)
    // Opposite side and perpendicular directions stay untouched.
    #expect(isWhite(withTail.pixel(100 - 50, 100)))
    #expect(isWhite(withTail.pixel(100, 100 - 50)))
    #expect(isWhite(withTail.pixel(100, 100 + 50)))
  }

  @Test func tailPointsDownWhenAngleIsHalfPi() {
    let pixels = render(.reject, tailAngle: .pi / 2, color: .red)
    expectColor(pixels.pixel(100, 100 + 50), .red)
    #expect(isWhite(pixels.pixel(100, 100 - 50)))
  }

  @Test func rotationKeepsTheCenterGlyph() {
    let pixels = render(.perfect, color: .orange, rotation: .pi / 3)
    expectColor(pixels.pixel(100, 100), AnnotationColor.orange.contrastingOutline)
  }

  @Test func everyKindRendersWithAndWithoutTailAndShadow() {
    for kind in StampKind.allCases {
      for tail in [nil, 0.7] as [Double?] {
        for shadows in [false, true] {
          let pixels = render(kind, tailAngle: tail, color: kind.defaultColor, shadows: shadows)
          #expect(!isWhite(pixels.pixel(100 + 34, 100)))
        }
      }
    }
  }

  @Test func shadowFallsBelowTheBadge() {
    // Just below the badge edge (y = 140) the shadow darkens the white background.
    #expect(render(.reject, color: .red, shadows: true).pixel(100, 142).r < 250)
    #expect(isWhite(render(.reject, color: .red).pixel(100, 142)))
  }

  @Test func zeroSizeStampDrawsNothing() throws {
    let element = Element(
      kind: .stamp(.approve, center: center, tailAngle: nil, labelID: nil),
      style: Style(color: .red, sizeStep: .default, strokeWidth: 0, fontSize: 24))
    let document = Document(baseImage: makeBitmap(width: 200, height: 200, fill: .white), elements: [element])
    let image = try DocumentRenderer.flatten(document)
    #expect(isWhite(PixelReader(image).pixel(100, 100)))
  }
}
