import CoreGraphics
import Foundation
import Testing

@testable import SkitchoCore

/// An opaque image whose pixel (x, y) is (x * 10, y * 10, 7) counted from the top-left.
private func gradientImage(width: Int, height: Int) -> CGImage {
  let context = makeContext(width: width, height: height)
  let data = context.data!.assumingMemoryBound(to: UInt8.self)
  for y in 0..<height {
    for x in 0..<width {
      let i = y * context.bytesPerRow + x * 4
      data[i] = UInt8(x * 10)
      data[i + 1] = UInt8(y * 10)
      data[i + 2] = 7
      data[i + 3] = 255
    }
  }
  return context.makeImage()!
}

private func gradientDocument(width: Int = 4, height: Int = 4, elements: [Element] = []) -> Document {
  Document(baseImage: gradientImage(width: width, height: height), elements: elements)
}

private func arrowElement(_ start: CGPoint, _ end: CGPoint, stroke: Double = 4) -> Element {
  Element(kind: .arrow(start: start, end: end, doubleHeaded: false), style: testStyle(.red, stroke: stroke))
}

private func expectPoint(_ actual: CGPoint, _ x: Double, _ y: Double, sourceLocation: SourceLocation = #_sourceLocation)
{
  #expect(
    abs(actual.x - x) < 1e-6 && abs(actual.y - y) < 1e-6, "\(actual) vs (\(x), \(y))", sourceLocation: sourceLocation)
}

private func arrowPoints(_ element: Element) -> (CGPoint, CGPoint) {
  guard case .arrow(let start, let end, _) = element.kind else { fatalError("not an arrow") }
  return (start, end)
}

private func samePixels(_ a: CGImage, _ b: CGImage) -> Bool {
  guard a.width == b.width, a.height == b.height else { return false }
  let left = PixelReader(a)
  let right = PixelReader(b)
  for y in 0..<a.height {
    for x in 0..<a.width where left.pixel(x, y) != right.pixel(x, y) { return false }
  }
  return true
}

@Suite struct ImageOpsTests {
  // MARK: pixelate

  @Test func pixelateAveragesTwoPixelBlocksExactly() throws {
    let result = try ImageOps.pixelate(gradientDocument(), rect: CGRect(x: 0, y: 0, width: 4, height: 4), blockSize: 2)
    let pixels = PixelReader(result.baseImage)
    // Block (0,0) covers x 0..1, y 0..1: red avg of 0,10 = 5, green avg of 0,10 = 5.
    for (x, y) in [(0, 0), (1, 0), (0, 1), (1, 1)] {
      let p = pixels.pixel(x, y)
      #expect(p.r == 5 && p.g == 5 && p.b == 7 && p.a == 255)
    }
    // Block (1,1) covers x 2..3, y 2..3: red avg of 20,30 = 25, green 25.
    let p = pixels.pixel(3, 3)
    #expect(p.r == 25 && p.g == 25)
    // Block (1,0): red avg 25, green avg 5.
    let q = pixels.pixel(2, 1)
    #expect(q.r == 25 && q.g == 5)
  }

  @Test func pixelateOnlyChangesTheRegionAndClips() throws {
    let result = try ImageOps.pixelate(
      gradientDocument(), rect: CGRect(x: 2, y: 2, width: 100, height: 100), blockSize: 2)
    let pixels = PixelReader(result.baseImage)
    #expect(pixels.pixel(0, 0).r == 0 && pixels.pixel(1, 3).g == 30)
    #expect(pixels.pixel(2, 2).r == 25 && pixels.pixel(3, 3).g == 25)
    #expect(result.elements.isEmpty && result.canvasSize == CGSize(width: 4, height: 4))
  }

  @Test func pixelateEdgeBlocksAverageTheirOwnPixels() throws {
    // 3 wide with block 2: the last column is a block of its own.
    let result = try ImageOps.pixelate(
      gradientDocument(width: 3, height: 1), rect: CGRect(x: 0, y: 0, width: 3, height: 1), blockSize: 2)
    let pixels = PixelReader(result.baseImage)
    #expect(pixels.pixel(0, 0).r == 5 && pixels.pixel(1, 0).r == 5)
    #expect(pixels.pixel(2, 0).r == 20)
  }

  @Test func pixelateBlockSizeOneIsIdentityOnPixels() throws {
    let document = gradientDocument()
    let result = try ImageOps.pixelate(document, rect: CGRect(x: 0, y: 0, width: 4, height: 4), blockSize: 1)
    #expect(samePixels(result.baseImage, document.baseImage))
  }

