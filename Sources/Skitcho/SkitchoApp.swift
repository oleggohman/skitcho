import SkitchoCore
import SkitchoUI
import SwiftUI

@main
struct SkitchoApp: App {
  var body: some Scene {
    DocumentGroup(
      newDocument: { SkitchoDocument() },
      editor: { file in PlaceholderDocumentView(document: file.document) })
  }
}

/// Spike view: shows the base image until the real editor window lands.
struct PlaceholderDocumentView: View {
  let document: SkitchoDocument

  var body: some View {
    Image(decorative: document.editor.document.baseImage, scale: 1)
      .resizable()
      .scaledToFit()
      .frame(minWidth: 320, minHeight: 240)
  }
}
