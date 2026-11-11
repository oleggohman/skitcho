import SkitchoCore
import SwiftUI

/// The crop options: W×H fields, expand-canvas edge buttons (+64 px each) and Apply/Cancel, driven by a
/// `CropToolController`.
struct CropBar: View {
  let width: Int
  let height: Int
  let canApply: Bool
  let errorMessage: String?
  let onWidth: (Int) -> Void
  let onHeight: (Int) -> Void
  let onExpand: (CanvasEdge) -> Void
  let onApply: () -> Void
  let onCancel: () -> Void

  private static let edges: [(edge: CanvasEdge, symbol: String, label: String)] = [
    (.top, "arrow.up.to.line", "Add space above"),
    (.left, "arrow.left.to.line", "Add space on the left"),
    (.bottom, "arrow.down.to.line", "Add space below"),
    (.right, "arrow.right.to.line", "Add space on the right"),
  ]

  var body: some View {
    VStack(alignment: .trailing, spacing: Spacing.xxs) {
      ApplyCancelBar(applyTitle: "Crop", canApply: canApply, onApply: onApply, onCancel: onCancel) {
        HStack(spacing: Spacing.xs) {
          field("W", value: width, action: onWidth)
          field("H", value: height, action: onHeight)
          Text("Expand +\(CropToolController.expandAmount)")
            .font(Typography.caption.font())
            .foregroundStyle(BrandColor.mediumGray.color)
          ForEach(Self.edges, id: \.edge) { item in
            Button {
              onExpand(item.edge)
            } label: {
              Image(systemName: item.symbol)
            }
            .buttonStyle(CZButtonStyle(.secondary, size: .small))
            .help(item.label)
            .accessibilityLabel(item.label)
          }
        }
      }
      if let errorMessage {
        Text(errorMessage)
          .font(Typography.caption.font())
          .foregroundStyle(BrandColor.red.color)
      }
    }
  }

  private func field(_ title: String, value: Int, action: @escaping (Int) -> Void) -> some View {
    HStack(spacing: Spacing.xxs) {
      Text(title)
        .font(Typography.caption.font())
        .foregroundStyle(BrandColor.darkBlue.color)
      TextField(
        title, value: Binding(get: { value }, set: { action($0) }),
        format: .number.grouping(.never)
      )
      .textFieldStyle(.roundedBorder)
      .frame(width: 64)
      .accessibilityLabel(title == "W" ? "Width" : "Height")
    }
  }
}