  @Test func pixelateRespectsImageOrigin() throws {
    var document = gradientDocument()
    document.canvasSize = CGSize(width: 8, height: 4)
    document.imageOrigin = CGPoint(x: 4, y: 0)
    // Document x 4..5 maps to image x 0..1.
    let result = try ImageOps.pixelate(document, rect: CGRect(x: 4, y: 0, width: 2, height: 2), blockSize: 2)
    let pixels = PixelReader(result.baseImage)
    #expect(pixels.pixel(0, 0).r == 5 && pixels.pixel(2, 0).r == 20)
  }

  // MARK: crop

  @Test func cropTranslatesElementsAndShrinksCanvas() throws {
    let arrow = arrowElement(CGPoint(x: 5, y: 6), CGPoint(x: 9, y: 6))
    let document = gradientDocument(width: 12, height: 10, elements: [arrow])
    let result = try ImageOps.crop(document, rect: CGRect(x: 3, y: 2, width: 8, height: 6))
    #expect(result.canvasSize == CGSize(width: 8, height: 6))
    #expect(result.baseImage.width == 8 && result.baseImage.height == 6)
    let (start, end) = arrowPoints(result.elements[0])
    expectPoint(start, 2, 4)
    expectPoint(end, 6, 4)
    // Cropped pixel (0,0) is the source pixel (3,2).
    let p = PixelReader(result.baseImage).pixel(0, 0)
    #expect(p.r == 30 && p.g == 20)
  }

  @Test func cropLeavesStrokeWidthAndFontSizeUnchanged() throws {
    let arrow = arrowElement(CGPoint(x: 5, y: 6), CGPoint(x: 9, y: 6), stroke: 7)
    let document = gradientDocument(width: 12, height: 10, elements: [arrow])
    let result = try ImageOps.crop(document, rect: CGRect(x: 1, y: 1, width: 6, height: 6))
    #expect(result.elements[0].style == arrow.style)
    #expect(result.elements[0].style.strokeWidth == 7 && result.elements[0].style.fontSize == 24)
  }

  @Test func cropClipsAndRoundsOutward() throws {
    let result = try ImageOps.crop(gradientDocument(), rect: CGRect(x: 1.4, y: 1.4, width: 100, height: 1.2))
    // x: 1..4 (3 wide), y: floor 1.4 = 1 .. ceil 2.6 = 3 (2 high).
    #expect(result.baseImage.width == 3 && result.baseImage.height == 2)
  }

  @Test func cropBakesBackgroundWhenImageIsOffset() throws {
    var document = gradientDocument()
    document.canvasSize = CGSize(width: 8, height: 4)
    document.imageOrigin = CGPoint(x: 4, y: 0)
    document.background = .navy
    let result = try ImageOps.crop(document, rect: CGRect(x: 2, y: 0, width: 4, height: 4))
    let pixels = PixelReader(result.baseImage)
    expectColor(pixels.pixel(0, 0), .navy)
    #expect(pixels.pixel(2, 0).r == 0 && pixels.pixel(3, 1).g == 10)
  }

  // MARK: resize

  @Test func resizeHalfHalvesGeometryAndStrokeWidth() throws {
    let arrow = arrowElement(CGPoint(x: 20, y: 40), CGPoint(x: 60, y: 40), stroke: 8)
    let text = Element(
      kind: .text(TextContent(string: "hi", origin: CGPoint(x: 10, y: 10), wrapWidth: 50)), style: arrow.style)
    let result = try ImageOps.resize(gradientDocument(width: 10, height: 8, elements: [arrow, text]), scale: 0.5)
    #expect(result.canvasSize == CGSize(width: 5, height: 4))
    #expect(result.baseImage.width == 5 && result.baseImage.height == 4)
    let (start, end) = arrowPoints(result.elements[0])
    expectPoint(start, 10, 20)
    expectPoint(end, 30, 20)
    #expect(result.elements[0].style.strokeWidth == 4)
    #expect(result.elements[0].style.fontSize == 12)
    guard case .text(let content) = result.elements[1].kind else { fatalError() }
    expectPoint(content.origin, 5, 5)
    #expect(content.wrapWidth == 25)
  }

