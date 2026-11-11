import CoreGraphics
import Foundation
import Testing

@testable import SkitchoCore

/// Pixel access helper for renderer tests: reads an sRGB RGBA8 premultiplied image with a top-left origin.
struct PixelReader {
  let width: Int
  let height: Int
  private let bytes: [UInt8]

  init(_ image: CGImage) {
    width = image.width
    height = image.height
    var data = [UInt8](repeating: 0, count: width * height * 4)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let width = self.width
    let height = self.height
    data.withUnsafeMutableBytes { buffer in
      let context = CGContext(
        data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    bytes = data
  }

  /// RGBA of the pixel at (x, y) counted from the top-left corner of the image.
  func pixel(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
    // Bitmap memory starts at the top row, so no flip is needed here.
    let i = (y * width + x) * 4
    return (Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2]), Int(bytes[i + 3]))
  }
}

func expectColor(_ actual: (r: Int, g: Int, b: Int, a: Int), _ color: AnnotationColor, tolerance: Int = 2) {
  let rgba = color.rgba
  let expected = [rgba.red, rgba.green, rgba.blue].map { Int(($0 * 255).rounded()) }
  #expect(abs(actual.r - expected[0]) <= tolerance, "red \(actual.r) vs \(expected[0])")
  #expect(abs(actual.g - expected[1]) <= tolerance, "green \(actual.g) vs \(expected[1])")
  #expect(abs(actual.b - expected[2]) <= tolerance, "blue \(actual.b) vs \(expected[2])")
}

