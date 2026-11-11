import AppKit
import CoreGraphics
import Foundation
import SkitchoCore
import SwiftUI
import Testing
import UniformTypeIdentifiers

import struct SkitchoCore.Document

@testable import SkitchoUI

@Suite struct DocumentTests {
  @MainActor private func documentWithElements() -> SkitchoDocument {
    let doc = SkitchoDocument()
    let size = doc.initial.canvasSize
    doc.editor.document.elements = [
      Element(
        kind: .line(start: CGPoint(x: 5, y: 6), end: CGPoint(x: 90, y: 60)),
        style: Style.make(tool: .line, imageSize: size)),
      Element(
        kind: .rect(CGRect(x: 10, y: 20, width: 100, height: 50), rounded: true),
        style: Style.make(tool: .roundedRect, imageSize: size)),
    ]
    return doc
  }

  @MainActor @Test func snapshotAndFileWrapperRoundTripWithElements() throws {
    let doc = documentWithElements()
    let snap = try doc.snapshot(contentType: .skitchoDocument)
    // `fileWrapper(snapshot:configuration:)` is a pure PackageCodec call (WriteConfiguration cannot be built).
    let wrapper = try PackageCodec.wrapper(for: snap)
    #expect(wrapper.isDirectory)
    let back = SkitchoDocument(initial: try PackageCodec.document(from: wrapper))
    #expect(back.editor.document.elements == doc.editor.document.elements)
    #expect(back.editor.document.canvasSize == doc.editor.document.canvasSize)
  }

  @MainActor @Test func snapshotReflectsLiveEditorState() throws {
    let doc = documentWithElements()
    doc.editor.select(doc.editor.document.elements[0].id)
    doc.editor.removeSelection()
    #expect(try doc.snapshot(contentType: .skitchoDocument).elements.count == 1)
  }

  @MainActor @Test func imageOpenedDocumentsSaveAsSkitcho() throws {
    // Plain images are readable but never writable, so SwiftUI treats an opened image as untitled-like and the
    // first save asks for a `.skitcho` location; the source file is not a save target.
    #expect(SkitchoDocument.readableContentTypes.contains(.image))
    #expect(SkitchoDocument.writableContentTypes == [.skitchoDocument])
    #expect(!SkitchoDocument.writableContentTypes.contains { $0.conforms(to: .image) })
    // The image decode path yields a document with the picture as base and no elements.
    let png = try PackageCodec.pngData(Document.blank(size: CGSize(width: 40, height: 30)).baseImage)
    let doc = SkitchoDocument(initial: try ImageImporter.load(data: png))
    #expect(doc.editor.document.canvasSize == CGSize(width: 40, height: 30))
    #expect(doc.editor.document.elements.isEmpty)
    // Whatever was read, the written wrapper is a `.skitcho` package.
    let wrapper = try PackageCodec.wrapper(for: doc.snapshot(contentType: .skitchoDocument))
    #expect(wrapper.fileWrappers?[PackageCodec.jsonName] != nil)
  }

  @MainActor @Test func undoRegistrationsGoThroughTheWindowManager() {
    let doc = SkitchoDocument()
    let editor = doc.editor
    #expect(editor.undoManager == nil)
    let manager = UndoManager()
    EditorWindowView.bind(editor, to: manager)
    #expect(editor.undoManager === manager)
    #expect(!manager.canUndo)
    editor.perform("Resize Image") { $0.background = .red }
    #expect(manager.canUndo)
    #expect(manager.undoActionName == "Resize Image")
    manager.undo()
    #expect(editor.document.background != .red)
    #expect(manager.canRedo)
  }

  @MainActor @Test func bindingNilDetachesTheManager() {
    let editor = SkitchoDocument().editor
    EditorWindowView.bind(editor, to: UndoManager())
    EditorWindowView.bind(editor, to: nil)
    #expect(editor.undoManager == nil)
  }

  @MainActor @Test func windowViewHostsTheCanvas() {
    let doc = SkitchoDocument()
    let host = NSHostingView(rootView: EditorWindowView(document: doc))
    host.frame = CGRect(x: 0, y: 0, width: 900, height: 640)
    let window = NSWindow(
      contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: true)
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    func canvas(in view: NSView) -> CanvasView? {
      if let found = view as? CanvasView { return found }
      for sub in view.subviews { if let found = canvas(in: sub) { return found } }
      return nil
    }
    let found = canvas(in: host)
    #expect(found != nil)
    #expect(found?.editor === doc.editor)
  }

  @MainActor @Test func zoomChangesReachTheHandle() {
    let editor = SkitchoDocument().editor
    let canvas = CanvasView(editor: editor)
    let handle = CanvasHandle()
    handle.attach(canvas)
    handle.zoomIn()
    #expect(abs(handle.zoom - CanvasView.zoomStep) < 1e-9)
    handle.actualSize()
    #expect(handle.zoom == 1)
  }
}
