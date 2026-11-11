import AppKit
import SkitchoCore
import SwiftUI

/// Bridges the AppKit canvas to the SwiftUI shell: the bottom bar reads the zoom level and drives zoom actions
/// through this handle.
@MainActor @Observable
public final class CanvasHandle {
  public private(set) var zoom: Double = 1
  public private(set) weak var canvas: CanvasView?

  public init() {}

  func attach(_ canvas: CanvasView) {
    self.canvas = canvas
    zoom = canvas.zoom
    canvas.onZoomChange = { [weak self] value in self?.zoom = value }
  }

  public func zoomIn() { canvas?.zoomIn() }
  public func zoomOut() { canvas?.zoomOut() }
  public func actualSize() { canvas?.actualSize() }
  public func zoomToFit() { canvas?.zoomToFit() }
}

/// Hosts the scrollable `CanvasView` inside SwiftUI.
struct CanvasHost: NSViewRepresentable {
  let editor: EditorModel
  let handle: CanvasHandle

  func makeNSView(context: Context) -> NSScrollView {
    let (scrollView, canvas) = CanvasView.makeScrollView(editor: editor)
    handle.attach(canvas)
    // The canvas takes the keyboard (tool shortcuts, Delete, arrows) as soon as it is in a window.
    Task { @MainActor in canvas.window?.makeFirstResponder(canvas) }
    return scrollView
  }

  func updateNSView(_ nsView: NSScrollView, context: Context) {}
}

/// A clearly marked region reserved for a later task (tool palette, properties panel).
struct PlaceholderRegion: View {
  let title: String
  let systemImage: String
  var onDark = false

  var body: some View {
    let tint = onDark ? BrandColor.lightGray : BrandColor.mediumGray
    VStack(spacing: Spacing.xxs) {
      Image(systemName: systemImage)
        .font(Typography.body.font())
      Text(title)
        .font(Typography.caption.font(weight: .medium))
        .multilineTextAlignment(.center)
    }
    .foregroundStyle(tint.color)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(Spacing.xs)
    .overlay {
      RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
        .strokeBorder(tint.color.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(title) placeholder")
  }
}

/// The document window: tool palette (left), canvas (center, rounded surround), properties (right) and a
/// bottom bar with zoom and the resize panel. The palette and properties contents are placeholders until the
/// panels land.
public struct EditorWindowView: View {
  public static let sidebarWidth: CGFloat = Spacing.xxxl
  public static let propertiesWidth: CGFloat = 208

  private let editor: EditorModel
  @Environment(\.undoManager) private var undoManager
  @State private var handle = CanvasHandle()
  @State private var resize: ResizeModel?

  public init(document: SkitchoDocument) {
    self.editor = document.editor
  }

  /// Gives the editor the window's undo manager, so registrations dirty the document.
  @MainActor
  public static func bind(_ editor: EditorModel, to undoManager: UndoManager?) {
    if editor.undoManager !== undoManager { editor.undoManager = undoManager }
  }

  public var body: some View {
    HStack(spacing: 0) {
      PlaceholderRegion(title: "Tools", systemImage: "wrench.and.screwdriver", onDark: true)
        .padding(Spacing.xs)
        .frame(width: Self.sidebarWidth)
        .frame(maxHeight: .infinity)
        .background(BrandSemantic.sidebar.color)
      VStack(spacing: Spacing.xs) {
        HStack(spacing: Spacing.xs) {
          CanvasHost(editor: editor, handle: handle)
            .background(BrandSemantic.canvasSurround.color)
            .clipShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
            .frame(minWidth: 320, minHeight: 240)
          PlaceholderRegion(title: "Properties", systemImage: "slider.horizontal.3")
            .frame(width: Self.propertiesWidth)
        }
        bottomBar
      }
      .padding(Spacing.xs)
    }
    .background(BrandSemantic.windowBackground.color)
    .onAppear { Self.bind(editor, to: undoManager) }
    .onChange(of: undoManager) { _, new in Self.bind(editor, to: new) }
  }

  private var bottomBar: some View {
    HStack(spacing: Spacing.sm) {
      Text(sizeText)
        .font(Typography.caption.font())
        .foregroundStyle(BrandSemantic.caption.color)
      Spacer(minLength: Spacing.xs)
      if let resize {
        ResizeBar(model: resize)
      } else {
        Button("Resize…") { startResize() }
          .buttonStyle(CZButtonStyle(.secondary, size: .small))
          .help("Resize, rotate or flip the image")
        zoomControls
      }
    }
  }

  private var sizeText: String {
    let size = editor.document.canvasSize
    return "\(Int(size.width.rounded())) × \(Int(size.height.rounded())) px"
  }

  private var zoomControls: some View {
    HStack(spacing: Spacing.xxs) {
      Button {
        handle.zoomOut()
      } label: {
        Image(systemName: "minus")
      }
      .accessibilityLabel("Zoom out")
      Button("\(Int((handle.zoom * 100).rounded()))%") { handle.actualSize() }
        .frame(minWidth: 48)
        .help("Actual size")
      Button {
        handle.zoomIn()
      } label: {
        Image(systemName: "plus")
      }
      .accessibilityLabel("Zoom in")
      Button {
        handle.zoomToFit()
      } label: {
        Image(systemName: "arrow.up.left.and.down.right.magnifyingglass")
      }
      .help("Fit to window")
      .accessibilityLabel("Fit to window")
    }
    .buttonStyle(CZButtonStyle(.transparent, size: .small))
  }

  private func startResize() {
    let model = ResizeModel(editor: editor)
    model.onDismiss = { resize = nil }
    resize = model
  }
}
