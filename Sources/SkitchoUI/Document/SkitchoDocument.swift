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
      guard let data = configuration.file.regularFileContents else { throw ImageImportError.unreadable }
      self.initial = try ImageImporter.load(data: data)
    }
  }

  /// A new document: the pending clipboard document (see `PendingDocument`), else a blank canvas.
  public nonisolated init() {
    self.initial = PendingDocument.take() ?? Document.blank()
  }

  /// Wraps an already decoded document (New from Clipboard, tests).
  public nonisolated init(initial: Document) {
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

/// Hands a decoded document to the next `SkitchoDocument()`. `NewDocumentAction` can only create blank
/// documents for a `ReferenceFileDocument`, so New from Clipboard stores the clipboard image here and then
/// asks for a new document; the new document's initializer takes it.
public enum PendingDocument {
  private nonisolated(unsafe) static var value: Document?
  private static let lock = NSLock()

  public static func set(_ document: Document) {
    lock.withLock { value = document }
  }

  static func take() -> Document? {
    lock.withLock {
      defer { value = nil }
      return value
    }
  }

  /// Drops a document that was set but never claimed.
  public static func clear() {
    lock.withLock { value = nil }
  }
}