  @Test func resizeDoubleKeepsColorsOfSolidImage() throws {
    let document = Document(baseImage: makeBitmap(width: 4, height: 4, fill: .blue))
    let result = try ImageOps.resize(document, scale: 2)
    #expect(result.baseImage.width == 8 && result.baseImage.height == 8)
    expectColor(PixelReader(result.baseImage).pixel(4, 4), .blue)
  }

  @Test func resizeNeverCollapsesBelowOnePixel() throws {
    let result = try ImageOps.resize(gradientDocument(), scale: 0.01)
    #expect(result.baseImage.width == 1 && result.baseImage.height == 1)
  }

  // MARK: expand

  @Test func expandLeftAndTopShiftContentRightAndBottomDoNot() throws {
    let arrow = arrowElement(CGPoint(x: 1, y: 1), CGPoint(x: 3, y: 1))
    let document = gradientDocument(elements: [arrow])

    let left = try ImageOps.expandCanvas(document, edge: .left, amount: 64)
    #expect(left.canvasSize == CGSize(width: 68, height: 4))
    expectPoint(left.imageOrigin, 64, 0)
    expectPoint(arrowPoints(left.elements[0]).0, 65, 1)

    let top = try ImageOps.expandCanvas(document, edge: .top, amount: 10)
    #expect(top.canvasSize == CGSize(width: 4, height: 14))
    expectPoint(top.imageOrigin, 0, 10)
    expectPoint(arrowPoints(top.elements[0]).0, 1, 11)

    let right = try ImageOps.expandCanvas(document, edge: .right, amount: 6)
    #expect(right.canvasSize == CGSize(width: 10, height: 4))
    #expect(right.imageOrigin == .zero)
    expectPoint(arrowPoints(right.elements[0]).0, 1, 1)

    let bottom = try ImageOps.expandCanvas(document, edge: .bottom, amount: 6)
    #expect(bottom.canvasSize == CGSize(width: 4, height: 10))
    #expect(bottom.imageOrigin == .zero)
  }

  @Test func expandThenFlattenShowsBackgroundOnTheNewEdge() throws {
    var document = Document(baseImage: makeBitmap(width: 4, height: 4, fill: .blue), background: .navy)
    document = try ImageOps.expandCanvas(document, edge: .left, amount: 4)
    let flat = try DocumentRenderer.flatten(document, scale: 1)
    let pixels = PixelReader(flat)
    expectColor(pixels.pixel(1, 1), .navy)
    expectColor(pixels.pixel(6, 1), .blue)
  }

  // MARK: rotate / flip

  @Test func rotateClockwiseMovesPixelsAndPoints() throws {
    let arrow = arrowElement(CGPoint(x: 1, y: 0), CGPoint(x: 3, y: 0))
    let document = gradientDocument(width: 4, height: 2, elements: [arrow])
    let result = try ImageOps.rotate90(document, clockwise: true)
    #expect(result.canvasSize == CGSize(width: 2, height: 4))
    // Source top-left (0,0) goes to the top-right corner (1,0).
    let pixels = PixelReader(result.baseImage)
    #expect(pixels.pixel(1, 0).r == 0 && pixels.pixel(1, 0).g == 0)
    // Source (3,0) goes to (1,3).
    #expect(pixels.pixel(1, 3).r == 30 && pixels.pixel(1, 3).g == 0)
    let (start, end) = arrowPoints(result.elements[0])
    expectPoint(start, 2, 1)
    expectPoint(end, 2, 3)
  }

  @Test func rotateCounterClockwiseMovesPixelsAndPoints() throws {
    let arrow = arrowElement(CGPoint(x: 1, y: 0), CGPoint(x: 3, y: 0))
    let document = gradientDocument(width: 4, height: 2, elements: [arrow])
    let result = try ImageOps.rotate90(document, clockwise: false)
    let pixels = PixelReader(result.baseImage)
    // Source top-left (0,0) goes to the bottom-left corner (0,3).
    #expect(pixels.pixel(0, 3).r == 0 && pixels.pixel(0, 3).g == 0)
    #expect(pixels.pixel(0, 0).r == 30)
    let (start, end) = arrowPoints(result.elements[0])
    expectPoint(start, 0, 3)
    expectPoint(end, 0, 1)
  }

