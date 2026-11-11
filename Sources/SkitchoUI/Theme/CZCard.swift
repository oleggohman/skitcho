import SwiftUI

/// CloudZone card: 2 pt ghostGray border, radius 20, padding 32 (24 in compact panels).
public struct CZCard<Content: View>: View {
  public static var borderWidth: CGFloat { 2 }
  public static func padding(compact: Bool) -> CGFloat { compact ? Spacing.md : Spacing.lg }

  private let title: String?
  private let compact: Bool
  private let content: Content

  public init(title: String? = nil, compact: Bool = false, @ViewBuilder content: () -> Content) {
    self.title = title
    self.compact = compact
    self.content = content()
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      if let title {
        Text(title)
          .font(Typography.title.font(weight: .semibold))
          .foregroundStyle(BrandSemantic.text.color)
      }
      content
        .font(Typography.bodySmall.font())
        .foregroundStyle(BrandSemantic.text.color)
    }
    .padding(Self.padding(compact: compact))
    .background(
      RoundedRectangle(cornerRadius: Radius.large, style: .continuous).fill(BrandSemantic.panel.color)
    )
    .overlay(
      RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
        .strokeBorder(BrandSemantic.panelBorder.color, lineWidth: Self.borderWidth)
    )
  }
}
