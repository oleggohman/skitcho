import SwiftUI

/// A floating confirmation bar: optional options content on the left, Cancel (secondary) and Apply (primary)
/// on the right. Generic so pixelate, crop and resize can share it; the caller supplies the options and the
/// button titles. Keyboard (Return/Esc) is handled by the active tool controller, not here, because the
/// canvas keeps the first responder.
public struct ApplyCancelBar<Content: View>: View {
  public let applyTitle: String
  public let cancelTitle: String
  public let canApply: Bool
  public let onApply: () -> Void
  public let onCancel: () -> Void
  private let content: Content

  public init(
    applyTitle: String = "Apply",
    cancelTitle: String = "Cancel",
    canApply: Bool = true,
    onApply: @escaping () -> Void,
    onCancel: @escaping () -> Void,
    @ViewBuilder content: () -> Content
  ) {
    self.applyTitle = applyTitle
    self.cancelTitle = cancelTitle
    self.canApply = canApply
    self.onApply = onApply
    self.onCancel = onCancel
    self.content = content()
  }

  public var body: some View {
    HStack(spacing: Spacing.sm) {
      content
      Button(cancelTitle, action: onCancel)
        .buttonStyle(CZButtonStyle(.secondary, size: .small))
      Button(applyTitle, action: onApply)
        .buttonStyle(CZButtonStyle(.primary, size: .small))
        .disabled(!canApply)
    }
    .padding(.horizontal, Spacing.sm)
    .padding(.vertical, Spacing.xs)
    .background {
      RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
        .fill(BrandColor.white.color)
        .shadow(color: BrandColor.black.color.opacity(0.18), radius: 8, y: 2)
    }
  }
}

extension ApplyCancelBar where Content == EmptyView {
  public init(
    applyTitle: String = "Apply",
    cancelTitle: String = "Cancel",
    canApply: Bool = true,
    onApply: @escaping () -> Void,
    onCancel: @escaping () -> Void
  ) {
    self.init(
      applyTitle: applyTitle, cancelTitle: cancelTitle, canApply: canApply, onApply: onApply,
      onCancel: onCancel
    ) { EmptyView() }
  }
}
