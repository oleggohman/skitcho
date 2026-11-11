import CoreGraphics
import Foundation
import SkitchoCore
import Testing
import UniformTypeIdentifiers

@testable import SkitchoUI

@Suite struct DocumentSpikeTests {
  @MainActor @Test func writableTypesAreSkitchoOnly() {
    #expect(SkitchoDocument.writableContentTypes == [.skitchoDocument])
    #expect(SkitchoDocument.readableContentTypes.contains(.image))
  }

  @MainActor @Test func blankInitHasDefaultCanvas() {
    let doc = SkitchoDocument()
    #expect(doc.initial.canvasSize == CGSize(width: 800, height: 600))
    #expect(doc.editor.document.canvasSize == doc.initial.canvasSize)
  }

  @MainActor @Test func packageRoundTripThroughSnapshot() throws {
    let doc = SkitchoDocument()
    let style = Style.make(tool: .line, imageSize: CGSize(width: 800, height: 600))
    doc.editor.document.elements = [
      Element(kind: .line(start: CGPoint(x: 1, y: 2), end: CGPoint(x: 30, y: 40)), style: style)
    ]
    let snap = try doc.snapshot(contentType: .skitchoDocument)
    let wrapper = try PackageCodec.wrapper(for: snap)
    #expect(wrapper.isDirectory)
    #expect(wrapper.fileWrappers?[PackageCodec.jsonName] != nil)
    #expect(wrapper.fileWrappers?[PackageCodec.imageName] != nil)
    let back = try PackageCodec.document(from: wrapper)
    #expect(back.canvasSize == snap.canvasSize)
    #expect(back.elements == snap.elements)
    #expect(back.baseImage.width == 800)
  }

  @Test func pngDataYieldsDocument() throws {
    let png = try PackageCodec.pngData(Document.blank(size: CGSize(width: 20, height: 10)).baseImage)
    let doc = try ImageImporter.load(data: png)
    #expect(doc.canvasSize == CGSize(width: 20, height: 10))
    #expect(doc.elements.isEmpty)
  }

  @Test func errorsAreTyped() {
    #expect(throws: ImageImportError.unreadable) {
      _ = try ImageImporter.load(data: Data([1, 2, 3]))
    }
    let empty = FileWrapper(directoryWithFileWrappers: [:])
    #expect(throws: PackageCodecError.missingFile(PackageCodec.jsonName)) {
      _ = try PackageCodec.document(from: empty)
    }
  }

  @MainActor @Test func decodingRunsOffMainActor() async throws {
    let source = Document.blank(size: CGSize(width: 32, height: 16))
    let wrapper = try PackageCodec.wrapper(for: source)
    nonisolated(unsafe) let sendableWrapper = wrapper
    let decoded = try await Task.detached {
      try PackageCodec.document(from: sendableWrapper)
    }.value
    let doc = SkitchoDocument(initial: decoded)
    #expect(doc.editor.document.canvasSize == CGSize(width: 32, height: 16))
  }
}