  @Test func rotateFourTimesIsIdentity() throws {
    let rect = Element(
      kind: .rect(CGRect(x: 2, y: 1, width: 6, height: 3), rounded: false), style: testStyle(.red), rotation: 0.3)
    let arrow = arrowElement(CGPoint(x: 1, y: 1), CGPoint(x: 9, y: 4))
    let stamp = Element(
      kind: .stamp(.approve, center: CGPoint(x: 6, y: 5), tailAngle: 0.7, labelID: nil), style: testStyle(.green))
    let document = gradientDocument(width: 12, height: 8, elements: [rect, arrow, stamp])
    for clockwise in [true, false] {
      var result = document
      for _ in 0..<4 { result = try ImageOps.rotate90(result, clockwise: clockwise) }
      #expect(samePixels(result.baseImage, document.baseImage))
      #expect(result.canvasSize == document.canvasSize)
      assertSameGeometry(result.elements, document.elements)
    }
  }

  @Test func rotateKeepsBoxSizeAndAddsQuarterTurn() throws {
    let rect = Element(kind: .rect(CGRect(x: 2, y: 1, width: 6, height: 3), rounded: false), style: testStyle(.red))
    let result = try ImageOps.rotate90(gradientDocument(width: 12, height: 8, elements: [rect]), clockwise: true)
    let element = result.elements[0]
    #expect(abs(element.rotation - .pi / 2) < 1e-9)
    // Old center (5, 2.5) maps to (8 - 2.5, 5) = (5.5, 5).
    expectPoint(element.baseBounds.center, 5.5, 5)
    #expect(element.baseBounds.width == 6 && element.baseBounds.height == 3)
    // The rotated box covers the mapped corners: x 4...7, y 2...8.
    let box = element.bounds
    #expect(abs(box.minX - 4) < 1e-6 && abs(box.maxX - 7) < 1e-6)
    #expect(abs(box.minY - 2) < 1e-6 && abs(box.maxY - 8) < 1e-6)
  }

  @Test func flipTwiceIsIdentityAndOnceMirrors() throws {
    let arrow = arrowElement(CGPoint(x: 1, y: 1), CGPoint(x: 3, y: 1))
    let stamp = Element(
      kind: .stamp(.reject, center: CGPoint(x: 2, y: 2), tailAngle: 0.5, labelID: nil),
      style: testStyle(.red, stroke: 0.3), rotation: 0.2)
    let document = gradientDocument(width: 4, height: 4, elements: [arrow, stamp])
    for axis in [FlipAxis.horizontal, .vertical] {
      let once = try ImageOps.flip(document, axis: axis)
      #expect(!samePixels(once.baseImage, document.baseImage))
      let twice = try ImageOps.flip(once, axis: axis)
      #expect(samePixels(twice.baseImage, document.baseImage))
      assertSameGeometry(twice.elements, document.elements)
    }
    let horizontal = try ImageOps.flip(document, axis: .horizontal)
    #expect(PixelReader(horizontal.baseImage).pixel(3, 0).r == 0)
    expectPoint(arrowPoints(horizontal.elements[0]).0, 3, 1)
    let vertical = try ImageOps.flip(document, axis: .vertical)
    #expect(PixelReader(vertical.baseImage).pixel(0, 3).g == 0)
    expectPoint(arrowPoints(vertical.elements[0]).0, 1, 3)
  }

  @Test func singleFlipMirrorsRotationTailAndCenterOfEveryBoxKind() throws {
    let elements = [
      Element(
        kind: .rect(CGRect(x: 2, y: 1, width: 6, height: 3), rounded: true), style: testStyle(.red), rotation: 0.3),
      Element(kind: .ellipse(CGRect(x: 10, y: 2, width: 4, height: 6)), style: testStyle(.red), rotation: -0.4),
      Element(
        kind: .text(TextContent(string: "Hi", origin: CGPoint(x: 3, y: 5))), style: testStyle(.red), rotation: 0.5),
      Element(
        kind: .stamp(.question, center: CGPoint(x: 14, y: 6), tailAngle: 0.7, labelID: nil),
        style: testStyle(.red, stroke: 0.3), rotation: 0.2),
    ]
    let (width, height) = (20.0, 10.0)
    let document = gradientDocument(width: 20, height: 10, elements: elements)
    for axis in [FlipAxis.horizontal, .vertical] {
      let flipped = try ImageOps.flip(document, axis: axis).elements
      for (old, new) in zip(elements, flipped) {
        #expect(abs(new.rotation + old.rotation) < 1e-9, "\(axis) rotation \(new.rotation) vs \(-old.rotation)")
        let c = old.baseBounds.center
        let mapped = axis == .horizontal ? CGPoint(x: width - c.x, y: c.y) : CGPoint(x: c.x, y: height - c.y)
        expectPoint(new.baseBounds.center, mapped.x, mapped.y)
        // Boxes are moved, never mirrored or resized.
        #expect(abs(new.baseBounds.width - old.baseBounds.width) < 1e-9)
        #expect(abs(new.baseBounds.height - old.baseBounds.height) < 1e-9)
      }
      guard case .stamp(_, _, let tail?, _) = flipped[3].kind else {
        Issue.record("stamp lost its tail")
        continue
      }
      let expectedTail = axis == .horizontal ? Double.pi - 0.7 : -0.7
      #expect(abs(tail - expectedTail) < 1e-9, "\(axis) tail \(tail) vs \(expectedTail)")
      guard case .text(let content) = flipped[2].kind else { fatalError("expected text") }
      #expect(content.string == "Hi")
    }
  }

