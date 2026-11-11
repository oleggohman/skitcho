import AppKit
import SkitchoCore
import SwiftUI

/// View-model of the properties panel (right side). It reads the style of the selection, or of the next
/// element when nothing is selected, and forwards changes to the editor's style commands.
@MainActor @Observable
public final class PropertiesModel {
  private let editor: EditorModel
  /// Starts the label editor on a stamp (wired to the canvas by the shell).
  private let attachLabelAction: (UUID) -> Bool

  public init(editor: EditorModel, attachLabel: @escaping (UUID) -> Bool = { _ in false }) {
    self.editor = editor
    self.attachLabelAction = attachLabel
  }

  // MARK: Context

  /// Style families the panel currently edits: those of the selection, else of the current tool.
  private var contextTools: [StyleTool] {
    if editor.selection.isEmpty { return editor.currentTool.styleTool.map { [$0] } ?? [] }
    return editor.selectedElements.map { EditorModel.styleTool(of: $0) }
  }

  /// Colors and sizes apply to anything styled.
  public var showsStyle: Bool { !contextTools.isEmpty }
  public var showsTextStyle: Bool { contextTools.contains(.text) }
  public var showsDoubleHead: Bool { contextTools.contains(.arrow) }

  /// True when exactly one stamp without a label is selected.
  public var canAttachLabel: Bool { attachLabelTarget != nil }

  private var attachLabelTarget: UUID? {
    guard editor.selection.count == 1, let element = editor.selectedElements.first,
      case .stamp(_, _, _, let label) = element.kind, label == nil
    else { return nil }
    return element.id
  }

  /// Hint shown instead of controls while nothing styled is in context.
  public static let emptyHint = "Select an element or pick a drawing tool to edit its style."

  // MARK: Values

  /// The color shown as selected (the first selected element's, else the next element's).
  public var currentColor: AnnotationColor {
    if let first = editor.selectedElements.first { return first.style.color }
    if let next = editor.nextColor { return next }
    return editor.currentTool.styleTool.map(Style.defaultColor(for:)) ?? .red
  }

  public var currentSizeStep: SizeStep {
    editor.selectedElements.first?.style.sizeStep ?? editor.nextSizeStep
  }

  public var isTextStyled: Bool {
    let styled = editor.selectedElements.compactMap { element -> Bool? in
      if case .text(let content) = element.kind { return content.styled }
      return nil
    }
    return styled.isEmpty ? editor.nextTextStyled : styled.allSatisfy { $0 }
  }

  public var isDoubleHeaded: Bool {
    let heads = editor.selectedElements.compactMap { element -> Bool? in
      if case .arrow(_, _, let double) = element.kind { return double }
      return nil
    }
    return heads.isEmpty ? editor.nextDoubleHeaded : heads.allSatisfy { $0 }
  }

  // MARK: Commands

  public func setColor(_ color: AnnotationColor) {
    finishCustomColor()
    editor.applyColor(color)
  }

  /// How long a custom color stays quiet before its continuous change is committed as one undo step.
  public var colorCommitDelay: Duration = .milliseconds(400)
  /// True while a continuous custom color change is open (one undo step is pending).
  public private(set) var isColorSessionActive = false
  private var colorCommit: Task<Void, Never>?

  /// Applies a color chosen in the system color picker as a custom annotation color. Changes that follow each
  /// other (dragging in the picker) are previewed live and coalesced into one "Change Color" undo step, which
  /// is committed after `colorCommitDelay` of quiet or by `finishCustomColor()`.
  public func setCustomColor(_ color: Color) {
    guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return }
    let custom = AnnotationColor.custom(
      RGBA(
        red: Double(srgb.redComponent), green: Double(srgb.greenComponent), blue: Double(srgb.blueComponent),
        alpha: Double(srgb.alphaComponent)))
    if !isColorSessionActive {
      // Another gesture owns the interactive slot: fall back to a plain one-step change.
      guard !editor.isInteracting else {
        editor.applyColor(custom)
        return
      }
      editor.beginInteractive()
      isColorSessionActive = true
    }
    editor.applyColorLive(custom)
    colorCommit?.cancel()
    let delay = colorCommitDelay
    colorCommit = Task { [weak self] in
      try? await Task.sleep(for: delay)
      guard !Task.isCancelled else { return }
      self?.finishCustomColor()
    }
  }

  /// Ends the open custom color change (if any) and registers its single undo step.
  public func finishCustomColor() {
    colorCommit?.cancel()
    colorCommit = nil
    guard isColorSessionActive else { return }
    isColorSessionActive = false
    editor.commitInteractive(name: "Change Color")
  }

  public func setSize(_ step: SizeStep) {
    finishCustomColor()
    editor.applySizeStep(step)
  }
  public func toggleTextStyle() {
    finishCustomColor()
    editor.toggleTextStyle()
  }
  public func toggleDoubleHead() {
    finishCustomColor()
    editor.toggleDoubleHead()
  }

  /// Starts a label on the selected stamp. Returns false when the panel does not offer it.
  @discardableResult
  public func attachLabel() -> Bool {
    guard let id = attachLabelTarget else { return false }
    return attachLabelAction(id)
  }
}

