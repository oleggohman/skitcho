import AppKit
import SkitchoCore
import UniformTypeIdentifiers

import struct SkitchoCore.Document

/// What the Save panel is asked to show.
public struct SavePanelRequest: Equatable {
  public var suggestedName: String
  public var directory: URL?
  /// The format preselected in the popup (JPEG for every request this coordinator makes).
  public var defaultFormat: SaveFormat
}

/// The user's choice in the Save panel.
public struct SavePanelChoice: Equatable {
  public var url: URL
  public var format: SaveFormat
}

/// Owns the Save and Save As behaviour of one editor window.
///
/// `SkitchoDocument` can only write `.skitcho` (see `SaveFormat`), so a JPEG never goes through the document
/// system's autosave. This coordinator writes the flattened JPEG itself and talks to the window's `NSDocument`
/// directly for everything else. All of it runs on the main actor and never blocks it: the document system's own
/// save is asynchronous and calls the nonisolated `snapshot` on a worker.
@MainActor
public final class SaveCoordinator {
  /// Shows the Save panel and calls back with the choice, or nil when cancelled.
  public typealias PanelPresenter = (SavePanelRequest, @escaping (SavePanelChoice?) -> Void) -> Void
  /// Replaces `target` with `data`, atomically and through file coordination. Throws on failure.
  public typealias Writer = (Data, URL, NSDocument) throws -> Void
  /// Finds the document that belongs to a window.
  public typealias DocumentResolver = (NSWindow?) -> NSDocument?

  private let editor: EditorModel
  private let handle: CanvasHandle
  private let window: () -> NSWindow?
  private let resolveDocument: DocumentResolver
  private let writer: Writer
  private let presentPanel: PanelPresenter

  /// The JPEG file this window saves to with Save, set by saving through the panel as JPEG.
  public private(set) var jpegTarget: URL?
  /// The file URL `DocumentGroup` passed to the window view. Used only when `NSDocument.fileURL` is nil, and read
  /// at save time (the view keeps it current), never cached by the coordinator itself.
  public var fallbackURL: URL?
  /// Receives the readable message of a failed save (the window shows it as an alert).
  public var onError: ((String) -> Void)?

  public init(
    editor: EditorModel,
    handle: CanvasHandle,
    window: (() -> NSWindow?)? = nil,
    resolveDocument: DocumentResolver? = nil,
    writer: Writer? = nil,
    presentPanel: PanelPresenter? = nil
  ) {
    self.editor = editor
    self.handle = handle
    self.window = window ?? { [weak handle] in handle?.canvas?.window }
    self.resolveDocument = resolveDocument ?? Self.defaultResolver
    self.writer = writer ?? Self.coordinatedReplace
    self.presentPanel = presentPanel ?? Self.defaultPanel(window: self.window)
  }

  // MARK: Commands

  /// Save (⌘S). A `.skitcho` file with a URL saves through the document; a JPEG target or opened JPEG is
  /// overwritten with a flattened JPEG; anything else asks where to save.
  public func save() {
    guard let nsDocument = resolveDocument(window()) else { return }
    if Self.isSkitchoFile(nsDocument) {
      nsDocument.save(nil)
    } else if let target = jpegTarget ?? openedJPEGURL(of: nsDocument) {
      writeJPEG(to: target, for: nsDocument, retarget: false, markSaved: true)
    } else {
      saveAs()
    }
  }

  /// Save As… (⇧⌘S): always the panel, JPEG preselected.
  public func saveAs() {
    guard let nsDocument = resolveDocument(window()) else { return }
    let current = nsDocument.fileURL
    let request = SavePanelRequest(
      suggestedName: Self.baseName(of: nsDocument), directory: current?.deletingLastPathComponent(),
      defaultFormat: .jpeg)
    presentPanel(request) { [weak self, weak nsDocument] choice in
      guard let self, let nsDocument, let choice else { return }
      switch choice.format {
      case .jpeg:
        // A JPEG saved from a `.skitcho` file is a copy: the document keeps saving `.skitcho`.
        let isCopy = Self.isSkitchoFile(nsDocument)
        self.writeJPEG(to: choice.url, for: nsDocument, retarget: !isCopy, markSaved: !isCopy)
      case .skitcho:
        self.jpegTarget = nil
        self.saveAsSkitcho(to: choice.url, nsDocument)
      }
    }
  }

  /// Runs a File menu item on this window's document. Returns false when it is disabled or has no document.
  /// Close is not handled here: the menu sends it to the key window directly.
  @discardableResult
  public func perform(_ item: FileMenuItem) -> Bool {
    guard isEnabled(item), let nsDocument = resolveDocument(window()) else { return false }
    switch item {
    case .close: return false
    case .save: save()
    case .saveAs: saveAs()
    case .duplicate: nsDocument.duplicate(nil)
    case .revertToSaved: nsDocument.revertToSaved(nil)
    case .rename: nsDocument.rename(nil)
    case .moveTo: nsDocument.move(nil)
    }
    return true
  }

