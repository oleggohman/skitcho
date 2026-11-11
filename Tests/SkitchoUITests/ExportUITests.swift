import CoreGraphics
import Foundation
import ImageIO
import SkitchoCore
import Testing

import struct SkitchoCore.Document

@testable import SkitchoUI

private final class LockedBox<T>: @unchecked Sendable {
  private let lock = NSLock()
  private var stored: T
  init(_ value: T) { stored = value }
  var value: T {
    get { lock.withLock { stored } }
    set { lock.withLock { stored = newValue } }
  }
}

@MainActor
@Suite struct ExportUITests {
  /// A private defaults suite, removed again by `cleanup`.
  private func privateDefaults() -> (UserDefaults, cleanup: () -> Void) {
    let name = "skitcho.tests.export.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    return (defaults, { defaults.removePersistentDomain(forName: name) })
  }

  @Test func defaultsAreLosslessPngAtOneX() {
    let (defaults, cleanup) = privateDefaults()
    defer { cleanup() }
    let model = ExportAccessoryModel(defaults: defaults)
    #expect(model.format == .png)
    #expect(model.scale == 1)
    #expect(model.jpegQuality == ExportAccessoryModel.defaultQuality)
  }

  @Test func stateMapsToExportFormatAndScale() {
    let (defaults, cleanup) = privateDefaults()
    defer { cleanup() }
    let model = ExportAccessoryModel(defaults: defaults)
    model.kind = .jpeg
    model.jpegQuality = 0.4
    model.retina = true
    #expect(model.format == .jpeg(quality: 0.4))
    #expect(model.scale == 2)
    model.kind = .tiff
    #expect(model.format == .tiff)
    model.kind = .png
    #expect(model.format == .png)
  }

  @Test func lastChoiceIsRemembered() {
    let (defaults, cleanup) = privateDefaults()
    defer { cleanup() }
    let first = ExportAccessoryModel(defaults: defaults)
    first.kind = .jpeg
    first.jpegQuality = 0.55
    first.retina = true
    let second = ExportAccessoryModel(defaults: defaults)
    #expect(second.kind == .jpeg)
    #expect(second.jpegQuality == 0.55)
    #expect(second.retina)
  }

  @Test func invalidStoredValuesFallBack() {
    let (defaults, cleanup) = privateDefaults()
    defer { cleanup() }
    defaults.set("bmp", forKey: ExportAccessoryModel.Key.kind)
    defaults.set(7.0, forKey: ExportAccessoryModel.Key.quality)
    let model = ExportAccessoryModel(defaults: defaults)
    #expect(model.kind == .png)
    #expect(model.jpegQuality == 1)
  }

  @Test func fileNameFollowsTheFormat() {
    let (defaults, cleanup) = privateDefaults()
    defer { cleanup() }
    let model = ExportAccessoryModel(defaults: defaults)
    #expect(model.fileName(for: "Shot.png") == "Shot.png")
    model.kind = .jpeg
    #expect(model.fileName(for: "Shot.png") == "Shot.jpg")
    model.kind = .tiff
    #expect(model.fileName(for: "Shot.jpg") == "Shot.tiff")
    #expect(model.fileName(for: "v1.2 draft") == "v1.2 draft.tiff")
  }

  @Test func exportAsCommandIsEnabledAndPresents() {
    let editor = EditorModel(document: Document.blank(size: CGSize(width: 40, height: 30)), undoManager: nil)
    let handle = CanvasHandle()
    let model = EditorCommandModel(editor: editor, handle: handle)
    var presented = 0
    model.presentExport = { presented += 1 }
    #expect(model.isEnabled(.exportAs))
    #expect(model.perform(.exportAs))
    #expect(presented == 1)
  }

  // MARK: Drag-out

  @Test func dragFileNameUsesDocumentNameOrFallback() {
    #expect(DragOutSource.fileName(forDocumentName: "My Shot") == "My Shot.png")
    #expect(DragOutSource.fileName(forDocumentName: "My Shot.skitcho") == "My Shot.png")
    #expect(DragOutSource.fileName(forDocumentName: "a/b:c") == "a-b-c.png")
    #expect(DragOutSource.fileName(forDocumentName: nil) == "Skitcho.png")
    #expect(DragOutSource.fileName(forDocumentName: "  ") == "Skitcho.png")
    #expect(DragOutSource.fileName(forDocumentName: ".hidden") == "Skitcho.png")
  }

  @Test func promiseProviderCarriesPngTypeAndFileName() {
    let editor = EditorModel(document: Document.blank(size: CGSize(width: 40, height: 30)), undoManager: nil)
    let source = DragOutSource(document: { editor.document }, documentName: { "Notes.skitcho" })
    let provider = source.makeProvider()
    #expect(provider.fileType == "public.png")
    #expect(source.filePromiseProvider(provider, fileNameForType: "public.png") == "Notes.png")
  }

  /// AppKit may call the name and queue callbacks off the main thread; they must not trap there, and the name
  /// is the one taken when the drag started.
  @Test func promiseCallbacksWorkOffTheMainThread() async {
    var name = "Before.skitcho"
    let source = DragOutSource(
      document: { Document.blank(size: CGSize(width: 4, height: 3)) }, documentName: { name })
    nonisolated(unsafe) let provider = source.makeProvider()
    name = "Renamed.skitcho"
    let (fileName, hasQueue, onMain) = await withCheckedContinuation { continuation in
      DispatchQueue.global().async {
        continuation.resume(
          returning: (
            source.filePromiseProvider(provider, fileNameForType: "public.png"),
            source.operationQueue(for: provider).qualityOfService == .userInitiated,
            Thread.isMainThread
          ))
      }
    }
    #expect(!onMain)
    #expect(fileName == "Before.png")
    #expect(hasQueue)
  }

  @Test func promiseWriterProducesDecodablePng() throws {
    let editor = EditorModel(document: Document.blank(size: CGSize(width: 40, height: 30)), undoManager: nil)
    let source = DragOutSource(document: { editor.document }, documentName: { nil })
    let provider = source.makeProvider()
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("skitcho-drag-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent(source.filePromiseProvider(provider, fileNameForType: "public.png"))

    let done = DispatchSemaphore(value: 0)
    let failure = LockedBox<Error?>(nil)
    source.filePromiseProvider(provider, writePromiseTo: url) {
      failure.value = $0
      done.signal()
    }
    #expect(done.wait(timeout: .now() + 5) == .success)
    #expect(failure.value == nil)
    #expect(url.lastPathComponent == "Skitcho.png")
    let image = CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
    #expect(image?.width == 40)
    #expect(image?.height == 30)
    let type = CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceGetType($0) } as String?
    #expect(type == "public.png")
  }
}
