import SkitchoCore
import SkitchoUI
import SwiftUI

/// The SwiftUI app. The process entry point is `Entry`, which handles `--self-test` before this starts.
struct SkitchoApp: App {
  @State private var updater = UpdaterController()

  var body: some Scene {
    DocumentGroup(
      newDocument: { SkitchoDocument() },
      editor: { file in EditorWindowView(document: file.document) }
    )
    .commands { SkitchoCommands(updater: updater) }

    Window("About Skitcho", id: AboutView.windowID) {
      AboutView()
    }
    .windowResizability(.contentSize)

    Settings {
      SettingsView(
        autoCheck: Binding(
          get: { updater.automaticallyChecksForUpdates },
          set: { updater.automaticallyChecksForUpdates = $0 }),
        updatesEnabled: updater.isEnabled)
    }
  }
}
