import SkitchoCore
import SwiftUI
import Synchronization
import UniformTypeIdentifiers

import struct SkitchoCore.Document

/// Core `Document` collides with `SwiftUI.Document`, so files using both import it explicitly
/// (`import struct SkitchoCore.Document`).
/// The document type. Decoding and encoding are pure and nonisolated; the `editor` is created lazily on the
/// main actor from the view.
///
/// `snapshot(contentType:)` is `nonisolated`: NSDocument saves asynchronously and SwiftUI calls it on a
/// background dispatch worker (`ReferenceFileDocumentBox.snapshotForSerialization`). Crash report evidence:
/// at that moment the main thread sits in `-[NSDocument _waitForUserInteractionUnblocking]`
/// (`NSConditionLock lockWhenCondition:`) while the worker runs `snapshot`. So `snapshot` must neither touch
/// main-actor state (the Swift 6 isolation check traps) nor wait for the main thread (`DispatchQueue.main.sync`
/// or any main-actor hop that is awaited would deadlock). It only reads `store`, which the main actor keeps
/// current through `publish()`.
@MainActor
public final class SkitchoDocument: @preconcurrency ReferenceFileDocument {
  public static let readableContentTypes: [UTType] = [.skitchoDocument, .image]
  public static let writableContentTypes: [UTType] = [.skitchoDocument]

  public nonisolated let initial: Document
  /// The document `snapshot` serves, readable from any thread. Written only by `publish()` on the main actor.
  private nonisolated let store: SavableDocumentStore
  public lazy var editor: EditorModel = {
    let editor = EditorModel(document: initial, undoManager: nil)
    editor.onDocumentChange = { [weak self] in self?.publish() }
    return editor
  }()
  /// The window's canvas link (created on the main actor by the view). A running text edit is read through it.
  public lazy var canvasHandle: CanvasHandle = {
    let handle = CanvasHandle()
    handle.onSavableDocumentChange = { [weak self] in self?.publish() }
    return handle
  }()

  public nonisolated init(configuration: ReadConfiguration) throws {
    if configuration.contentType.conforms(to: .skitchoDocument) {
      self.initial = try PackageCodec.document(from: configuration.file)
    } else {
      guard let data = configuration.file.regularFileContents else { throw ImageImportError.unreadable }
      self.initial = try ImageImporter.load(data: data)
    }
    self.store = SavableDocumentStore(initial)
  }

  /// A new document: the pending clipboard document (see `PendingDocument`), else a blank canvas.
  public nonisolated init() {
    let initial = PendingDocument.take() ?? Document.blank()
    self.initial = initial
    self.store = SavableDocumentStore(initial)
  }

  /// Wraps an already decoded document (New from Clipboard, tests).
  public nonisolated init(initial: Document) {
    self.initial = initial
    self.store = SavableDocumentStore(initial)
  }

  /// Copies the current savable document into the store: `editor.document`, with a running text edit's live
  /// string in place. Runs on the main actor after every editor document change and every text edit change.
  private func publish() {
    let canvas = canvasHandle.canvas
    store.set(canvas?.savableDocument ?? editor.document, isEditingText: canvas?.isEditingText ?? false)
  }

  /// The document to write: the last published one (a text edit in progress is included with its live string
  /// and stays open). Runs on any thread and reads only the lock-protected store.
  ///
  /// A state written during a text edit must be on the undo stack (see `TextToolController.checkpointSavedEdit`).
  /// That is main-actor work, so it is scheduled, never awaited: the save returns at once and the checkpoint
  /// runs when the main thread is free. The window may keep its "edited" dot after such a save until the next
  /// save; that was accepted and no data is lost.
  public nonisolated func snapshot(contentType: UTType) throws -> Document {
    let (document, isEditingText) = store.get()
    if isEditingText {
      Task { @MainActor [weak self] in
        self?.canvasHandle.canvas?.checkpointSavedEdit(document)
      }
    }
    return document
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

/// Thread-safe holder of the document `SkitchoDocument.snapshot` serves. `Document` is a value type, so a
/// copy under the lock is cheap and the reader never sees a half-written state.
final class SavableDocumentStore: Sendable {
  private struct State {
    var document: Document
    var isEditingText = false
  }

  private let state: Mutex<State>

  init(_ document: Document) {
    state = Mutex(State(document: document))
  }

  func set(_ document: Document, isEditingText: Bool) {
    state.withLock { $0 = State(document: document, isEditingText: isEditingText) }
  }

  func get() -> (document: Document, isEditingText: Bool) {
    state.withLock { ($0.document, $0.isEditingText) }
  }
}
