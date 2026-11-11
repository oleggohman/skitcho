import AppKit
import Sparkle

/// Process entry point. `--self-test` runs before SwiftUI starts: it loads Sparkle (proving the embedded
/// framework resolves through the `@executable_path/../Frameworks` rpath), prints `ok` and exits.
@main
enum Entry {
  static let selfTestFlag = "--self-test"

  @MainActor
  static func main() {
    if CommandLine.arguments.contains(selfTestFlag) {
      guard !NSStringFromClass(SPUUpdater.self).isEmpty else { exit(1) }
      print("ok")
      return
    }
    SkitchoApp.main()
  }
}
