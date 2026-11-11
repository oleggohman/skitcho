import CoreGraphics
import Foundation
import ImageIO
import ObjectiveC
import SkitchoCore
import Testing

import struct SkitchoCore.Document

@testable import SkitchoUI

@Suite struct SaveFormatTests {
  private func solidImage(width: Int, height: Int, red: Double, green: Double, blue: Double) -> CGImage {
    let context = CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
  }

  private func decode(_ data: Data) throws -> CGImage {
    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
  }

  /// RGB of one pixel (top-left origin) after redrawing into sRGB RGBA8.
  private func rgb(_ image: CGImage, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
    var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
    let width = image.width
    let height = image.height
    bytes.withUnsafeMutableBytes { buffer in
      let context = CGContext(
        data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    let i = (y * width + x) * 4
    return (Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2]))
  }

  private func annotatedDocument() -> Document {
    let style = Style(color: .red, sizeStep: .default, strokeWidth: 12, fontSize: 24)
    let rect = Element(kind: .rect(CGRect(x: 20, y: 20, width: 100, height: 60), rounded: false), style: style)
    return Document(
      baseImage: solidImage(width: 160, height: 120, red: 1, green: 1, blue: 1), elements: [rect])
  }

  @Test func formatsListJpegFirstWithExtensionsAndTypes() {
    #expect(SaveFormat.allCases == [.jpeg, .skitcho])
    #expect(SaveFormat.jpeg.fileExtension == "jpg")
    #expect(SaveFormat.skitcho.fileExtension == "skitcho")
    #expect(SaveFormat.jpeg.contentType == .jpeg)
    #expect(SaveFormat.skitcho.contentType == .skitchoDocument)
    #expect(SaveFormat.jpegQuality == 0.9)
  }

  @Test func jpegDecodesWithCanvasSizeAndFlattenedAnnotations() throws {
    let data = try SaveFormat.jpegData(for: annotatedDocument())
    #expect(data.prefix(2) == Data([0xFF, 0xD8]))
    let image = try decode(data)
    #expect(image.width == 160 && image.height == 120)
    let onStroke = rgb(image, 70, 20)  // top edge of the rect
    #expect(onStroke.r > 200 && onStroke.g < 150 && onStroke.b < 150, "stroke pixel \(onStroke)")
    let inside = rgb(image, 70, 50)
    #expect(inside.r > 240 && inside.g > 240 && inside.b > 240, "interior pixel \(inside)")
  }

  @Test func oversizedCanvasThrowsReadableErrorWithoutCrashing() {
    var document = annotatedDocument()
    document.canvasSize = CGSize(width: Double(ImageOps.maxSide) * 4, height: 10)
    #expect(throws: SaveFormatError(message: "The image is too large to render.")) {
      _ = try SaveFormat.jpegData(for: document)
    }
    document.canvasSize = CGSize(width: Double.nan, height: 10)
    #expect(throws: SaveFormatError.self) { _ = try SaveFormat.jpegData(for: document) }
  }

  @Test func jpegDataWorksOffTheMainActor() async throws {
    let document = annotatedDocument()
    let data: Data = try await withCheckedThrowingContinuation { continuation in
      DispatchQueue.global().async {
        continuation.resume(with: Result { try SaveFormat.jpegData(for: document) })
      }
    }
    #expect(try decode(data).width == 160)
  }

  // `writableContentTypes == [.skitchoDocument]` is pinned by `DocumentSpikeTests.writableTypesAreSkitchoOnly`.

  /// Read-only check of the fact the whole save design rests on: SwiftUI's document class autosaves in place, so a
  /// lossy type must never be writable. Fails loudly if Apple changes it; skipped when the private class is gone.
  @Test func swiftUIPlatformDocumentAutosavesInPlace() {
    // Skipped (returns) when the private class is absent: nothing to pin then.
    guard let cls = NSClassFromString("SwiftUI.PlatformDocument") else { return }
    let selector = NSSelectorFromString("autosavesInPlace")
    // Read the class method's BOOL through its IMP; no swizzling, no instance is created.
    guard let method = class_getClassMethod(cls, selector) else {
      Issue.record("SwiftUI.PlatformDocument has no +autosavesInPlace; revisit the JPEG save design")
      return
    }
    typealias Getter = @convention(c) (AnyClass, Selector) -> Bool
    let getter = unsafeBitCast(method_getImplementation(method), to: Getter.self)
    #expect(getter(cls, selector), "SwiftUI no longer autosaves in place; revisit the JPEG save design")
  }
}