/// A solid-color bitmap, optionally with a differently colored top-left quadrant (as seen on screen).
func makeBitmap(width: Int, height: Int, fill: AnnotationColor, topLeft: AnnotationColor? = nil) -> CGImage {
  let space = CGColorSpace(name: CGColorSpace.sRGB)!
  let context = CGContext(
    data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  context.setFillColor(fill.cgColor)
  context.fill(CGRect(x: 0, y: 0, width: width, height: height))
  if let topLeft {
    context.setFillColor(topLeft.cgColor)
    // The context is y-up, so the top-left quadrant is the upper-left of the y range.
    context.fill(CGRect(x: 0, y: height / 2, width: width / 2, height: height - height / 2))
  }
  return context.makeImage()!
}

func testStyle(_ color: AnnotationColor, stroke: Double = 10) -> Style {
  Style(color: color, sizeStep: .default, strokeWidth: stroke, fontSize: 24)
}

func makeContext(width: Int, height: Int) -> CGContext {
  CGContext(
    data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

@Suite struct RendererShapeTests {
  private func document(elements: [Element] = [], fill: AnnotationColor = .white) -> Document {
    Document(baseImage: makeBitmap(width: 100, height: 80, fill: fill), elements: elements)
  }

  private let straight = BezierSegment(
    CGPoint(x: 10, y: 40), CGPoint(x: 40, y: 40), CGPoint(x: 60, y: 40), CGPoint(x: 90, y: 40))

  @Test func orientationTopLeftQuadrantStaysTopLeft() throws {
    let image = makeBitmap(width: 100, height: 80, fill: .blue, topLeft: .red)
    let output = PixelReader(try DocumentRenderer.flatten(Document(baseImage: image)))
    expectColor(output.pixel(10, 10), .red)
    expectColor(output.pixel(90, 10), .blue)
    expectColor(output.pixel(10, 70), .blue)
    expectColor(output.pixel(90, 70), .blue)
  }

  @Test func imageOriginOffsetsBaseOverBackground() throws {
    let base = makeBitmap(width: 40, height: 40, fill: .blue)
    let doc = Document(
      baseImage: base, canvasSize: CGSize(width: 100, height: 80), imageOrigin: CGPoint(x: 50, y: 30),
      background: .white)
    let output = PixelReader(try DocumentRenderer.flatten(doc))
    expectColor(output.pixel(10, 10), .white)
    expectColor(output.pixel(70, 50), .blue)
    expectColor(output.pixel(60, 20), .white)  // above the image
  }

  @Test func rectStrokeColorAndInteriorUntouched() throws {
    let rect = Element(
      kind: .rect(CGRect(x: 20, y: 20, width: 60, height: 40), rounded: false), style: testStyle(.red))
    let output = PixelReader(try DocumentRenderer.flatten(document(elements: [rect])))
    expectColor(output.pixel(50, 20), .red)  // on the top edge
    expectColor(output.pixel(50, 40), .white)  // interior
    expectColor(output.pixel(5, 5), .white)  // outside
  }

  @Test func ellipseAndLineStrokes() throws {
    let ellipse = Element(kind: .ellipse(CGRect(x: 10, y: 10, width: 80, height: 60)), style: testStyle(.blue))
    let line = Element(
      kind: .line(start: CGPoint(x: 0, y: 75), end: CGPoint(x: 100, y: 75)), style: testStyle(.black, stroke: 6))
    let output = PixelReader(try DocumentRenderer.flatten(document(elements: [ellipse, line])))
    expectColor(output.pixel(50, 10), .blue)
    expectColor(output.pixel(50, 40), .white)
    expectColor(output.pixel(50, 75), .black)
  }

  @Test func arrowIsFilledAlongShaft() throws {
    let arrow = Element(
      kind: .arrow(start: CGPoint(x: 10, y: 40), end: CGPoint(x: 90, y: 40), doubleHeaded: false),
      style: testStyle(.red, stroke: 8))
    let output = PixelReader(try DocumentRenderer.flatten(document(elements: [arrow])))
    expectColor(output.pixel(40, 40), .red)
    expectColor(output.pixel(40, 70), .white)
  }

  private func outlinedArrow() -> Element {
    Element(
      kind: .arrow(start: CGPoint(x: 10, y: 40), end: CGPoint(x: 90, y: 40), doubleHeaded: false),
      style: testStyle(.red, stroke: 8))
  }

  @Test func arrowHasWhiteOutlineAroundTheFill() throws {
    // Stroke 8: shaft half-width at x = 40 is about 2.7 and the outline reaches about 4.2.
    let context = makeContext(width: 100, height: 80)
    DocumentRenderer.draw(document(elements: [outlinedArrow()], fill: .black), in: context, shadows: false)
    let output = PixelReader(context.makeImage()!)
    expectColor(output.pixel(40, 39), .red)
    expectColor(output.pixel(40, 40), .red)
    // Just outside the fill edge, on both sides, the outline is white against the black background.
    for y in [36, 43] {
      let pixel = output.pixel(40, y)
      #expect(pixel.r > 240 && pixel.g > 240 && pixel.b > 240, "y \(y): \(pixel)")
    }
    expectColor(output.pixel(40, 30), .black)
    expectColor(output.pixel(40, 50), .black)
  }

  @Test func arrowOutlineHasNoSpikePastTheTip() throws {
    let context = makeContext(width: 100, height: 80)
    DocumentRenderer.draw(document(elements: [outlinedArrow()], fill: .black), in: context, shadows: false)
    let output = PixelReader(context.makeImage()!)
    // The outline half-width is 1.5: right behind the tip it is white, further than that it is untouched.
    let near = output.pixel(90, 40)
    #expect(near.r > 200 && near.g > 200 && near.b > 200, "\(near)")
    expectColor(output.pixel(93, 40), .black)
    expectColor(output.pixel(95, 40), .black)
  }

  @Test func arrowCastsOneShadowWhenEnabled() throws {
    let output = PixelReader(try DocumentRenderer.flatten(document(elements: [outlinedArrow()])))
    // Below the arrow (y-down) the shadow darkens the white background; above it does not.
    #expect(output.pixel(40, 46).r < 245)
    #expect(output.pixel(40, 34).r > output.pixel(40, 46).r)
    let context = makeContext(width: 100, height: 80)
    DocumentRenderer.draw(document(elements: [outlinedArrow()]), in: context, shadows: false)
    #expect(PixelReader(context.makeImage()!).pixel(40, 46).r >= 253)
  }

  @Test func arrowBoundsAndHitTestIncludeTheOutline() {
    let arrow = outlinedArrow()
    let fill = ArrowPath.make(from: CGPoint(x: 10, y: 40), to: CGPoint(x: 90, y: 40), width: 8).boundingBoxOfPath
    let pad = ArrowPath.outlineWidth(width: 8) / 2
    #expect(abs(arrow.baseBounds.maxX - (fill.maxX + pad)) < 1e-9)
    #expect(abs(arrow.baseBounds.minY - (fill.minY - pad)) < 1e-9)
    // Just outside the fill but inside the outline still hits.
    #expect(arrow.hitTest(point: CGPoint(x: 91, y: 40), tolerance: 0))
    #expect(!arrow.hitTest(point: CGPoint(x: 95, y: 40), tolerance: 0))
  }

  @Test func freehandStrokeIsDrawn() throws {
    let stroke = Element(
      kind: .freehand(segments: [straight], highlighter: false), style: testStyle(.navy, stroke: 8))
    let output = PixelReader(try DocumentRenderer.flatten(document(elements: [stroke])))
    expectColor(output.pixel(50, 40), .navy)
    expectColor(output.pixel(50, 60), .white)
  }

  @Test func highlighterDarkensWithoutReplacing() throws {
    let mark = Element(
      kind: .freehand(segments: [straight], highlighter: true), style: testStyle(.yellow, stroke: 20))
    let output = PixelReader(try DocumentRenderer.flatten(document(elements: [mark])))
    let pixel = output.pixel(50, 40)
    // Multiply of yellow at 0.4 over white: blue drops, red stays near white, and the stroke is not opaque yellow.
    #expect(pixel.r >= 250)
    #expect(pixel.b < 250 && pixel.b > 100)
    #expect(pixel.a == 255)
    expectColor(output.pixel(50, 70), .white)
  }

  @Test func highlighterKeepsDarkContentDark() throws {
    let base = makeBitmap(width: 100, height: 80, fill: .black)
    let mark = Element(
      kind: .freehand(segments: [straight], highlighter: true), style: testStyle(.yellow, stroke: 20))
    let output = PixelReader(try DocumentRenderer.flatten(Document(baseImage: base, elements: [mark])))
    let pixel = output.pixel(50, 40)
    #expect(pixel.r < 5 && pixel.g < 5 && pixel.b < 5)  // multiply over black stays black
  }

  @Test func scaleTwoDoublesDimensionsAndGeometry() throws {
    let rect = Element(
      kind: .rect(CGRect(x: 20, y: 20, width: 60, height: 40), rounded: false), style: testStyle(.red))
    let image = try DocumentRenderer.flatten(document(elements: [rect]), scale: 2)
    #expect(image.width == 200 && image.height == 160)
    let output = PixelReader(image)
    expectColor(output.pixel(100, 40), .red)  // top edge at y = 20 * 2
    expectColor(output.pixel(100, 80), .white)
  }

  @Test func excludedElementsAreSkipped() throws {
    let rect = Element(
      kind: .rect(CGRect(x: 20, y: 20, width: 60, height: 40), rounded: false), style: testStyle(.red))
    let context = makeContext(width: 100, height: 80)
    DocumentRenderer.draw(document(elements: [rect]), in: context, excluding: [rect.id], shadows: false)
    expectColor(PixelReader(context.makeImage()!).pixel(50, 20), .white)
  }

  @Test func shadowFallsBelowTheShape() throws {
    let line = Element(
      kind: .line(start: CGPoint(x: 10, y: 30), end: CGPoint(x: 90, y: 30)), style: testStyle(.black, stroke: 4))
    let output = PixelReader(try DocumentRenderer.flatten(document(elements: [line])))
    // Below the line (y-down) the shadow darkens the white more than above it.
    #expect(output.pixel(50, 35).r < 250)
    #expect(output.pixel(50, 25).r > output.pixel(50, 35).r)
  }

  @Test func noShadowWhenDisabled() throws {
    let line = Element(
      kind: .line(start: CGPoint(x: 10, y: 30), end: CGPoint(x: 90, y: 30)), style: testStyle(.black, stroke: 4))
    let context = makeContext(width: 100, height: 80)
    DocumentRenderer.draw(document(elements: [line]), in: context, shadows: false)
    #expect(PixelReader(context.makeImage()!).pixel(50, 35).r >= 253)
  }
}
