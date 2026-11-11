import SwiftUI

/// CloudZone button: variants x sizes, hover and disabled states.
public struct CZButtonStyle: ButtonStyle {
  public enum Variant: CaseIterable, Sendable {
    case primary, secondary, transparent, link
  }

  public enum Size: CaseIterable, Sendable {
    case small, normal

    public var minHeight: CGFloat {
      switch self {
      case .small: 24
      case .normal: 38
      }
    }

    public var cornerRadius: CGFloat {
      switch self {
      case .small: Radius.medium
      case .normal: Radius.pill
      }
    }

    public var horizontalPadding: CGFloat {
      switch self {
      case .small: Spacing.xs
      case .normal: Spacing.md
      }
    }

    public var typography: Typography {
      switch self {
      case .small: .caption
      case .normal: .bodySmall
      }
    }
  }

  public let variant: Variant
  public let size: Size

  public init(_ variant: Variant = .primary, size: Size = .normal) {
    self.variant = variant
    self.size = size
  }

  /// Background token for a state; nil means no background.
  public static func background(_ variant: Variant, hovering: Bool, enabled: Bool) -> BrandColor? {
    switch variant {
    case .transparent, .link: return nil
    case .primary: return enabled ? (hovering ? .purple : .blue) : .mutedGray
    case .secondary: return enabled ? (hovering ? .lightBlue : .paleBlue) : .mutedGray
    }
  }

  /// Foreground token for a state.
  public static func foreground(_ variant: Variant, hovering: Bool, enabled: Bool) -> BrandColor {
    guard enabled else { return variant == .transparent || variant == .link ? .lightGray : .mediumGray }
    switch variant {
    case .primary: return .white
    case .secondary, .transparent: return .darkBlue
    case .link: return .purple
    }
  }

  public func makeBody(configuration: Configuration) -> some View {
    CZButtonBody(variant: variant, size: size, configuration: configuration)
  }
}

private struct CZButtonBody: View {
  let variant: CZButtonStyle.Variant
  let size: CZButtonStyle.Size
  let configuration: ButtonStyleConfiguration

  @Environment(\.isEnabled) private var isEnabled
  @State private var hovering = false

  var body: some View {
    let background = CZButtonStyle.background(variant, hovering: hovering, enabled: isEnabled)
    let foreground = CZButtonStyle.foreground(variant, hovering: hovering, enabled: isEnabled)
    // Transparent buttons have no hover color, so they fall back to reduced opacity.
    let fadeOnHover = variant == .transparent && hovering && isEnabled
    configuration.label
      .font(size.typography.font(weight: .semibold))
      .underline(variant == .link && hovering && isEnabled)
      .foregroundStyle(foreground.color)
      .padding(.horizontal, size.horizontalPadding)
      .frame(minHeight: size.minHeight)
      .background {
        if let background {
          RoundedRectangle(cornerRadius: size.cornerRadius, style: .continuous).fill(background.color)
        }
      }
      .opacity(fadeOnHover ? Motion.hoverFallbackOpacity : (configuration.isPressed ? 0.9 : 1))
      .contentShape(RoundedRectangle(cornerRadius: size.cornerRadius, style: .continuous))
      .onHover { hovering = $0 }
      .animation(Motion.animation(Motion.quick), value: hovering)
  }
}
