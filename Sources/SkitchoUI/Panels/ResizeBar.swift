import Foundation
import SkitchoCore
import SwiftUI

/// View-model of the resize panel (resize is not a canvas tool, so the shell presents `ResizeBar` itself).
/// It holds the pending target size, keeps the scale, W and H in sync, and runs the image-op commands on the
/// editor. Nothing touches the document until `apply()`; the rotate/flip actions run immediately.
@MainActor @Observable
public final class ResizeModel {
  /// Scale slider range (1.0 = original size).
  public static let scaleRange = 0.1...4.0

  private let editor: EditorModel
  /// The canvas size the pending size is relative to.
  public private(set) var originalWidth: Int
  public private(set) var originalHeight: Int
  public private(set) var width: Int
  public private(set) var height: Int
  /// When true, editing W or H (or the slider) keeps the aspect ratio; when false only the edited axis changes.
  public var isProportionLinked = true
  /// Message of the last failed command, cleared by the next edit or successful command.
  public private(set) var errorMessage: String?

  /// Called after a successful Apply and after Cancel, so the shell can dismiss the panel.
  public var onDismiss: (() -> Void)?

  public init(editor: EditorModel) {
    self.editor = editor
    let size = Self.pixelSize(of: editor)
    originalWidth = size.width
    originalHeight = size.height
    width = size.width
    height = size.height
  }

  private static func pixelSize(of editor: EditorModel) -> (width: Int, height: Int) {
    let size = editor.document.canvasSize
    return (max(1, Int(size.width.rounded())), max(1, Int(size.height.rounded())))
  }

  /// Re-reads the canvas size (after the document changed) and resets the pending size to it.
  public func reload() {
    let size = Self.pixelSize(of: editor)
    originalWidth = size.width
    originalHeight = size.height
    width = size.width
    height = size.height
    errorMessage = nil
  }

  // MARK: Fields

  /// The pending scale relative to the original width.
  public var scale: Double { Double(width) / Double(originalWidth) }

  /// Sets a uniform scale; W and H follow (the slider acts on both axes).
  public func setScale(_ value: Double) {
    guard value.isFinite, value > 0 else { return }
    errorMessage = nil
    width = max(1, Int((Double(originalWidth) * value).rounded()))
    height = proportionalHeight(forWidth: width)
  }

  public func setWidth(_ value: Int) {
    errorMessage = nil
    width = max(1, value)
    if isProportionLinked { height = proportionalHeight(forWidth: width) }
  }

  public func setHeight(_ value: Int) {
    errorMessage = nil
    height = max(1, value)
    if isProportionLinked {
      width = max(1, Int((Double(height) * Double(originalWidth) / Double(originalHeight)).rounded()))
    }
  }

  private func proportionalHeight(forWidth width: Int) -> Int {
    max(1, Int((Double(width) * Double(originalHeight) / Double(originalWidth)).rounded()))
  }

  // MARK: Guards

  /// The guard message while the pending size exceeds `ImageOps.maxSide`, else nil.
  public var sizeError: String? {
    guard width > ImageOps.maxSide || height > ImageOps.maxSide else { return nil }
    return "The longest side can be at most \(ImageOps.maxSide) px."
  }

  /// True when W×H is the original size scaled uniformly, the only kind of resize the image ops perform.
  public var isUniform: Bool { height == proportionalHeight(forWidth: width) }

  public var canApply: Bool {
    sizeError == nil && isUniform && (width != originalWidth || height != originalHeight)
  }

  /// The text shown under the fields: a failure, the size guard, or a note that unlinked sizes are not uniform.
  public var message: String? {
    if let errorMessage { return errorMessage }
    if let sizeError { return sizeError }
    if !isUniform { return "Resize keeps the aspect ratio; relink the proportions to apply." }
    return nil
  }

  // MARK: Commands

  /// Resizes the image to the pending size (one "Resize Image" undo step). Returns false, leaving the document
  /// untouched, when the size is not applicable or the operation failed (see `message`).
  @discardableResult
  public func apply() -> Bool {
    guard canApply else { return false }
    do {
      try editor.resize(scale: scale)
    } catch {
      errorMessage = Self.text(for: error, action: "resize")
      return false
    }
    reload()
    onDismiss?()
    return true
  }

  /// Discards the pending size.
  public func cancel() {
    reload()
    onDismiss?()
  }

  @discardableResult
  public func rotate(clockwise: Bool) -> Bool {
    run("rotate") { try editor.rotate90(clockwise: clockwise) }
  }

  @discardableResult
  public func flip(_ axis: FlipAxis) -> Bool {
    run("flip") { try editor.flip(axis: axis) }
  }

  private func run(_ action: String, _ command: () throws -> Void) -> Bool {
    do {
      try command()
    } catch {
      errorMessage = Self.text(for: error, action: action)
      return false
    }
    reload()
    return true
  }

  private static func text(for error: Error, action: String) -> String {
    "Could not \(action): \(error.localizedDescription)"
  }
}

/// The resize panel: scale slider, W×H fields, proportion link, rotate/flip buttons and Apply/Cancel.
public struct ResizeBar: View {
  @Bindable var model: ResizeModel

  public init(model: ResizeModel) { self.model = model }

  public var body: some View {
    VStack(alignment: .trailing, spacing: Spacing.xxs) {
      ApplyCancelBar(
        applyTitle: "Resize", canApply: model.canApply, onApply: { model.apply() },
        onCancel: { model.cancel() }
      ) {
        HStack(spacing: Spacing.xs) {
          Slider(
            value: Binding(get: { model.scale }, set: { model.setScale($0) }),
            in: ResizeModel.scaleRange
          )
          .frame(width: 120)
          .accessibilityLabel("Scale")
          Text("\(Int((model.scale * 100).rounded()))%")
            .font(Typography.caption.font())
            .foregroundStyle(BrandColor.mediumGray.color)
            .frame(width: 40, alignment: .trailing)
          field("W", value: model.width) { model.setWidth($0) }
          Toggle(isOn: $model.isProportionLinked) {
            Image(systemName: model.isProportionLinked ? "link" : "link.badge.plus")
          }
          .toggleStyle(.button)
          .help("Keep proportions")
          .accessibilityLabel("Keep proportions")
          field("H", value: model.height) { model.setHeight($0) }
          transformButtons
        }
      }
      if let message = model.message {
        Text(message)
          .font(Typography.caption.font())
          .foregroundStyle(BrandColor.red.color)
      }
    }
  }

  private var transformButtons: some View {
    HStack(spacing: Spacing.xxs) {
      iconButton("rotate.left", "Rotate left") { model.rotate(clockwise: false) }
      iconButton("rotate.right", "Rotate right") { model.rotate(clockwise: true) }
      iconButton("arrow.left.and.right.righttriangle.left.righttriangle.right", "Flip horizontally") {
        model.flip(.horizontal)
      }
      iconButton("arrow.up.and.down.righttriangle.up.righttriangle.down", "Flip vertically") {
        model.flip(.vertical)
      }
    }
  }

  private func iconButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
    Button(action: action) { Image(systemName: symbol) }
      .buttonStyle(CZButtonStyle(.secondary, size: .small))
      .help(label)
      .accessibilityLabel(label)
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
