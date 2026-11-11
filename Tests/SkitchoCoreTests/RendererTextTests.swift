import CoreGraphics
import CoreText
import Foundation
import Testing

@testable import SkitchoCore

@Suite struct RendererTextTests {
  private func textStyle(_ color: AnnotationColor, fontSize: Double = 40) -> Style {
    Style(color: color, sizeStep: .default, strokeWidth: 10, fontSize: fontSize)
  }

  private func render(
    _ content: TextContent, style: Style, rotation: Double = 0, size: CGSize = CGSize(width: 200, height: 120)
  )
    throws -> PixelReader
  {
    let base = makeBitmap(width: Int(size.width), height: Int(size.height), fill: .white)
    let element = Element(kind: .text(content), style: style, rotation: rotation)
    let doc = Document(baseImage: base, elements: [element])
    return PixelReader(try DocumentRenderer.flatten(doc))
  }

  /// Bounding box (in top-left pixel coordinates) of pixels that differ from white by more than `threshold`.
  private func inkBox(_ pixels: PixelReader, threshold: Int = 100) -> CGRect? {
    var minX = Int.max
    var minY = Int.max
    var maxX = -1
    var maxY = -1
    for y in 0..<pixels.height {
      for x in 0..<pixels.width {
        let p = pixels.pixel(x, y)
        if (255 - p.r) + (255 - p.g) + (255 - p.b) > threshold {
          minX = min(minX, x)
          maxX = max(maxX, x)
          minY = min(minY, y)
          maxY = max(maxY, y)
        }
      }
    }
    guard maxX >= 0 else { return nil }
    return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
  }

  // MARK: Measure

  @Test func measureGrowsWithStringAndLines() {
    func size(_ string: String) -> CGSize {
      TextRenderer.size(for: TextContent(string: string, origin: .zero), fontSize: 24)
    }
    #expect(size("abcdef").width > size("ab").width)
    #expect(size("a\nb").height > size("a").height)
    #expect(size("a").height > 0)
  }

  @Test func measureScalesWithFontSize() {
    let content = TextContent(string: "Hello", origin: .zero)
    let small = TextRenderer.size(for: content, fontSize: 12)
    let large = TextRenderer.size(for: content, fontSize: 48)
    #expect(large.width > small.width * 2)
    #expect(large.height > small.height * 2)
  }

  @Test func measureWrapsAtWrapWidth() {
    let string = "the quick brown fox jumps over the lazy dog"
    let free = TextRenderer.size(for: TextContent(string: string, origin: .zero), fontSize: 20)
    let wrapped = TextRenderer.size(for: TextContent(string: string, origin: .zero, wrapWidth: 100), fontSize: 20)
    #expect(wrapped.width == 100)
    #expect(free.width > 100)
    #expect(wrapped.height > free.height)
  }

  @Test func measureEmptyStringHasOneLineHeight() {
    let size = TextRenderer.size(for: TextContent(string: "", origin: .zero), fontSize: 20)
    #expect(size.width == 0)
    #expect(size.height > 0)
  }

  // MARK: Orientation and drawing

  @Test func glyphsAreNotMirroredAndSitInsideTextBox() throws {
    // "T" has a wide bar at the top and a narrow stem below: upright text has more ink in its top rows.
    let content = TextContent(string: "T", origin: CGPoint(x: 20, y: 30), styled: false)
    let pixels = try render(content, style: textStyle(.black, fontSize: 60))
    let box = try #require(inkBox(pixels))
    let measured = TextRenderer.size(for: content, fontSize: 60)
    #expect(box.minY >= 30 && box.maxY <= 30 + measured.height + 1)
    #expect(box.minX >= 20 && box.maxX <= 20 + measured.width + 1)

    func rowInk(_ y: Int) -> Int {
      (0..<pixels.width).filter { 255 - pixels.pixel($0, y).r > 100 }.count
    }
    let top = rowInk(Int(box.minY) + 3)
    let bottom = rowInk(Int(box.maxY) - 3)
    #expect(top > bottom * 2, "bar should be at the top: top \(top), bottom \(bottom)")
  }

