import SwiftUI

/// The pixelate options: block-size slider plus Apply/Cancel, driven by a `PixelateToolController`.
struct PixelateBar: View {
  let blockSize: Int
  let canApply: Bool
  /// Failure of the last Apply, shown under the bar.
  var errorMessage: String? = nil
  let onBlockSize: (Int) -> Void
  let onApply: () -> Void
  let onCancel: () -> Void

  private static let range =
    Double(
      PixelateToolController.blockSizeRange.lowerBound)...Double(
      PixelateToolController.blockSizeRange.upperBound)

  var body: some View {
    VStack(alignment: .trailing, spacing: Spacing.xxs) {
      bar
      if let errorMessage {
        Text(errorMessage)
          .font(Typography.caption.font())
          .foregroundStyle(BrandColor.red.color)
      }
    }
  }

  private var bar: some View {
    ApplyCancelBar(canApply: canApply, onApply: onApply, onCancel: onCancel) {
      HStack(spacing: Spacing.xs) {
        Text("Block size")
          .font(Typography.caption.font())
          .foregroundStyle(BrandColor.darkBlue.color)
        Slider(
          value: Binding(get: { Double(blockSize) }, set: { onBlockSize(Int($0.rounded())) }),
          in: Self.range
        )
        .frame(width: 140)
        Text("\(blockSize) px")
          .font(Typography.caption.font())
          .foregroundStyle(BrandColor.mediumGray.color)
          .frame(width: 44, alignment: .trailing)
      }
    }
  }
}
