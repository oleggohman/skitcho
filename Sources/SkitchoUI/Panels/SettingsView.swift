import SwiftUI

/// The Settings window: a single switch for automatic update checks (the interval is the Info.plist daily default).
public struct SettingsView: View {
  public static let toggleTitle = "Automatically check for updates"
  public static let disabledHelp = "Updates are disabled in development builds"

  private let autoCheck: Binding<Bool>
  private let updatesEnabled: Bool

  public init(autoCheck: Binding<Bool>, updatesEnabled: Bool) {
    self.autoCheck = autoCheck
    self.updatesEnabled = updatesEnabled
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      Toggle(Self.toggleTitle, isOn: autoCheck)
        .font(Typography.body.font())
        .foregroundStyle(BrandSemantic.text.color)
        .disabled(!updatesEnabled)
      if !updatesEnabled {
        Text(Self.disabledHelp)
          .font(Typography.caption.font())
          .foregroundStyle(BrandSemantic.caption.color)
      }
    }
    .padding(Spacing.md)
    .frame(minWidth: 360, alignment: .leading)
    .background(BrandSemantic.windowBackground.color)
  }
}
