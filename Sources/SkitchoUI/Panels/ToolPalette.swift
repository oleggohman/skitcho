import SkitchoCore
import SwiftUI

/// One button in the tool palette. Group items (shapes, stamps) stand for several tools / kinds that are
/// chosen in a plain popover.
public enum PaletteItem: String, CaseIterable, Sendable, Identifiable {
  case select, arrow, text, marker, highlighter, shapes, stamp, pixelate, crop

  public var id: String { rawValue }

  /// The tools grouped under the Shapes button.
  public static let shapeTools: [Tool] = [.rect, .roundedRect, .ellipse, .line]

  /// Tools the button covers; the button is highlighted while the current tool is one of them.
  public var tools: [Tool] {
    switch self {
    case .select: [.select]
    case .arrow: [.arrow]
    case .text: [.text]
    case .marker: [.marker]
    case .highlighter: [.highlighter]
    case .shapes: Self.shapeTools
    case .stamp: [.stamp]
    case .pixelate: [.pixelate]
    case .crop: [.crop]
    }
  }

  /// True when the button opens a popover with sub-tools.
  public var isGroup: Bool { self == .shapes || self == .stamp }

  public var title: String {
    switch self {
    case .select: "Select"
    case .arrow: "Arrow"
    case .text: "Text"
    case .marker: "Marker"
    case .highlighter: "Highlighter"
    case .shapes: "Shapes"
    case .stamp: "Stamp"
    case .pixelate: "Pixelate"
    case .crop: "Crop"
    }
  }
}

extension Tool {
  /// Name with the single-key shortcut, e.g. "Arrow (A)", for menus and tooltips.
  public var titleWithShortcut: String { "\(title) (\(String(shortcut).uppercased()))" }

  /// Human-readable name for labels and tooltips.
  public var title: String {
    switch self {
    case .select: "Select"
    case .arrow: "Arrow"
    case .text: "Text"
    case .marker: "Marker"
    case .highlighter: "Highlighter"
    case .rect: "Rectangle"
    case .roundedRect: "Rounded Rectangle"
    case .ellipse: "Ellipse"
    case .line: "Line"
    case .stamp: "Stamp"
    case .pixelate: "Pixelate"
    case .crop: "Crop"
    }
  }

  /// SF Symbol of the tool button.
  public var symbolName: String {
    switch self {
    case .select: "cursorarrow"
    case .arrow: "arrow.up.right"
    case .text: "textformat"
    case .marker: "pencil.tip"
    case .highlighter: "highlighter"
    case .rect: "rectangle"
    case .roundedRect: "app"
    case .ellipse: "circle"
    case .line: "line.diagonal"
    case .stamp: "checkmark.seal"
    case .pixelate: "squareshape.split.3x3"
    case .crop: "crop"
    }
  }
}

extension StampKind {
  public var title: String {
    switch self {
    case .approve: "Approve"
    case .reject: "Reject"
    case .question: "Question"
    case .attention: "Attention"
    case .perfect: "Perfect"
    }
  }

  /// SF Symbol shown in the stamp popover (the canvas draws its own geometry).
  public var symbolName: String {
    switch self {
    case .approve: "checkmark.circle.fill"
    case .reject: "xmark.circle.fill"
    case .question: "questionmark.circle.fill"
    case .attention: "exclamationmark.circle.fill"
    case .perfect: "star.circle.fill"
    }
  }
}

/// View-model of the tool palette: maps button taps onto the editor's current tool and next-stamp choice.
@MainActor @Observable
public final class ToolPaletteModel {
  public static let shapeTools = PaletteItem.shapeTools

  private let editor: EditorModel
  /// The shape the Shapes button selects (the last one chosen in the popover).
  public private(set) var lastShape: Tool = .rect

  public init(editor: EditorModel) {
    self.editor = editor
  }

  /// Items in display order.
  public var items: [PaletteItem] { PaletteItem.allCases }

  public func isSelected(_ item: PaletteItem) -> Bool {
    item.tools.contains(editor.currentTool)
  }

  /// The tool a tap on `item` selects.
  public func tool(for item: PaletteItem) -> Tool {
    if item == .shapes { return Self.shapeTools.contains(editor.currentTool) ? editor.currentTool : lastShape }
    return item.tools[0]
  }

  /// Icon of `item`; the Shapes button shows the last chosen shape.
  public func symbolName(for item: PaletteItem) -> String {
    tool(for: item).symbolName
  }

