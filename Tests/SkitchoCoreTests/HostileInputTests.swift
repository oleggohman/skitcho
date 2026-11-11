import CoreGraphics
import Foundation
import Testing

@testable import SkitchoCore

/// CRC-32 (IEEE) as used by PNG chunks.
private func crc32(_ bytes: [UInt8]) -> UInt32 {
  var crc: UInt32 = 0xFFFF_FFFF
  for byte in bytes {
    crc ^= UInt32(byte)
    for _ in 0..<8 { crc = crc & 1 == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1 }
  }
  return ~crc
}

private func bigEndian(_ value: UInt32) -> [UInt8] {
  [UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)]
}

/// A tiny PNG (the pixel data of a 4x4 image) whose header claims `width` x `height` pixels: the IHDR
/// chunk of a real PNG is rewritten and its CRC fixed, so the file stays small but looks huge.
private func pngHeader(width: UInt32, height: UInt32) throws -> Data {
  var bytes = [UInt8](try Exporter.encode(makeBitmap(width: 4, height: 4, fill: .blue), format: .png))
  // Signature (8) + chunk length (4), then "IHDR" at 12, width at 16, height at 20, CRC at 29.
  #expect(Array(bytes[12..<16]) == Array("IHDR".utf8))
  bytes.replaceSubrange(16..<20, with: bigEndian(width))
  bytes.replaceSubrange(20..<24, with: bigEndian(height))
  bytes.replaceSubrange(29..<33, with: bigEndian(crc32(Array(bytes[12..<29]))))
  return Data(bytes)
}

/// A real, decodable PNG of `width` x 1 pixels.
private func pngStrip(width: Int) throws -> Data {
  try Exporter.encode(makeBitmap(width: width, height: 1, fill: .blue), format: .png)
}

private func packageWrapper(json: Data, png: Data) -> FileWrapper {
  let dir = FileWrapper(directoryWithFileWrappers: [:])
  let jsonFile = FileWrapper(regularFileWithContents: json)
  jsonFile.preferredFilename = PackageCodec.jsonName
  dir.addFileWrapper(jsonFile)
  let pngFile = FileWrapper(regularFileWithContents: png)
  pngFile.preferredFilename = PackageCodec.imageName
  dir.addFileWrapper(pngFile)
  return dir
}

/// The JSON and PNG of a valid 4x4 package, with `edit` applied to the decoded JSON object.
private func editedPackage(_ edit: (inout [String: Any]) -> Void) throws -> FileWrapper {
  let good = try PackageCodec.wrapper(for: Document.blank(size: CGSize(width: 4, height: 4)))
  let json = good.fileWrappers![PackageCodec.jsonName]!.regularFileContents!
  let png = good.fileWrappers![PackageCodec.imageName]!.regularFileContents!
  var object = try #require(try JSONSerialization.jsonObject(with: json) as? [String: Any])
  edit(&object)
  return packageWrapper(json: try JSONSerialization.data(withJSONObject: object), png: png)
}

@Suite struct HostileInputTests {
  // MARK: Package JSON

