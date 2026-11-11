import AppKit
import SkitchoCore
import SkitchoUI
import SwiftUI

/// The menu bar. Commands act on the key window's editor through the `editorCommands` focused value; the
/// enablement rules live in `EditorCommandModel`. Undo/Redo, New, Open and Save come from `DocumentGroup`.
struct SkitchoCommands: Commands {
  @FocusedValue(\.editorCommands) private var editor
  @Environment(\.newDocument) private var newDocument
  @Environment(\.openWindow) private var openWindow

  var body: some Commands {
    CommandGroup(replacing: .appInfo) {
      Button("About Skitcho") { openWindow(id: AboutView.windowID) }
    }

    CommandGroup(after: .newItem) {
      Button("New from Clipboard") { newFromClipboard() }
        .keyboardShortcut("n", modifiers: [.command, .option])
    }

    CommandGroup(after: .saveItem) {
      item("Export As…", .exportAs).keyboardShortcut("e", modifiers: [.command, .shift])
      item("Copy Image", .copyImage).keyboardShortcut("c", modifiers: [.command, .shift])
    }

    CommandGroup(replacing: .pasteboard) {
      item("Cut", .cut).keyboardShortcut("x")
      item("Copy", .copy).keyboardShortcut("c")
      item("Paste", .paste).keyboardShortcut("v")
      // Backspace is left to the canvas: a menu key equivalent would steal it from text editing.
      item("Delete", .delete)
      Divider()
      item("Select All", .selectAll).keyboardShortcut("a")
    }

    CommandMenu("Arrange") {
      item("Bring Forward", .bringForward).keyboardShortcut("]")
      item("Send Backward", .sendBackward).keyboardShortcut("[")
    }

    CommandMenu("Image") {
      item("Crop", .cropTool)
      item("Resize…", .resize)
      Divider()
      item("Rotate Left", .rotateLeft)
      item("Rotate Right", .rotateRight)
      item("Flip Horizontal", .flipHorizontal)
      item("Flip Vertical", .flipVertical)
      Divider()
      Menu("Expand Canvas") {
        ForEach(CanvasEdge.allCases, id: \.self) { edge in
          Button("\(Self.name(of: edge)) (+\(EditorCommandModel.expandAmount) px)") {
            editor?.expandCanvas(edge)
          }
        }
      }
      .disabled(!(editor?.isEnabled(.expandCanvas) ?? false))
    }

    CommandGroup(after: .toolbar) {
      item("Zoom In", .zoomIn).keyboardShortcut("+")
      item("Zoom Out", .zoomOut).keyboardShortcut("-")
      item("Actual Size", .actualSize).keyboardShortcut("0")
      item("Zoom to Fit", .zoomToFit).keyboardShortcut("9")
    }

    // Tool shortcuts are single letters that the canvas handles itself (they must not fire while text is
    // typed), so the menu shows them in the title and has no key equivalents.
    CommandMenu("Tools") {
      ForEach(Tool.allCases, id: \.self) { tool in
        Toggle(
          tool.titleWithShortcut,
          isOn: Binding(
            get: { editor?.currentTool == tool },
            set: { if $0 { editor?.selectTool(tool) } }))
      }
    }
  }

  private func item(_ title: String, _ command: EditorCommandModel.Command) -> some View {
    Button(title) { editor?.perform(command) }
      .disabled(!(editor?.isEnabled(command) ?? false))
  }

  private static func name(of edge: CanvasEdge) -> String {
    switch edge {
    case .top: "Top"
    case .left: "Left"
    case .bottom: "Bottom"
    case .right: "Right"
    }
  }

  private func newFromClipboard() {
    do {
      let document = try PasteboardBridge().readDocument()
      PendingDocument.set(document)
      newDocument(contentType: .skitchoDocument)
    } catch {
      NSSound.beep()
    }
  }
}
