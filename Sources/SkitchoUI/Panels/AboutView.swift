import SwiftUI

/// The About window: product name, version and license.
public struct AboutView: View {
  public static let title = "Skitcho — by CloudZone"
  public static let license = "MIT License"
  public static let windowID = "about"

  /// "Version 1.2 (34)" from the bundle's Info.plist; "Development build" outside a bundle.
  public static func versionText(bundle: Bundle = .main) -> String { versionText(info: bundle.infoDictionary) }

  static func versionText(info: [String: Any]?) -> String {
    guard let short = info?["CFBundleShortVersionString"] as? String else { return "Development build" }
    if let build = info?["CFBundleVersion"] as? String, build != short { return "Version \(short) (\(build))" }
    return "Version \(short)"
  }

  private let bundle: Bundle

  public init(bundle: Bundle = .main) {
    self.bundle = bundle
  }

  public var body: some View {
    VStack(spacing: Spacing.xs) {
      Text(Self.title)
        .font(Typography.title.font(weight: .semibold))
        .foregroundStyle(BrandSemantic.text.color)
      Text(Self.versionText(bundle: bundle))
        .font(Typography.bodySmall.font())
        .foregroundStyle(BrandSemantic.caption.color)
      Text(Self.license)
        .font(Typography.caption.font())
        .foregroundStyle(BrandSemantic.caption.color)
    }
    .padding(Spacing.lg)
    .frame(minWidth: 320)
    .background(BrandSemantic.windowBackground.color)
  }
}