  /// Tooltip with the shortcut key of the button's tool.
  public func help(for item: PaletteItem) -> String {
    let tool = tool(for: item)
    let key = String(tool.shortcut).uppercased()
    let name = item == .shapes ? "Shapes (\(tool.title))" : item.title
    return item.isGroup ? "\(name) (\(key)) - click again for more" : "\(name) (\(key))"
  }

  /// Handles a tap on `item`. Returns true when a group item that is already active was tapped, i.e. the
  /// caller should show its popover.
  @discardableResult
  public func tap(_ item: PaletteItem) -> Bool {
    if item.isGroup, isSelected(item) { return true }
    select(tool(for: item))
    return false
  }

  /// Selects `tool` directly (also used by the shape popover).
  public func select(_ tool: Tool) {
    if Self.shapeTools.contains(tool) { lastShape = tool }
    editor.currentTool = tool
  }

  /// Picks the stamp the stamp tool places next and switches to the stamp tool.
  public func selectStamp(_ kind: StampKind) {
    editor.nextStampKind = kind
    editor.currentTool = .stamp
  }

  public var currentStampKind: StampKind { editor.nextStampKind }
}

/// The left sidebar: SF Symbol tool buttons on `darkBlue`.
public struct ToolPalette: View {
  let model: ToolPaletteModel
  @State private var popover: PaletteItem?

  public init(model: ToolPaletteModel) {
    self.model = model
  }

  public var body: some View {
    VStack(spacing: Spacing.xxs) {
      ForEach(model.items) { item in
        button(for: item)
      }
      Spacer(minLength: 0)
    }
    .padding(.vertical, Spacing.xs)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func button(for item: PaletteItem) -> some View {
    Button {
      if model.tap(item) { popover = item }
    } label: {
      PaletteButtonLabel(
        symbol: model.symbolName(for: item), selected: model.isSelected(item), hasMenu: item.isGroup)
    }
    .buttonStyle(.plain)
    .help(model.help(for: item))
    .accessibilityLabel(item.title)
    .accessibilityAddTraits(model.isSelected(item) ? .isSelected : [])
    .popover(
      isPresented: Binding(get: { popover == item }, set: { if !$0 { popover = nil } }),
      arrowEdge: .trailing
    ) {
      popoverContent(for: item)
    }
  }

  @ViewBuilder
  private func popoverContent(for item: PaletteItem) -> some View {
    HStack(spacing: Spacing.xxs) {
      if item == .shapes {
        ForEach(ToolPaletteModel.shapeTools, id: \.self) { tool in
          choice(symbol: tool.symbolName, title: tool.titleWithShortcut, selected: model.tool(for: .shapes) == tool) {
            model.select(tool)
            popover = nil
          }
        }
      } else {
        ForEach(StampKind.allCases, id: \.self) { kind in
          choice(symbol: kind.symbolName, title: kind.title, selected: model.currentStampKind == kind) {
            model.selectStamp(kind)
            popover = nil
          }
        }
      }
    }
    .padding(Spacing.xs)
  }

  private func choice(symbol: String, title: String, selected: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(Typography.body.font())
        .frame(width: 32, height: 32)
        .foregroundStyle(selected ? BrandColor.white.color : BrandColor.darkBlue.color)
        .background(
          RoundedRectangle(cornerRadius: Radius.tiny, style: .continuous)
            .fill(selected ? BrandSemantic.selectedTool.color : Color.clear))
    }
    .buttonStyle(.plain)
    .help(title)
    .accessibilityLabel(title)
  }
}

/// Icon cell of a palette button: blue when selected, purple on hover, inverted (white) icon on the sidebar.
struct PaletteButtonLabel: View {
  let symbol: String
  let selected: Bool
  let hasMenu: Bool
  @State private var hovering = false

  var body: some View {
    let fill: Color =
      selected ? BrandSemantic.selectedTool.color : (hovering ? BrandSemantic.toolHover.color : .clear)
    Image(systemName: symbol)
      .font(.system(size: 18, weight: .medium))
      .foregroundStyle(BrandSemantic.sidebarIcon.color)
      .frame(width: 40, height: 36)
      .background(RoundedRectangle(cornerRadius: Radius.tiny * 2, style: .continuous).fill(fill))
      .overlay(alignment: .bottomTrailing) {
        if hasMenu {
          Image(systemName: "triangle.fill")
            .font(.system(size: 5))
            .rotationEffect(.degrees(135))
            .foregroundStyle(BrandSemantic.sidebarIcon.color.opacity(0.7))
            .padding(3)
        }
      }
      .contentShape(Rectangle())
      .onHover { hovering = $0 }
      .animation(Motion.animation(Motion.quick), value: hovering)
  }
}
