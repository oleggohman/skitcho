import AppKit
import SwiftUI

/// CloudZone type scale mapped onto the system font (SF Pro). No font files are bundled or registered.
public enum Typography: CaseIterable, Sendable {
  case label, caption, bodySmall, input, body, title, largeTitle

  /// Point size of the token.
  public var size: CGFloat {
    switch self {
    case .label: 10
    case .caption: 12
    case .bodySmall: 14
    case .input: 15
    case .body: 16
    case .title: 20
    case .largeTitle: 40
    }
  }

  /// CloudZone weights 400/500/600.
  public enum Weight: Int, CaseIterable, Sendable {
    case regular = 400
    case medium = 500
    case semibold = 600

    public var fontWeight: Font.Weight {
      switch self {
      case .regular: .regular
      case .medium: .medium
      case .semibold: .semibold
      }
    }

    public var nsWeight: NSFont.Weight {
      switch self {
      case .regular: .regular
      case .medium: .medium
      case .semibold: .semibold
      }
    }
  }

  /// Body text defaults to medium.
  public var defaultWeight: Weight { .medium }

  public func font(weight: Weight? = nil) -> Font {
    .system(size: size, weight: (weight ?? defaultWeight).fontWeight)
  }

  public func nsFont(weight: Weight? = nil) -> NSFont {
    .systemFont(ofSize: size, weight: (weight ?? defaultWeight).nsWeight)
  }
}
