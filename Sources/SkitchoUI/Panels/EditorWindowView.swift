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
  @discardableResult
  public func attachLabel(to id: UUID) -> Bool { canvas?.attachLabel(to: id) ?? false }
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

/// The document window: tool palette (left), canvas (center, rounded surround), properties (right) and a
/// bottom bar with zoom and the resize panel.
public struct EditorWindowView: View {
  public static let sidebarWidth: CGFloat = Spacing.xxxl
  public static let propertiesWidth: CGFloat = 208

  private let editor: EditorModel
  @Environment(\.undoManager) private var undoManager
  @State private var handle: CanvasHandle
  @State private var resize: ResizeModel?
  @State private var palette: ToolPaletteModel
  @State private var properties: PropertiesModel
  @State private var commands: EditorCommandModel
  @State private var dragOut: DragOutSource

  public init(document: SkitchoDocument) {
    self.editor = document.editor
    let handle = CanvasHandle()
    _handle = State(initialValue: handle)
    _commands = State(initialValue: EditorCommandModel(editor: document.editor, handle: handle))
    let editor = document.editor
    _dragOut = State(
      initialValue: DragOutSource(
        document: { editor.document },
        documentName: { [weak handle] in handle?.canvas?.window?.title }))
    _palette = State(initialValue: ToolPaletteModel(editor: document.editor))
    _properties = State(
      initialValue: PropertiesModel(
        editor: document.editor,
        attachLabel: { [weak handle] in
          handle?.attachLabel(to: $0) ?? false
        }))
  }

  /// Gives the editor the window's undo manager, so registrations dirty the document.
  @MainActor
  public static func bind(_ editor: EditorModel, to undoManager: UndoManager?) {
    if editor.undoManager !== undoManager { editor.undoManager = undoManager }
  }

  public var body: some View {
    HStack(spacing: 0) {
      ToolPalette(model: palette)
        .frame(width: Self.sidebarWidth)
        .frame(maxHeight: .infinity)
        .background(BrandSemantic.sidebar.color)
      VStack(spacing: Spacing.xs) {
        HStack(spacing: Spacing.xs) {
          CanvasHost(editor: editor, handle: handle)
            .background(BrandSemantic.canvasSurround.color)
            .clipShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
            .frame(minWidth: 320, minHeight: 240)
          PropertiesPanel(model: properties)
            .frame(width: Self.propertiesWidth)
        }
        bottomBar
      }
      .padding(Spacing.xs)
    }
    .background(BrandSemantic.windowBackground.color)
    .focusedSceneValue(\.editorCommands, commands)
    .alert(
      "Skitcho",
      isPresented: Binding(
        get: { commands.errorMessage != nil }, set: { if !$0 { commands.errorMessage = nil } })
    ) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(commands.errorMessage ?? "")
    }
    .onAppear {
      Self.bind(editor, to: undoManager)
      commands.beginResize = { startResize() }
      commands.presentExport = { presentExport() }
    }
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
        DragOutHandle(source: dragOut)
          .frame(width: 28, height: 22)
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

  private func presentExport() {
    let editor = editor
    let window = handle.canvas?.window
    ExportPresenter.present(
      document: { editor.document },
      suggestedName: DragOutSource.fileName(forDocumentName: window?.title),
      window: window,
      onError: { commands.errorMessage = $0 })
  }

  private func startResize() {
    let model = ResizeModel(editor: editor)
    model.onDismiss = { resize = nil }
    resize = model
  }
}
