import Foundation
import Observation
import Sparkle

/// Wraps `SPUStandardUpdaterController`. Dev builds (empty `SUPublicEDKey`) never start the updater, because
/// Sparkle rejects unsigned feeds; the menu item stays disabled instead.
@MainActor
@Observable
final class UpdaterController {
  static let feedURL = "https://github.com/oleggohman/skitcho/releases/latest/download/appcast.xml"
  static let disabledHelp = "Updates are disabled in development builds"
  /// Sparkle's own defaults key for the automatic-check switch.
  static let automaticChecksKey = "SUEnableAutomaticChecks"

  /// True when a public EdDSA key is present and the updater was started.
  let isEnabled: Bool
  private(set) var canCheckForUpdates = false

  @ObservationIgnored private let controller: SPUStandardUpdaterController
  @ObservationIgnored private var observation: NSKeyValueObservation?

  init(publicKey: String? = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String) {
    let key = publicKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    isEnabled = !key.isEmpty
    controller = SPUStandardUpdaterController(
      startingUpdater: isEnabled, updaterDelegate: nil, userDriverDelegate: nil)
    guard isEnabled else { return }
    canCheckForUpdates = controller.updater.canCheckForUpdates
    observation = controller.updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] _, change in
      let value = change.newValue ?? false
      Task { @MainActor in self?.canCheckForUpdates = value }
    }
  }

  /// "Automatically check for updates"; Sparkle persists it under `SUEnableAutomaticChecks`.
  var automaticallyChecksForUpdates: Bool {
    get { controller.updater.automaticallyChecksForUpdates }
    set {
      controller.updater.automaticallyChecksForUpdates = newValue
      UserDefaults.standard.set(newValue, forKey: Self.automaticChecksKey)
    }
  }

  func checkForUpdates() {
    guard isEnabled else { return }
    controller.checkForUpdates(nil)
  }
}
