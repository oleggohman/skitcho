import CoreGraphics
import Foundation
import Testing

@testable import SkitchoCore

@Suite struct ModelTests {
  static let imageSize = CGSize(width: 1000, height: 1000)

  static func style(_ tool: StyleTool = .rect) -> Style {
    Style.make(tool: tool, imageSize: imageSize)
  }

  static func sampleElements() -> [Element] {
    let s = style()
    let curve = BezierSegment(
      CGPoint(x: 10, y: 10), CGPoint(x: 30, y: 0), CGPoint(x: 50, y: 40), CGPoint(x: 70, y: 10))
    return [
      Element(kind: .arrow(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 200, y: 100), doubleHeaded: true), style: s),
      Element(kind: .line(start: CGPoint(x: 5, y: 5), end: CGPoint(x: 50, y: 60)), style: s),
      Element(kind: .rect(CGRect(x: 10, y: 20, width: 100, height: 50), rounded: true), style: s, rotation: 0.5),
      Element(kind: .ellipse(CGRect(x: 0, y: 0, width: 40, height: 80)), style: s, rotation: 1.0),
      Element(kind: .freehand(segments: [curve], highlighter: true), style: Self.style(.highlighter)),
      Element(
        kind: .text(TextContent(string: "Hello\nworld", origin: CGPoint(x: 3, y: 4), wrapWidth: 120, styled: false)),
        style: s),
      Element(
        kind: .stamp(.perfect, center: CGPoint(x: 50, y: 50), tailAngle: 0.7, labelID: UUID()), style: s),
      Element(kind: .stamp(.approve, center: CGPoint(x: 9, y: 9), tailAngle: nil, labelID: nil), style: s),
    ]
  }

  // MARK: JSON round trip

  @Test func everyKindRoundTripsThroughJSON() throws {
    for element in Self.sampleElements() {
      let data = try JSONEncoder().encode(element)
      let back = try JSONDecoder().decode(Element.self, from: data)
      #expect(back == element)
    }
  }

  @Test func documentRoundTripsThroughPackageWrapper() throws {
    var doc = Document.blank(size: CGSize(width: 64, height: 48), background: .navy)
    doc.canvasSize = CGSize(width: 100, height: 90)
    doc.imageOrigin = CGPoint(x: 12, y: 7)
    doc.elements = Self.sampleElements()
    let back = try PackageCodec.document(from: PackageCodec.wrapper(for: doc))
    #expect(back.elements == doc.elements)
    #expect(back.canvasSize == doc.canvasSize)
    #expect(back.imageOrigin == doc.imageOrigin)
    #expect(back.background == .navy)
    #expect(back.version == Document.currentVersion)
    #expect(back.baseImage.width == 64 && back.baseImage.height == 48)
  }

  @Test func packageRoundTripKeepsEveryPixel() throws {
    // Opaque pixels that all differ, so any codec change to the bitmap shows up (alpha 255 avoids
    // premultiplication rounding).
    let width = 23
    let height = 17
    let context = makeContext(width: width, height: height)
    let data = context.data!.assumingMemoryBound(to: UInt8.self)
    for y in 0..<height {
      for x in 0..<width {
        let i = y * context.bytesPerRow + x * 4
        data[i] = UInt8((x * 11 + y * 3) % 256)
        data[i + 1] = UInt8((y * 15 + x) % 256)
        data[i + 2] = UInt8((x * y * 7) % 256)
        data[i + 3] = 255
      }
    }
    let doc = Document(baseImage: context.makeImage()!)
    let back = try PackageCodec.document(from: PackageCodec.wrapper(for: doc))
    let (expected, actual) = (PixelReader(doc.baseImage), PixelReader(back.baseImage))
    #expect(back.baseImage.width == width && back.baseImage.height == height)
    for y in 0..<height {
      for x in 0..<width where actual.pixel(x, y) != expected.pixel(x, y) {
        Issue.record("pixel (\(x), \(y)): \(actual.pixel(x, y)) vs \(expected.pixel(x, y))")
      }
    }
  }

  @Test func packageRoundTripsThroughTempDirectory() throws {
    var doc = Document.blank(size: CGSize(width: 16, height: 16))
    doc.elements = Self.sampleElements()
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("skitcho-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("test.skitcho")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try PackageCodec.wrapper(for: doc).write(to: url, options: [], originalContentsURL: nil)
    #expect(FileManager.default.fileExists(atPath: url.appendingPathComponent("base.png").path))
    #expect(FileManager.default.fileExists(atPath: url.appendingPathComponent("document.json").path))
    let back = try PackageCodec.document(from: FileWrapper(url: url, options: []))
    #expect(back.elements == doc.elements)
  }

  // MARK: Equality

  @Test func documentEqualityUsesImageIdentity() {
    let a = Document.blank(size: CGSize(width: 8, height: 8))
    var b = a
    #expect(a == b)
    b.elements = [Self.sampleElements()[0]]
    #expect(a != b)
    let other = Document.blank(size: CGSize(width: 8, height: 8))
    #expect(a != other)
  }

  // MARK: Bounds

  @Test func boundsOfBasicShapes() {
    let s = Self.style()
    let rect = Element(kind: .rect(CGRect(x: 10, y: 20, width: 100, height: 50), rounded: false), style: s)
    #expect(rect.bounds == CGRect(x: 10, y: 20, width: 100, height: 50))
    let line = Element(kind: .line(start: CGPoint(x: 50, y: 60), end: CGPoint(x: 5, y: 5)), style: s)
    #expect(line.bounds == CGRect(x: 5, y: 5, width: 45, height: 55))
    let arrow = Element(kind: .arrow(start: .zero, end: CGPoint(x: 200, y: 0), doubleHeaded: false), style: s)
    #expect(arrow.bounds.maxX == 200 && arrow.bounds.minX == 0)
    #expect(arrow.bounds.height > 0)
  }

  @Test func rotatedBoundsSwapExtentsAtQuarterTurn() {
    let rect = Element(
      kind: .rect(CGRect(x: 0, y: 0, width: 100, height: 40), rounded: false), style: Self.style(),
      rotation: .pi / 2)
    let b = rect.bounds
    #expect(abs(b.width - 40) < 1e-9)
    #expect(abs(b.height - 100) < 1e-9)
    #expect(abs(b.midX - 50) < 1e-9 && abs(b.midY - 20) < 1e-9)
  }

  @Test func freehandAndStampBounds() {
    let samples = Self.sampleElements()
    let freehand = samples[4].bounds
    #expect(freehand.minX == 10 && freehand.maxX == 70)
    let radius = StampKind.radius(strokeWidth: samples[6].style.strokeWidth)
    let withTail = samples[6].bounds
    let noTail = samples[7].bounds
    #expect(abs(noTail.width - 2 * radius) < 1e-9)
    #expect(withTail.width > 2 * radius || withTail.height > 2 * radius)
  }

  @Test func textBoundsGrowWithStringAndWrap() {
    let s = Self.style(.text)
    func box(_ string: String, wrap: Double? = nil) -> CGRect {
      Element(kind: .text(TextContent(string: string, origin: .zero, wrapWidth: wrap)), style: s).bounds
    }
    #expect(box("abcdef").width > box("ab").width)
    #expect(box("a\nb").height > box("a").height)
    let wrapped = box(String(repeating: "x", count: 100), wrap: 100)
    #expect(wrapped.width == 100)
    #expect(wrapped.height > box("x").height)
  }

  // MARK: Hit testing

  @Test func lineAndRectHitTests() {
    let s = Self.style()
    let line = Element(kind: .line(start: .zero, end: CGPoint(x: 100, y: 0)), style: s)
    #expect(line.hitTest(point: CGPoint(x: 50, y: 1), tolerance: 2))
    #expect(!line.hitTest(point: CGPoint(x: 50, y: 40), tolerance: 2))
    let rect = Element(kind: .rect(CGRect(x: 0, y: 0, width: 100, height: 100), rounded: false), style: s)
    #expect(rect.hitTest(point: CGPoint(x: 0, y: 50), tolerance: 2))
    #expect(!rect.hitTest(point: CGPoint(x: 50, y: 50), tolerance: 2))
  }

  @Test func rotatedRectHitFollowsRotation() {
    let rect = Element(
      kind: .rect(CGRect(x: 0, y: 0, width: 200, height: 20), rounded: false), style: Self.style(),
      rotation: .pi / 2)
    // Rotated a quarter turn about (100, 10): the rect now spans x in 90...110 and y in -90...110.
    #expect(rect.hitTest(point: CGPoint(x: 100, y: -90), tolerance: 2))
    #expect(!rect.hitTest(point: CGPoint(x: 190, y: 10), tolerance: 2))
  }

  @Test func arrowFreehandTextAndStampHitTests() {
    let samples = Self.sampleElements()
    #expect(samples[0].hitTest(point: CGPoint(x: 100, y: 50), tolerance: 2))
    #expect(!samples[0].hitTest(point: CGPoint(x: 100, y: 200), tolerance: 2))
    #expect(samples[4].hitTest(point: CGPoint(x: 10, y: 10), tolerance: 2))
    #expect(!samples[4].hitTest(point: CGPoint(x: 500, y: 500), tolerance: 2))
    #expect(samples[5].hitTest(point: CGPoint(x: 10, y: 10), tolerance: 0))
    #expect(!samples[5].hitTest(point: CGPoint(x: 400, y: 400), tolerance: 2))
    #expect(samples[7].hitTest(point: CGPoint(x: 9, y: 9), tolerance: 0))
    #expect(!samples[7].hitTest(point: CGPoint(x: 200, y: 200), tolerance: 2))
  }

  // MARK: Transforms

  @Test func translatedMovesEveryKind() {
    let delta = CGPoint(x: 7, y: -3)
    for element in Self.sampleElements() {
      let moved = element.translated(by: delta)
      let before = element.baseBounds
      let after = moved.baseBounds
      #expect(abs(after.minX - before.minX - 7) < 1e-9)
      #expect(abs(after.minY - before.minY + 3) < 1e-9)
      #expect(moved.id == element.id && moved.style == element.style && moved.rotation == element.rotation)
    }
  }

  @Test func scaledScalesGeometryAboutAnchorAndKeepsStyle() {
    let rect = Element(
      kind: .rect(CGRect(x: 100, y: 100, width: 40, height: 20), rounded: false), style: Self.style())
    let scaled = rect.scaled(by: 0.5, about: CGPoint(x: 100, y: 100))
    #expect(scaled.kind == .rect(CGRect(x: 100, y: 100, width: 20, height: 10), rounded: false))
    #expect(scaled.style == rect.style)
    let text = Element(
      kind: .text(TextContent(string: "a", origin: CGPoint(x: 20, y: 20), wrapWidth: 80)), style: Self.style(.text))
    guard case .text(let content) = text.scaled(by: 2, about: .zero).kind else {
      Issue.record("expected text")
      return
    }
    #expect(content.origin == CGPoint(x: 40, y: 40) && content.wrapWidth == 160)
  }

  // MARK: Codec errors

  private func wrapper(json: Data?, png: Data?) -> FileWrapper {
    let dir = FileWrapper(directoryWithFileWrappers: [:])
    if let json {
      let file = FileWrapper(regularFileWithContents: json)
      file.preferredFilename = PackageCodec.jsonName
      dir.addFileWrapper(file)
    }
    if let png {
      let file = FileWrapper(regularFileWithContents: png)
      file.preferredFilename = PackageCodec.imageName
      dir.addFileWrapper(file)
    }
    return dir
  }

  @Test func missingBaseImageThrows() throws {
    let good = try PackageCodec.wrapper(for: Document.blank(size: CGSize(width: 4, height: 4)))
    let json = good.fileWrappers![PackageCodec.jsonName]!.regularFileContents!
    #expect(throws: PackageCodecError.missingFile(PackageCodec.imageName)) {
      _ = try PackageCodec.document(from: wrapper(json: json, png: nil))
    }
  }

  @Test func futureVersionThrows() throws {
    let good = try PackageCodec.wrapper(for: Document.blank(size: CGSize(width: 4, height: 4)))
    let png = good.fileWrappers![PackageCodec.imageName]!.regularFileContents!
    let future = Data(#"{"version": 99, "somethingNew": true}"#.utf8)
    #expect(throws: PackageCodecError.unsupportedVersion(99)) {
      _ = try PackageCodec.document(from: wrapper(json: future, png: png))
    }
  }

  @Test func corruptJSONThrows() throws {
    let good = try PackageCodec.wrapper(for: Document.blank(size: CGSize(width: 4, height: 4)))
    let png = good.fileWrappers![PackageCodec.imageName]!.regularFileContents!
    #expect(throws: PackageCodecError.corruptJSON) {
      _ = try PackageCodec.document(from: wrapper(json: Data("not json".utf8), png: png))
    }
    // Valid header but a payload that does not match the schema is corrupt too.
    #expect(throws: PackageCodecError.corruptJSON) {
      _ = try PackageCodec.document(from: wrapper(json: Data(#"{"version": 1}"#.utf8), png: png))
    }
  }

  @Test func corruptBaseImageThrows() throws {
    let good = try PackageCodec.wrapper(for: Document.blank(size: CGSize(width: 4, height: 4)))
    let json = good.fileWrappers![PackageCodec.jsonName]!.regularFileContents!
    #expect(throws: PackageCodecError.corruptImage) {
      _ = try PackageCodec.document(from: wrapper(json: json, png: Data([0, 1, 2])))
    }
  }

  @Test func stampKindsHaveDistinctDefaultColors() {
    let colors = StampKind.allCases.map(\.defaultColor)
    #expect(Set(colors).count == StampKind.allCases.count)
    #expect(StampKind.radius(strokeWidth: -5) == 0)
  }
}