/// Human-readable color names for accessibility.
extension AnnotationColor {
  var title: String {
    switch self {
    case .red: "Red"
    case .orange: "Orange"
    case .blue: "Blue"
    case .purple: "Purple"
    case .lavender: "Lavender"
    case .navy: "Navy"
    case .black: "Black"
    case .white: "White"
    case .yellow: "Yellow"
    case .green: "Green"
    case .custom: "Custom color"
    }
  }
}

/// The right-hand panel: color swatches + custom picker, five size dots, text and arrow toggles, Attach Label.
public struct PropertiesPanel: View {
  let model: PropertiesModel

  public init(model: PropertiesModel) {
    self.model = model
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      if model.showsStyle {
        colorSection
        sizeSection
        if model.showsTextStyle { textToggle }
        if model.showsDoubleHead { arrowToggle }
      } else {
        Text(PropertiesModel.emptyHint)
          .font(Typography.caption.font())
          .foregroundStyle(BrandSemantic.caption.color)
      }
      if model.canAttachLabel {
        Button("Attach Label") { model.attachLabel() }
          .buttonStyle(CZButtonStyle(.secondary, size: .small))
          .help("Add a text label next to the selected stamp")
          .accessibilityLabel("Attach Label")
      }
      Spacer(minLength: 0)
    }
    .padding(Spacing.xs)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(BrandSemantic.panel.color)
    .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
        .strokeBorder(BrandSemantic.panelBorder.color, lineWidth: 1)
    }
  }

  private func caption(_ text: String) -> some View {
    Text(text)
      .font(Typography.caption.font(weight: .semibold))
      .foregroundStyle(BrandSemantic.caption.color)
  }

  private var colorSection: some View {
    VStack(alignment: .leading, spacing: Spacing.xxs) {
      caption("Color")
      LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: Spacing.xxs), count: 5), spacing: Spacing.xxs) {
        ForEach(AnnotationColor.presets, id: \.self) { color in
          swatch(color)
        }
      }
      ColorPicker(
        "Custom",
        selection: Binding(
          get: { Color(cgColor: model.currentColor.cgColor) },
          set: { model.setCustomColor($0) }),
        supportsOpacity: false
      )
      .font(Typography.caption.font())
      .help("Pick a custom color")
      .accessibilityLabel("Custom color")
    }
  }

  private func swatch(_ color: AnnotationColor) -> some View {
    let selected = model.currentColor == color
    return Button {
      model.setColor(color)
    } label: {
      Circle()
        .fill(Color(cgColor: color.cgColor))
        .frame(width: 20, height: 20)
        .overlay(Circle().strokeBorder(BrandColor.mutedGray.color, lineWidth: 1))
        .padding(3)
        .overlay {
          if selected { Circle().strokeBorder(BrandSemantic.selectedTool.color, lineWidth: 2) }
        }
    }
    .buttonStyle(.plain)
    .help(color.title)
    .accessibilityLabel(color.title)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  private var sizeSection: some View {
    VStack(alignment: .leading, spacing: Spacing.xxs) {
      caption("Size")
      HStack(spacing: Spacing.xxs) {
        ForEach(SizeStep.allCases, id: \.self) { step in
          sizeDot(step)
        }
      }
    }
  }

  private func sizeDot(_ step: SizeStep) -> some View {
    let selected = model.currentSizeStep == step
    let diameter = 6 + CGFloat(step.rawValue) * 3
    return Button {
      model.setSize(step)
    } label: {
      Circle()
        .fill(selected ? BrandSemantic.selectedTool.color : BrandColor.lightGray.color)
        .frame(width: diameter, height: diameter)
        .frame(width: 28, height: 28)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help("Size \(step.rawValue) of 5")
    .accessibilityLabel("Size \(step.rawValue)")
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  private var textToggle: some View {
    Toggle(
      "Text outline",
      isOn: Binding(get: { model.isTextStyled }, set: { _ in model.toggleTextStyle() })
    )
    .toggleStyle(.switch)
    .controlSize(.small)
    .font(Typography.caption.font())
    .help("Styled text has a contrasting outline; plain text has none")
    .accessibilityLabel("Styled text")
  }

  private var arrowToggle: some View {
    Toggle(
      "Double head",
      isOn: Binding(get: { model.isDoubleHeaded }, set: { _ in model.toggleDoubleHead() })
    )
    .toggleStyle(.switch)
    .controlSize(.small)
    .font(Typography.caption.font())
    .help("Put an arrow head on both ends")
    .accessibilityLabel("Double-headed arrow")
  }
}