  @Test func rotateAndFlipLeaveStylesUnchanged() throws {
    let arrow = arrowElement(CGPoint(x: 1, y: 1), CGPoint(x: 3, y: 1), stroke: 9)
    let document = gradientDocument(elements: [arrow])
    #expect(try ImageOps.rotate90(document, clockwise: true).elements[0].style == arrow.style)
    #expect(try ImageOps.flip(document, axis: .horizontal).elements[0].style == arrow.style)
    #expect(try ImageOps.expandCanvas(document, edge: .top, amount: 3).elements[0].style == arrow.style)
  }

  // MARK: errors

  @Test func tooLargeIsRejected() throws {
    let document = gradientDocument()
    #expect(throws: ImageOpError.tooLarge) { try ImageOps.resize(document, scale: 5000) }
    #expect(throws: ImageOpError.tooLarge) {
      try ImageOps.expandCanvas(document, edge: .right, amount: ImageOps.maxSide)
    }
    // Exactly at the limit is fine.
    let ok = try ImageOps.expandCanvas(document, edge: .right, amount: ImageOps.maxSide - 4)
    #expect(Int(ok.canvasSize.width) == ImageOps.maxSide)
  }

  @Test func invalidRectsAreRejected() throws {
    let document = gradientDocument()
    let bad = [
      CGRect.zero, CGRect(x: 1, y: 1, width: 0, height: 3), CGRect(x: 10, y: 10, width: 2, height: 2),
      CGRect(x: -5, y: -5, width: 2, height: 2), CGRect(x: Double.nan, y: 0, width: 2, height: 2),
      CGRect(x: 0, y: 0, width: Double.infinity, height: 2),
    ]
    for rect in bad {
      #expect(throws: ImageOpError.invalidRect) { try ImageOps.crop(document, rect: rect) }
      #expect(throws: ImageOpError.invalidRect) { try ImageOps.pixelate(document, rect: rect, blockSize: 2) }
    }
  }

  @Test func invalidArgumentsAreRejected() throws {
    let document = gradientDocument()
    let full = CGRect(x: 0, y: 0, width: 4, height: 4)
    #expect(throws: ImageOpError.invalidArgument) { try ImageOps.pixelate(document, rect: full, blockSize: 0) }
    #expect(throws: ImageOpError.invalidArgument) { try ImageOps.resize(document, scale: 0) }
    #expect(throws: ImageOpError.invalidArgument) { try ImageOps.resize(document, scale: -1) }
    #expect(throws: ImageOpError.invalidArgument) { try ImageOps.resize(document, scale: Double.nan) }
    #expect(throws: ImageOpError.invalidArgument) { try ImageOps.expandCanvas(document, edge: .top, amount: 0) }
  }

  // MARK: helpers

  private func assertSameGeometry(
    _ actual: [Element], _ expected: [Element], sourceLocation: SourceLocation = #_sourceLocation
  ) {
    #expect(actual.count == expected.count, sourceLocation: sourceLocation)
    for (a, e) in zip(actual, expected) {
      #expect(a.id == e.id && a.style == e.style, sourceLocation: sourceLocation)
      #expect(
        abs(a.rotation - e.rotation) < 1e-9, "rotation \(a.rotation) vs \(e.rotation)", sourceLocation: sourceLocation)
      let (ab, eb) = (a.bounds, e.bounds)
      #expect(
        abs(ab.minX - eb.minX) < 1e-6 && abs(ab.minY - eb.minY) < 1e-6 && abs(ab.maxX - eb.maxX) < 1e-6
          && abs(ab.maxY - eb.maxY) < 1e-6, "bounds \(ab) vs \(eb)", sourceLocation: sourceLocation)
    }
  }
}
