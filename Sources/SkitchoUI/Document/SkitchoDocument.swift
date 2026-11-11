import SkitchoCore
import SwiftUI
import UniformTypeIdentifiers

import struct SkitchoCore.Document

/// Core `Document` collides with `SwiftUI.Document`, so files using both import it explicitly
/// (`import struct SkitchoCore.Document`).
/// The document type. Decoding and encoding are pure and nonisolated; the `editor` is created lazily on the
/// main actor from the view. `MainActor.assumeIsolated` is deliberately not used because the document may be
/// read off the main thread.
@MainActor
public final class SkitchoDocument: @preconcurrency ReferenceFileDocument {
  public static let readableContentTypes: [UTType] = [.skitchoDocument, .image]
  public static let writableContentTypes: [UTType] = [.skitchoDocument]

  public nonisolated let initial: Document
  public lazy var editor = EditorModel(document: initial, undoManager: nil)

  public nonisolated init(configuration: ReadConfiguration) throws {
    if configuration.contentType.conforms(to: .skitchoDocument) {
      self.initial = try PackageCodec.document(from: configuration.file)
    } else {
      guard let data = configuration.file.regularFileContents else { throw PackageCodecError.corruptImage }
      self.initial = try PackageCodec.document(fromImageData: data)
    }
  }

  public nonisolated init() {
    self.initial = Document.blank()
  }

  /// Wraps an already decoded document (used by tests and future import paths).
  nonisolated init(initial: Document) {
    self.initial = initial
  }

  public func snapshot(contentType: UTType) throws -> Document {
    editor.document
  }

  public nonisolated func fileWrapper(
    snapshot: Document, configuration: WriteConfiguration
  ) throws -> FileWrapper {
    try PackageCodec.wrapper(for: snapshot)
  }
}
