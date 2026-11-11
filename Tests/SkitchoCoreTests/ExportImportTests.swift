import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import SkitchoCore

/// Encodes `image` as JPEG with an EXIF orientation tag.
private func jpegData(_ image: CGImage, orientation: Int) -> Data {
  let data = NSMutableData()
  let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
  CGImageDestinationAddImage(
    dest, image,
    [kCGImagePropertyOrientation: orientation, kCGImageDestinationLossyCompressionQuality: 1.0] as CFDictionary)
  #expect(CGImageDestinationFinalize(dest))
  return data as Data
}

private func sourceType(_ data: Data) -> String? {
  CGImageSourceCreateWithData(data as CFData, nil).flatMap { CGImageSourceGetType($0) as String? }
}

/// A busy base image so JPEG size reacts to the quality setting.
private func noisyDocument() -> Document {
  let width = 64
  let height = 64
  let context = makeContext(width: width, height: height)
  for y in 0..<height {
    for x in 0..<width {
      context.setFillColor(
        CGColor(
          srgbRed: Double((x * 37 + y * 11) % 256) / 255, green: Double((x * 5 + y * 71) % 256) / 255,
          blue: Double((x * y) % 256) / 255, alpha: 1))
      context.fill(CGRect(x: x, y: y, width: 1, height: 1))
    }
  }
  return Document(baseImage: context.makeImage()!)
}

struct ExportImportTests {
  @Test func exportsEachFormatAtBothScales() throws {
    let doc = Document.blank(size: CGSize(width: 30, height: 20))
    let formats: [(ExportFormat, UTType)] = [(.png, .png), (.jpeg(quality: 0.8), .jpeg), (.tiff, .tiff)]
    for (format, type) in formats {
      for scale in [1, 2] {
        let data = try Exporter.data(doc, format: format, scale: scale)
        #expect(sourceType(data) == type.identifier)
        let image = try ImageImporter.decodeImage(data)
        #expect(image.width == 30 * scale)
        #expect(image.height == 20 * scale)
      }
    }
  }

  @Test func rejectsUnsupportedScale() {
    #expect(throws: ExportError.invalidScale) {
      _ = try Exporter.data(Document.blank(), format: .png, scale: 3)
    }
  }

  @Test func jpegQualityChangesSize() throws {
    let doc = noisyDocument()
    let low = try Exporter.data(doc, format: .jpeg(quality: 0.1))
    let high = try Exporter.data(doc, format: .jpeg(quality: 1.0))
    #expect(low.count < high.count)
  }

  @Test func exportedPNGKeepsAnnotations() throws {
    var doc = Document.blank(size: CGSize(width: 40, height: 40), background: .white)
    let rect = CGRect(x: 0, y: 0, width: 40, height: 40)
    doc.elements = [Element(kind: .rect(rect, rounded: false), style: testStyle(.red, stroke: 40))]
    let image = try ImageImporter.decodeImage(try Exporter.data(doc, format: .png))
    expectColor(PixelReader(image).pixel(20, 20), .red, tolerance: 3)
  }

  @Test func orientationSixImportsUpright() throws {
    // Stored 40x20 with a red top-left quadrant; orientation 6 rotates it 90 degrees clockwise.
    let stored = makeBitmap(width: 40, height: 20, fill: .blue, topLeft: .red)
    let doc = try ImageImporter.load(data: jpegData(stored, orientation: 6))
    #expect(doc.canvasSize == CGSize(width: 20, height: 40))
    let pixels = PixelReader(doc.baseImage)
    expectColor(pixels.pixel(17, 2), .red, tolerance: 25)
    expectColor(pixels.pixel(2, 2), .blue, tolerance: 25)
    expectColor(pixels.pixel(2, 37), .blue, tolerance: 25)
  }

  @Test func importedImageIsSRGBRGBA8() throws {
    let doc = try ImageImporter.load(data: try Exporter.data(Document.blank(), format: .tiff))
    #expect(doc.baseImage.colorSpace?.name == CGColorSpace.sRGB)
    #expect(doc.baseImage.bitsPerComponent == 8)
  }

  @Test func blankIsWhite800x600() {
    let doc = ImageImporter.blank()
    #expect(doc.canvasSize == CGSize(width: 800, height: 600))
    #expect(doc.background == .white)
    expectColor(PixelReader(doc.baseImage).pixel(10, 10), .white)
  }

  @Test func loadsFromURL() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("skitcho-\(UUID().uuidString).png")
    defer { try? FileManager.default.removeItem(at: url) }
    try Exporter.data(Document.blank(size: CGSize(width: 12, height: 9)), format: .png).write(to: url)
    #expect(try ImageImporter.load(url: url).canvasSize == CGSize(width: 12, height: 9))
  }

  @Test func unreadableDataThrows() {
    #expect(throws: ImageImportError.unreadable) { _ = try ImageImporter.load(data: Data([1, 2, 3])) }
    #expect(throws: ImageImportError.unreadable) { _ = try ImageImporter.load(data: Data()) }
    let missing = URL(fileURLWithPath: "/nonexistent/skitcho-\(UUID().uuidString).png")
    #expect(throws: ImageImportError.unreadable) { _ = try ImageImporter.load(url: missing) }
  }

  @Test func zeroSizeImageThrows() {
    // A PNG header declaring 0x0 pixels.
    let png: [UInt8] = [
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52, 0, 0, 0, 0, 0, 0, 0, 0, 8, 6,
      0, 0, 0, 0xA0, 0x4B, 0xF4, 0x2B, 0, 0, 0, 0, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
    ]
    #expect(throws: ImageImportError.self) { _ = try ImageImporter.load(data: Data(png)) }
  }
}
