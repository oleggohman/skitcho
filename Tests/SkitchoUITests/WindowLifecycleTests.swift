import AppKit
import CoreGraphics
import Foundation
import SkitchoCore
import SwiftUI
import Testing

import struct SkitchoCore.Document

@testable import SkitchoUI

@MainActor
@Suite struct WindowLifecycleTests {
  /// Lets SwiftUI run its pending updates (onAppear, state wiring) and AppKit release what it autoreleased.
  private func spin(_ seconds: TimeInterval = 0.2) {
    RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds))
  }

  private func makeWindow() -> NSWindow {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 900, height: 600), styleMask: [.titled, .closable],
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    return window
  }

  /// A closed editor window must release its editor, canvas and command model: closures stored on the command
  /// model must not capture the window view (its state storage owns the model).
  @Test func closingTheWindowReleasesEditorCanvasAndCommands() {
    weak var weakEditor: EditorModel?
    weak var weakHandle: CanvasHandle?
    weak var weakCanvas: CanvasView?
    autoreleasepool {
      let document = SkitchoDocument(initial: Document.blank(size: CGSize(width: 200, height: 150)))
      weakEditor = document.editor
      weakHandle = document.canvasHandle
      let window = makeWindow()
      window.contentView = NSHostingView(rootView: EditorWindowView(document: document))
      window.orderFront(nil)
      spin()
      weakCanvas = document.canvasHandle.canvas
      #expect(weakCanvas != nil)
      window.orderOut(nil)
      window.contentView = nil
      window.close()
    }
    spin()
    #expect(weakEditor == nil)
    #expect(weakHandle == nil)
    #expect(weakCanvas == nil)
  }
}
