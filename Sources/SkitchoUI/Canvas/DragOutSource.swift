import AppKit
import SkitchoCore
import SwiftUI
import UniformTypeIdentifiers

import struct SkitchoCore.Document

/// Provides the flattened document as a PNG file promise: the destination (Finder, a mail window) tells the
/// drag where to write, so nothing is rendered until the drop.
@MainActor
public final class DragOutSource: NSObject, NSFilePromiseProviderDelegate {
  public static let fallbackName = "Skitcho"

  private let document: () -> Document
  private let documentName: () -> String?
  private let queue: OperationQueue = {
    let queue = OperationQueue()
    queue.qualityOfService = .userInitiated
    return queue
  }()

  public init(document: @escaping () -> Document, documentName: @escaping () -> String?) {
    self.document = document
    self.documentName = documentName
  }

  /// The promised file name: the document name without extension (path separators removed), else "Skitcho".
  public static func fileName(forDocumentName name: String?) -> String {
    var base = ((name ?? "") as NSString).deletingPathExtension
    base = base.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
    base = base.trimmingCharacters(in: .whitespacesAndNewlines)
    if base.isEmpty || base.hasPrefix(".") { base = fallbackName }
    return base + ".png"
  }

  /// A provider that carries a snapshot of the document taken now.
  public func makeProvider() -> NSFilePromiseProvider {
    let provider = NSFilePromiseProvider(fileType: UTType.png.identifier, delegate: self)
    provider.userInfo = document()
    return provider
  }

  /// Renders `document` at 1x as PNG into `url`.
  public nonisolated static func write(_ document: Document, to url: URL) throws {
    let data = try Exporter.data(document, format: .png, scale: 1)
    try data.write(to: url, options: .atomic)
  }

  // MARK: NSFilePromiseProviderDelegate

  public nonisolated func filePromiseProvider(
    _ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String
  ) -> String {
    MainActor.assumeIsolated { Self.fileName(forDocumentName: documentName()) }
  }

  public nonisolated func filePromiseProvider(
    _ filePromiseProvider: NSFilePromiseProvider, writePromiseTo url: URL,
    completionHandler: @escaping @Sendable (Error?) -> Void
  ) {
    guard let document = filePromiseProvider.userInfo as? Document else {
      completionHandler(ExportError.encodingFailed)
      return
    }
    do {
      try Self.write(document, to: url)
      completionHandler(nil)
    } catch {
      completionHandler(error)
    }
  }

  public nonisolated func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue {
    MainActor.assumeIsolated { queue }
  }
}

/// A small handle that starts the file-promise drag when dragged.
final class DragOutHandleView: NSView, NSDraggingSource {
  var source: DragOutSource?

  override var intrinsicContentSize: NSSize { NSSize(width: 28, height: 22) }

  override func draw(_ dirtyRect: NSRect) {
    guard
      let image = NSImage(
        systemSymbolName: "square.and.arrow.up.on.square", accessibilityDescription: "Drag image out")
    else { return }
    let size = NSSize(width: 16, height: 16)
    let rect = NSRect(
      x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2, width: size.width,
      height: size.height)
    let tinted = NSImage(size: size, flipped: false) { frame in
      image.draw(in: frame)
      NSColor.secondaryLabelColor.set()
      frame.fill(using: .sourceAtop)
      return true
    }
    tinted.draw(in: rect)
  }

  override func mouseDown(with event: NSEvent) {}

  override func mouseDragged(with event: NSEvent) {
    guard let source else { return }
    let item = NSDraggingItem(pasteboardWriter: source.makeProvider())
    let preview = NSImage(systemSymbolName: "photo", accessibilityDescription: nil) ?? NSImage()
    item.setDraggingFrame(NSRect(x: 0, y: 0, width: 32, height: 32), contents: preview)
    beginDraggingSession(with: [item], event: event, source: self)
  }

  func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext)
    -> NSDragOperation
  { .copy }
}

/// SwiftUI wrapper for the drag-out handle.
struct DragOutHandle: NSViewRepresentable {
  let source: DragOutSource

  func makeNSView(context: Context) -> DragOutHandleView {
    let view = DragOutHandleView()
    view.source = source
    view.toolTip = "Drag the image into another app or folder"
    return view
  }

  func updateNSView(_ nsView: DragOutHandleView, context: Context) { nsView.source = source }
}