  /// Whether `item` is available for this window's document.
  public func isEnabled(_ item: FileMenuItem) -> Bool {
    item.isEnabled(hasKeyWindow: true, document: resolveDocument(window()))
  }

  // MARK: Document access

  /// The window's document: the controller's lookup first, then the window controller's link.
  static let defaultResolver: DocumentResolver = { window in
    guard let window else { return nil }
    return NSDocumentController.shared.document(for: window) ?? window.windowController?.document as? NSDocument
  }

  /// A `.skitcho` document that already has a file: the only kind the document system saves.
  static func isSkitchoFile(_ nsDocument: NSDocument) -> Bool {
    guard nsDocument.fileURL != nil, let type = nsDocument.fileType.flatMap({ UTType($0) }) else { return false }
    return type.conforms(to: .skitchoDocument)
  }

  /// The JPEG file the document was opened from, read now (never cached): `NSDocument.fileURL`, else the URL
  /// the window view was given. Accepted only when the document type or the file's type is JPEG.
  private func openedJPEGURL(of nsDocument: NSDocument) -> URL? {
    guard let url = nsDocument.fileURL ?? fallbackURL else { return nil }
    if let type = nsDocument.fileType.flatMap({ UTType($0) }), type.conforms(to: .jpeg) { return url }
    if let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .jpeg) { return url }
    return nil
  }

  private static func baseName(of nsDocument: NSDocument) -> String {
    let name = nsDocument.displayName ?? "Untitled"
    return (name as NSString).deletingPathExtension
  }

  // MARK: Skitcho handoff

  private func saveAsSkitcho(to url: URL, _ nsDocument: NSDocument) {
    // The editable format goes through the document system, which uses the nonisolated snapshot/fileWrapper.
    nsDocument.save(to: url, ofType: UTType.skitchoDocument.identifier, for: .saveAsOperation) {
      [weak self] error in
      guard let error else { return }
      let message = error.localizedDescription
      Task { @MainActor in self?.onError?(message) }
    }
  }

  // MARK: JPEG write

  /// Flattens the document and replaces `target`. A failure is reported and leaves the document dirty.
  private func writeJPEG(to target: URL, for nsDocument: NSDocument, retarget: Bool, markSaved: Bool) {
    // The live text string must be part of the file.
    handle.canvas?.commitTextEdit()
    do {
      let data = try SaveFormat.jpegData(for: editor.document)
      try writer(data, target, nsDocument)
    } catch {
      onError?(error.localizedDescription)
      return
    }
    if retarget { jpegTarget = target }
    guard markSaved else { return }
    if let date = try? target.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
      nsDocument.fileModificationDate = date
    }
    nsDocument.updateChangeCount(.changeCleared)
  }

  /// The default writer: a temp file next to the target, swapped in under file coordination that excludes the
  /// document's own presenter (so no auto-revert can discard the vector annotations).
  static let coordinatedReplace: Writer = { data, target, nsDocument in
    let fileManager = FileManager.default
    let exists = fileManager.fileExists(atPath: target.path)
    let tempDirectory = try fileManager.url(
      for: .itemReplacementDirectory, in: .userDomainMask,
      appropriateFor: exists ? target : target.deletingLastPathComponent(), create: true)
    defer { try? fileManager.removeItem(at: tempDirectory) }
    let temp = tempDirectory.appendingPathComponent(target.lastPathComponent)
    try data.write(to: temp)

    var coordinationError: NSError?
    var replaceError: Error?
    NSFileCoordinator(filePresenter: nsDocument).coordinate(
      writingItemAt: target, options: .forReplacing, error: &coordinationError
    ) { coordinated in
      do {
        if fileManager.fileExists(atPath: coordinated.path) {
          _ = try fileManager.replaceItemAt(coordinated, withItemAt: temp)
        } else {
          try fileManager.moveItem(at: temp, to: coordinated)
        }
      } catch {
        replaceError = error
      }
    }
    if let error = coordinationError ?? replaceError { throw error }
  }

  // MARK: Default panel

  /// The Save panel as a window sheet, with the JPEG/Skitcho format popup as its accessory.
  static func defaultPanel(window: @escaping () -> NSWindow?) -> PanelPresenter {
    { request, completion in
      let panel = NSSavePanel()
      panel.nameFieldStringValue = request.suggestedName
      panel.directoryURL = request.directory
      panel.canCreateDirectories = true
      let accessory = SaveFormatAccessoryView(panel: panel, initial: request.defaultFormat)
      panel.accessoryView = accessory
      let finish: (NSApplication.ModalResponse) -> Void = { response in
        guard response == .OK, let url = panel.url else { return completion(nil) }
        completion(SavePanelChoice(url: url, format: accessory.selectedFormat))
      }
      if let window = window() {
        panel.beginSheetModal(for: window, completionHandler: finish)
      } else {
        panel.begin(completionHandler: finish)
      }
    }
  }
}
