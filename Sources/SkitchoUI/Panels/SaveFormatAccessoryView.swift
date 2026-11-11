import AppKit
import UniformTypeIdentifiers

/// The "Format" popup shown in the Save panel: JPEG (default) or Skitcho (editable). Choosing a format limits the
/// panel to that type and swaps the extension in the file name field.
@MainActor
public final class SaveFormatAccessoryView: NSView {
  /// Popup titles, in `SaveFormat.allCases` order.
  public static func title(for format: SaveFormat) -> String {
    switch format {
    case .jpeg: "JPEG"
    case .skitcho: "Skitcho (editable)"
    }
  }

  private weak var panel: NSSavePanel?
  public let popup = NSPopUpButton(frame: .zero, pullsDown: false)
  private let label = NSTextField(labelWithString: "Format:")

  /// The format currently chosen in the popup.
  public private(set) var selectedFormat: SaveFormat

  public init(panel: NSSavePanel, initial: SaveFormat = .jpeg) {
    self.panel = panel
    self.selectedFormat = initial
    super.init(frame: .zero)

    label.font = Typography.caption.nsFont()
    label.textColor = BrandSemantic.caption.nsColor
    popup.font = Typography.caption.nsFont()
    popup.addItems(withTitles: SaveFormat.allCases.map(Self.title(for:)))
    popup.target = self
    popup.action = #selector(formatChanged(_:))

    let stack = NSStackView(views: [label, popup])
    stack.orientation = .horizontal
    stack.spacing = Spacing.xs
    stack.edgeInsets = NSEdgeInsets(top: Spacing.xs, left: Spacing.sm, bottom: Spacing.xs, right: Spacing.sm)
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor),
      stack.topAnchor.constraint(equalTo: topAnchor),
      stack.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
    frame.size = stack.fittingSize
    select(initial)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  /// Selects `format` in the popup and applies it to the panel.
  public func select(_ format: SaveFormat) {
    selectedFormat = format
    popup.selectItem(at: SaveFormat.allCases.firstIndex(of: format) ?? 0)
    apply(format)
  }

  @objc private func formatChanged(_ sender: NSPopUpButton) {
    let index = sender.indexOfSelectedItem
    guard SaveFormat.allCases.indices.contains(index) else { return }
    select(SaveFormat.allCases[index])
  }

  /// Restricts the panel to the format's type and replaces the extension of the typed name.
  private func apply(_ format: SaveFormat) {
    guard let panel else { return }
    panel.allowedContentTypes = [format.contentType]
    panel.nameFieldStringValue = Self.name(panel.nameFieldStringValue, in: format)
  }

  /// `name` with the extension of `format`. Only the extensions this popup knows are replaced, so a name such as
  /// "v1.2" keeps its dot.
  static func name(_ name: String, in format: SaveFormat) -> String {
    let known = Set(SaveFormat.allCases.map(\.fileExtension) + ["jpeg"])
    let ext = (name as NSString).pathExtension
    let base = known.contains(ext.lowercased()) ? (name as NSString).deletingPathExtension : name
    return base + "." + format.fileExtension
  }
}
