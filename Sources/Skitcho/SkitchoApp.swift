import SkitchoCore
import SkitchoUI
import SwiftUI

@main
struct SkitchoApp: App {
  var body: some Scene {
    DocumentGroup(
      newDocument: { SkitchoDocument() },
      editor: { file in EditorWindowView(document: file.document) }
    )
    .commands { SkitchoCommands() }

    Window("About Skitcho", id: AboutView.windowID) {
      AboutView()
    }
    .windowResizability(.contentSize)
  }
}
