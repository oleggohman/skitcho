import Foundation
import Testing

@testable import Skitcho

@MainActor
struct UpdaterTests {
  @Test func emptyKeyDisablesUpdater() {
    #expect(UpdaterController(publicKey: "").isEnabled == false)
    #expect(UpdaterController(publicKey: "  \n").isEnabled == false)
    #expect(UpdaterController(publicKey: nil).isEnabled == false)
  }

  @Test func devBuildCannotCheckForUpdates() {
    let updater = UpdaterController(publicKey: "")
    #expect(updater.canCheckForUpdates == false)
    updater.checkForUpdates()  // must be a no-op, not a crash or a Sparkle error dialog
    #expect(UpdaterController.disabledHelp == "Updates are disabled in development builds")
  }

  @Test func feedURLConstant() {
    #expect(
      UpdaterController.feedURL
        == "https://github.com/oleggohman/skitcho/releases/latest/download/appcast.xml")
  }

  @Test func automaticCheckTogglePersistsToSparkleDefault() {
    let defaults = UserDefaults.standard
    let key = UpdaterController.automaticChecksKey
    let saved = defaults.object(forKey: key)
    defer {
      if let saved { defaults.set(saved, forKey: key) } else { defaults.removeObject(forKey: key) }
    }
    let updater = UpdaterController(publicKey: "")
    updater.automaticallyChecksForUpdates = true
    #expect(defaults.bool(forKey: key) == true)
    updater.automaticallyChecksForUpdates = false
    #expect(defaults.bool(forKey: key) == false)
    #expect(updater.automaticallyChecksForUpdates == false)
  }
}