  @Test func inkIsAboveBaselineOfTheTextBox() throws {
    // The ink of "H" must not extend below the text box bottom (the descent area stays empty).
    let content = TextContent(string: "H", origin: CGPoint(x: 10, y: 10), styled: false)
    let pixels = try render(content, style: textStyle(.black, fontSize: 50))
    let box = try #require(inkBox(pixels))
    let measured = TextRenderer.size(for: content, fontSize: 50)
    #expect(box.maxY < 10 + measured.height)
    #expect(box.minY >= 10)
  }

  @Test func plainTextUsesFillColorOnly() throws {
    let content = TextContent(string: "I", origin: CGPoint(x: 20, y: 20), styled: false)
    let pixels = try render(content, style: textStyle(.red, fontSize: 80))
    let box = try #require(inkBox(pixels, threshold: 60))
    // Sample the center of the stem: solid fill color.
    expectColor(pixels.pixel(Int(box.midX), Int(box.midY)), .red)
    // No dark outline anywhere: every inked pixel is reddish (red channel dominant).
    var darkPixels = 0
    for y in 0..<pixels.height {
      for x in 0..<pixels.width {
        let p = pixels.pixel(x, y)
        if p.r < 100 && p.g < 100 && p.b < 100 { darkPixels += 1 }
      }
    }
    #expect(darkPixels == 0)
  }

  @Test func styledTextDrawsContrastingOutlineAtGlyphEdge() throws {
    // White text gets a black outline; the fill stays white in the middle of the stem.
    let content = TextContent(string: "I", origin: CGPoint(x: 20, y: 20), styled: true)
    let base = makeBitmap(width: 200, height: 140, fill: .blue)
    let element = Element(kind: .text(content), style: textStyle(.white, fontSize: 90))
    let pixels = PixelReader(try DocumentRenderer.flatten(Document(baseImage: base, elements: [element])))

    var white: [Int] = []
    var dark = 0
    for y in 0..<pixels.height {
      for x in 0..<pixels.width {
        let p = pixels.pixel(x, y)
        if p.r > 240 && p.g > 240 && p.b > 240 { white.append(x) }
        if p.r < 40 && p.g < 40 && p.b < 40 { dark += 1 }
      }
    }
    #expect(!white.isEmpty, "fill is drawn")
    #expect(dark > 20, "outline is drawn in the contrasting color")
    // The outline sits left of the fill at the glyph edge.
    let fillLeft = try #require(white.min())
    let row = (0..<pixels.height).first { y in
      let p = pixels.pixel(fillLeft, y)
      return p.r > 240 && p.g > 240 && p.b > 240
    }
    let y = try #require(row) + 10
    let outline = pixels.pixel(fillLeft - 2, y)
    #expect(outline.r < 60 && outline.g < 60 && outline.b < 60, "outline pixel \(outline)")
  }

  @Test func wrapWidthBreaksLinesInsideTheBox() throws {
    let content = TextContent(
      string: "aaa bbb ccc ddd eee fff", origin: CGPoint(x: 10, y: 10), wrapWidth: 80, styled: false)
    let pixels = try render(content, style: textStyle(.black, fontSize: 24), size: CGSize(width: 200, height: 200))
    let box = try #require(inkBox(pixels))
    #expect(box.maxX <= 10 + 80 + 1)
    #expect(box.height > TextRenderer.size(for: TextContent(string: "a", origin: .zero), fontSize: 24).height)
  }

  @Test func rotationMovesInkOutOfTheUnrotatedBox() throws {
    let content = TextContent(string: "WWWWWW", origin: CGPoint(x: 20, y: 60), styled: false)
    let style = textStyle(.black, fontSize: 30)
    let flat = try #require(inkBox(try render(content, style: style)))
    let turned = try #require(inkBox(try render(content, style: style, rotation: .pi / 2)))
    #expect(turned.height > flat.height * 2)
    #expect(turned.width < flat.width)
  }

  @Test func emptyTextDrawsNothing() throws {
    let content = TextContent(string: "", origin: CGPoint(x: 10, y: 10))
    let pixels = try render(content, style: textStyle(.black))
    #expect(inkBox(pixels, threshold: 3) == nil)
  }

  @Test func systemFontIsUsed() {
    let name = CTFontCopyFamilyName(TextRenderer.font(size: 20)) as String
    #expect(name.hasPrefix(".") || name.contains("SF") || name.contains("San Francisco"))
  }
}