  @Test func outOfRangeCanvasSizeIsCorrupt() throws {
    let bad: [Double] = [1e300, -5, 0, 0.5, Double(ImageOps.maxSide) + 1]
    for value in bad {
      for key in ["canvasWidth", "canvasHeight"] {
        let wrapper = try editedPackage { $0[key] = value }
        #expect(throws: PackageCodecError.corruptJSON, "\(key) = \(value)") {
          _ = try PackageCodec.document(from: wrapper)
        }
      }
    }
    // The largest allowed canvas still loads.
    let edge = try editedPackage { $0["canvasWidth"] = Double(ImageOps.maxSide) }
    #expect(try PackageCodec.document(from: edge).canvasSize.width == Double(ImageOps.maxSide))
  }

  @Test func nonFiniteImageOriginIsCorrupt() throws {
    // JSON has no NaN or infinity; a literal beyond Double's range is the closest a file can get.
    let good = try PackageCodec.wrapper(for: Document.blank(size: CGSize(width: 4, height: 4)))
    let png = good.fileWrappers![PackageCodec.imageName]!.regularFileContents!
    let original = String(decoding: good.fileWrappers![PackageCodec.jsonName]!.regularFileContents!, as: UTF8.self)
    let hostile = original.replacingOccurrences(of: #""imageOriginX":0"#, with: #""imageOriginX":1e400"#)
    #expect(hostile != original)
    let json = Data(hostile.utf8)
    #expect(throws: PackageCodecError.corruptJSON) {
      _ = try PackageCodec.document(from: packageWrapper(json: json, png: png))
    }
  }

  @Test func versionBelowOneIsCorrupt() throws {
    for version in [0, -1] {
      let wrapper = try editedPackage { $0["version"] = version }
      #expect(throws: PackageCodecError.corruptJSON) { _ = try PackageCodec.document(from: wrapper) }
    }
  }

  @Test func clipboardRejectsVersionBelowOne() throws {
    let element = Element(kind: .line(start: .zero, end: CGPoint(x: 5, y: 5)), style: testStyle(.red))
    let data = try #require(ElementClipboard.encode([element]))
    var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    object["version"] = 0
    #expect(ElementClipboard.decode(try JSONSerialization.data(withJSONObject: object)) == nil)
  }

  @Test func oversizedBaseImageIsCorrupt() throws {
    let good = try PackageCodec.wrapper(for: Document.blank(size: CGSize(width: 4, height: 4)))
    let json = good.fileWrappers![PackageCodec.jsonName]!.regularFileContents!
    let png = try pngHeader(width: 60000, height: 60000)
    #expect(throws: PackageCodecError.corruptImage) {
      _ = try PackageCodec.document(from: packageWrapper(json: json, png: png))
    }
  }

  @Test func nonFiniteGeometryFailsToSaveWithCodecError() {
    var document = Document.blank(size: CGSize(width: 4, height: 4))
    document.elements = [
      Element(kind: .line(start: CGPoint(x: Double.nan, y: 0), end: CGPoint(x: 2, y: 2)), style: testStyle(.red))
    ]
    #expect(throws: PackageCodecError.encodingFailed) { _ = try PackageCodec.wrapper(for: document) }
  }

  // MARK: Image import

  @Test func oversizedHeaderIsRejectedBeforeDecoding() throws {
    // The header says 60000 px wide while the file holds 4x4 pixels: rejected from the header alone.
    let wide = try pngHeader(width: 60000, height: 1)
    #expect(wide.count < 200)
    #expect(throws: ImageImportError.tooLarge) { _ = try ImageImporter.decodeImage(wide) }
    // ImageIO's PNG reader already withholds the size of very large pixel counts; it must still not decode.
    let huge = try pngHeader(width: 60000, height: 60000)
    #expect(throws: ImageImportError.self) { _ = try ImageImporter.decodeImage(huge) }
  }

  @Test func imageOneOverTheLimitIsRejectedAndAtTheLimitLoads() throws {
    let over = try pngStrip(width: ImageOps.maxSide + 1)
    #expect(throws: ImageImportError.tooLarge) { _ = try ImageImporter.load(data: over) }
    let edge = try ImageImporter.load(data: pngStrip(width: ImageOps.maxSide))
    #expect(edge.baseImage.width == ImageOps.maxSide && edge.baseImage.height == 1)
  }

  // MARK: Rendering and blank documents

  @Test func flattenRejectsUnrenderableSizesInsteadOfTrapping() {
    var document = Document.blank(size: CGSize(width: 4, height: 4))
    for size in [
      CGSize(width: 1e300, height: 4), CGSize(width: 4, height: Double.infinity), CGSize(width: Double.nan, height: 4),
      CGSize(width: Double(DocumentRenderer.maxOutputSide) + 1, height: 1),
    ] {
      document.canvasSize = size
      #expect(throws: RenderError.invalidSize, "\(size)") { _ = try DocumentRenderer.flatten(document) }
      #expect(throws: RenderError.invalidSize, "\(size)") { _ = try Exporter.data(document, format: .png) }
    }
    // Scale 2 doubles the output: half the limit plus one is too large at scale 2.
    document.canvasSize = CGSize(width: Double(ImageOps.maxSide) + 1, height: 1)
    #expect(throws: RenderError.invalidSize) { _ = try Exporter.data(document, format: .png, scale: 2) }
    #expect(throws: RenderError.invalidSize) { _ = try DocumentRenderer.flatten(document, scale: .nan) }
  }

  @Test func blankClampsHostileSizes() {
    #expect(Document.blank(size: CGSize(width: Double.nan, height: -3)).canvasSize == CGSize(width: 1, height: 1))
    let huge = Document.blank(size: CGSize(width: 1e300, height: Double.infinity))
    #expect(huge.canvasSize == CGSize(width: ImageOps.maxSide, height: 1))
  }

  // MARK: Image op arguments

  @Test func hugeExpandAmountIsTooLargeNotAnOverflow() {
    let document = Document.blank(size: CGSize(width: 4, height: 4))
    for edge in CanvasEdge.allCases {
      #expect(throws: ImageOpError.tooLarge) { try ImageOps.expandCanvas(document, edge: edge, amount: Int.max) }
    }
  }

  @Test func hugePixelateBlockAveragesTheWholeRegion() throws {
    let document = Document(baseImage: makeBitmap(width: 4, height: 4, fill: .blue, topLeft: .red))
    let rect = CGRect(x: 0, y: 0, width: 4, height: 4)
    let huge = try ImageOps.pixelate(document, rect: rect, blockSize: Int.max)
    let exact = try ImageOps.pixelate(document, rect: rect, blockSize: 4)
    let (a, b) = (PixelReader(huge.baseImage), PixelReader(exact.baseImage))
    for y in 0..<4 {
      for x in 0..<4 { #expect(a.pixel(x, y) == b.pixel(x, y)) }
    }
  }

  // MARK: Non-finite geometry

  @Test func nonFiniteTransformsLeaveElementsUnchanged() {
    let element = Element(
      kind: .rect(CGRect(x: 1, y: 2, width: 3, height: 4), rounded: false), style: testStyle(.red))
    for delta in [CGPoint(x: Double.nan, y: 0), CGPoint(x: 0, y: Double.infinity)] {
      #expect(element.translated(by: delta) == element)
    }
    #expect(element.scaled(by: .nan, about: .zero) == element)
    #expect(element.scaled(by: 2, about: CGPoint(x: Double.infinity, y: 0)) == element)
  }
}
