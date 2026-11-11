import AppKit
import CoreGraphics
import Foundation
import ImageIO
import SkitchoCore
import Testing
import UniformTypeIdentifiers

import struct SkitchoCore.Document

@testable import SkitchoUI

/// An `NSDocument` that records what the coordinator asks of it instead of saving.
private final class RecordingDocument: NSDocument {
  var saveCalls = 0
  var saveAsCalls = 0
  var savedTo: [(url: URL, type: String, operation: NSDocument.SaveOperationType)] = []
  /// Reported by `save(to:ofType:for:)` instead of succeeding, when set.
  var saveError: Error?

  override func save(_ sender: Any?) { saveCalls += 1 }
  override func saveAs(_ sender: Any?) { saveAsCalls += 1 }
  override func save(
    to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType,
    completionHandler: @escaping (Error?) -> Void
  ) {
    savedTo.append((url, typeName, saveOperation))
    completionHandler(saveError)
  }
}

@MainActor
@Suite struct SaveCoordinatorTests {
  private struct Failure: LocalizedError {
    var errorDescription: String? { "disk is full" }
  }

  private final class PanelLog {
    var requests: [SavePanelRequest] = []
    var choice: SavePanelChoice?
  }

  private let directory: URL

  init() throws {
    directory = FileManager.default.temporaryDirectory.appendingPathComponent("skitcho-save-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  // MARK: Helpers

  private func solidImage(red: Double) -> CGImage {
    let context = CGContext(
      data: nil, width: 120, height: 80, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(srgbRed: red, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 120, height: 80))
    return context.makeImage()!
  }

  private func makeEditor() -> EditorModel {
    let manager = UndoManager()
    manager.groupsByEvent = false
    return EditorModel(document: Document(baseImage: solidImage(red: 1)), undoManager: manager)
  }

  private func isJPEG(_ data: Data) -> Bool { data.prefix(2) == Data([0xFF, 0xD8]) }

  private func decodedSize(_ data: Data) -> CGSize? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { return nil }
    return CGSize(width: image.width, height: image.height)
  }

  /// A file on disk with `data`, e.g. an opened JPEG or PNG.
  private func writeFile(_ name: String, _ data: Data) throws -> URL {
    let url = directory.appendingPathComponent(name)
    try data.write(to: url)
    return url
  }

  /// A JPEG that differs from anything the (red) test editor produces.
  private func blackJPEG() throws -> Data {
    try SaveFormat.jpegData(for: Document(baseImage: solidImage(red: 0)))
  }

  private func document(type: UTType, url: URL?) -> RecordingDocument {
    let nsDocument = RecordingDocument()
    nsDocument.fileType = type.identifier
    nsDocument.fileURL = url
    nsDocument.updateChangeCount(.changeDone)
    return nsDocument
  }

  private func makeCoordinator(
    _ editor: EditorModel, handle: CanvasHandle = CanvasHandle(), nsDocument: NSDocument?,
    log: PanelLog = PanelLog(), writer: SaveCoordinator.Writer? = nil
  ) -> SaveCoordinator {
    SaveCoordinator(
      editor: editor, handle: handle, window: { nil }, resolveDocument: { _ in nsDocument }, writer: writer,
      presentPanel: { request, completion in
        log.requests.append(request)
        completion(log.choice)
      })
  }

  // MARK: Opened JPEG

  @Test func saveOverwritesTheOpenedJPEGWithAFlattenedJPEG() throws {
    let black = try blackJPEG()
    let url = try writeFile("photo.jpg", black)
    let nsDocument = document(type: .jpeg, url: url)
    let log = PanelLog()
    let coordinator = makeCoordinator(makeEditor(), nsDocument: nsDocument, log: log)

    coordinator.save()

    let data = try Data(contentsOf: url)
    #expect(isJPEG(data))
    #expect(decodedSize(data) == CGSize(width: 120, height: 80))
    #expect(data != black)
    #expect(!nsDocument.isDocumentEdited)
    let date = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    #expect(date != nil)
    #expect(nsDocument.fileModificationDate == date)
    #expect(log.requests.isEmpty)
    #expect(nsDocument.saveCalls == 0 && nsDocument.savedTo.isEmpty)
  }

  @Test func openedJPEGUsesTheFallbackURLWhenTheDocumentHasNone() throws {
    let black = try blackJPEG()
    let url = try writeFile("photo.jpg", black)
    let nsDocument = document(type: .jpeg, url: nil)
    let log = PanelLog()
    let coordinator = makeCoordinator(makeEditor(), nsDocument: nsDocument, log: log)
    coordinator.fallbackURL = url

    coordinator.save()

    #expect(try Data(contentsOf: url) != black)
    #expect(log.requests.isEmpty)
    #expect(!nsDocument.isDocumentEdited)
  }

  @Test func openedJPEGWithoutAnyURLShowsTheJPEGDefaultPanel() {
    let nsDocument = document(type: .jpeg, url: nil)
    let log = PanelLog()
    let coordinator = makeCoordinator(makeEditor(), nsDocument: nsDocument, log: log)

    coordinator.save()

    #expect(log.requests.count == 1)
    #expect(log.requests.first?.defaultFormat == .jpeg)
    #expect(nsDocument.isDocumentEdited)
  }

  // MARK: Untitled

  @Test func untitledSaveAsksThenWritesAndLaterSavesWithoutThePanel() throws {
    let nsDocument = document(type: .skitchoDocument, url: nil)
    let log = PanelLog()
    let target = directory.appendingPathComponent("new.jpg")
    log.choice = SavePanelChoice(url: target, format: .jpeg)
    let coordinator = makeCoordinator(makeEditor(), nsDocument: nsDocument, log: log)

    coordinator.save()

    #expect(log.requests.count == 1)
    #expect(log.requests.first?.defaultFormat == .jpeg)
    #expect(isJPEG(try Data(contentsOf: target)))
    #expect(coordinator.jpegTarget == target)
    #expect(!nsDocument.isDocumentEdited)

    try FileManager.default.removeItem(at: target)
    nsDocument.updateChangeCount(.changeDone)
    coordinator.save()

    #expect(log.requests.count == 1)
    #expect(isJPEG(try Data(contentsOf: target)))
    #expect(!nsDocument.isDocumentEdited)
  }

  @Test func choosingSkitchoHandsOffToTheDocumentAndClearsTheTarget() {
    let nsDocument = document(type: .skitchoDocument, url: nil)
    let log = PanelLog()
    let jpeg = directory.appendingPathComponent("first.jpg")
    log.choice = SavePanelChoice(url: jpeg, format: .jpeg)
    let coordinator = makeCoordinator(makeEditor(), nsDocument: nsDocument, log: log)
    coordinator.saveAs()
    #expect(coordinator.jpegTarget == jpeg)

    let skitcho = directory.appendingPathComponent("edit.skitcho")
    log.choice = SavePanelChoice(url: skitcho, format: .skitcho)
    coordinator.saveAs()

    #expect(coordinator.jpegTarget == nil)
    #expect(nsDocument.savedTo.count == 1)
    #expect(nsDocument.savedTo.first?.url == skitcho)
    #expect(nsDocument.savedTo.first?.type == UTType.skitchoDocument.identifier)
    #expect(nsDocument.savedTo.first?.operation == .saveAsOperation)
    #expect(!FileManager.default.fileExists(atPath: skitcho.path))
  }

  @Test func aFailedSkitchoSaveKeepsTheJPEGTarget() throws {
    let black = try blackJPEG()
    let opened = try writeFile("a.jpg", black)
    let nsDocument = document(type: .jpeg, url: opened)
    let log = PanelLog()
    let jpeg = directory.appendingPathComponent("b.jpg")
    log.choice = SavePanelChoice(url: jpeg, format: .jpeg)
    let coordinator = makeCoordinator(makeEditor(), nsDocument: nsDocument, log: log)
    coordinator.saveAs()
    #expect(coordinator.jpegTarget == jpeg)

    nsDocument.saveError = Failure()
    log.choice = SavePanelChoice(url: directory.appendingPathComponent("c.skitcho"), format: .skitcho)
    coordinator.saveAs()
    #expect(nsDocument.savedTo.count == 1)
    #expect(coordinator.jpegTarget == jpeg)

    // ⌘S still writes the JPEG chosen by Save As and leaves the opened original alone.
    try FileManager.default.removeItem(at: jpeg)
    nsDocument.updateChangeCount(.changeDone)
    coordinator.save()
    #expect(isJPEG(try Data(contentsOf: jpeg)))
    #expect(try Data(contentsOf: opened) == black)
    #expect(!nsDocument.isDocumentEdited)
  }

  @Test func aJPEGSaveAsToAnotherFileLeavesTheDocumentModificationDate() throws {
    let opened = try writeFile("a.jpg", blackJPEG())
    let nsDocument = document(type: .jpeg, url: opened)
    let original = Date(timeIntervalSince1970: 1_000_000)
    nsDocument.fileModificationDate = original
    let log = PanelLog()
    let jpeg = directory.appendingPathComponent("b.jpg")
    log.choice = SavePanelChoice(url: jpeg, format: .jpeg)
    let coordinator = makeCoordinator(makeEditor(), nsDocument: nsDocument, log: log)

    coordinator.saveAs()
    #expect(isJPEG(try Data(contentsOf: jpeg)))
    #expect(!nsDocument.isDocumentEdited)
    #expect(nsDocument.fileModificationDate == original)

    // ⌘S to the Save As target does not touch it either.
    nsDocument.updateChangeCount(.changeDone)
    coordinator.save()
    #expect(!nsDocument.isDocumentEdited)
    #expect(nsDocument.fileModificationDate == original)
  }

  @Test func cancellingThePanelChangesNothing() {
    let nsDocument = document(type: .skitchoDocument, url: nil)
    let log = PanelLog()
    let coordinator = makeCoordinator(makeEditor(), nsDocument: nsDocument, log: log)

    coordinator.save()

    #expect(log.requests.count == 1)
    #expect(coordinator.jpegTarget == nil)
    #expect(nsDocument.isDocumentEdited)
    #expect(nsDocument.savedTo.isEmpty)
  }

  // MARK: .skitcho documents

  @Test func skitchoDocumentSavesThroughTheDocumentAndJPEGIsACopy() throws {
    let url = directory.appendingPathComponent("work.skitcho")
    let nsDocument = document(type: .skitchoDocument, url: url)
    let log = PanelLog()
    let copy = directory.appendingPathComponent("copy.jpg")
    log.choice = SavePanelChoice(url: copy, format: .jpeg)
    let coordinator = makeCoordinator(makeEditor(), nsDocument: nsDocument, log: log)

    coordinator.save()
    #expect(nsDocument.saveCalls == 1)
    #expect(log.requests.isEmpty)

    coordinator.saveAs()
    #expect(isJPEG(try Data(contentsOf: copy)))
    #expect(coordinator.jpegTarget == nil)
    // A copy does not count as saving the document.
    #expect(nsDocument.isDocumentEdited)

    coordinator.save()
    #expect(nsDocument.saveCalls == 2)
    #expect(log.requests.count == 1)
  }

  // MARK: Other images

  @Test func openedPNGAsksAndLeavesTheOriginalUntouched() throws {
    let png = try Exporter.data(Document(baseImage: solidImage(red: 0.5)), format: .png)
    let url = try writeFile("pic.png", png)
    let nsDocument = document(type: .png, url: url)
    let log = PanelLog()
    let coordinator = makeCoordinator(makeEditor(), nsDocument: nsDocument, log: log)

    coordinator.save()

    #expect(log.requests.count == 1)
    #expect(log.requests.first?.defaultFormat == .jpeg)
    #expect(try Data(contentsOf: url) == png)
  }

  // MARK: Text edit and failures

  @Test func saveDuringATextEditWritesTheLiveString() throws {
    let editor = makeEditor()
    editor.currentTool = .text
    let canvas = CanvasView(editor: editor)
    canvas.frame = CGRect(x: 0, y: 0, width: 400, height: 300)
    let handle = CanvasHandle()
    handle.attach(canvas)
    editor.undoManager?.beginUndoGrouping()
    defer { editor.undoManager?.endUndoGrouping() }
    canvas.activeController.mouseDown(at: CGPoint(x: 10, y: 10), modifiers: [])
    let overlay = try #require(canvas.textOverlay)
    overlay.string = "live"
    overlay.didChangeText()
    #expect(canvas.isEditingText)

    var written: Document?
    let url = try writeFile("photo.jpg", blackJPEG())
    let nsDocument = document(type: .jpeg, url: url)
    let coordinator = makeCoordinator(
      editor, handle: handle, nsDocument: nsDocument,
      writer: { _, _, _ in written = editor.document })

    coordinator.save()

    #expect(!canvas.isEditingText)
    let element = try #require(written?.elements.first)
    guard case .text(let content) = element.kind else {
      Issue.record("expected a text element")
      return
    }
    #expect(content.string == "live")
  }

  @Test func aWriteFailureLeavesTheDocumentDirtyAndReportsTheMessage() throws {
    let black = try blackJPEG()
    let url = try writeFile("photo.jpg", black)
    let nsDocument = document(type: .jpeg, url: url)
    let coordinator = makeCoordinator(
      makeEditor(), nsDocument: nsDocument, writer: { _, _, _ in throw Failure() })
    var messages: [String] = []
    coordinator.onError = { messages.append($0) }

    coordinator.save()

    #expect(messages == ["disk is full"])
    #expect(nsDocument.isDocumentEdited)
    #expect(try Data(contentsOf: url) == black)
  }

  @Test func aFlattenFailureShowsTheReadableMessageAndWritesNothing() throws {
    let url = try writeFile("photo.jpg", blackJPEG())
    let nsDocument = document(type: .jpeg, url: url)
    let editor = makeEditor()
    editor.document.canvasSize = CGSize(width: Double(ImageOps.maxSide) * 4, height: 10)
    var wrote = false
    let coordinator = makeCoordinator(editor, nsDocument: nsDocument, writer: { _, _, _ in wrote = true })
    var messages: [String] = []
    coordinator.onError = { messages.append($0) }

    coordinator.save()

    #expect(messages == ["The image is too large to render."])
    #expect(!wrote)
    #expect(nsDocument.isDocumentEdited)
  }

  @Test func theDefaultWriterReplacesAnExistingFileAndCreatesANewOne() throws {
    let url = try writeFile("photo.jpg", Data([1, 2, 3]))
    let nsDocument = RecordingDocument()
    try SaveCoordinator.coordinatedReplace(Data([9, 9]), url, nsDocument)
    #expect(try Data(contentsOf: url) == Data([9, 9]))
    let fresh = directory.appendingPathComponent("fresh.jpg")
    try SaveCoordinator.coordinatedReplace(Data([7]), fresh, nsDocument)
    #expect(try Data(contentsOf: fresh) == Data([7]))
  }
}
