import SkitchoCore

/// Decides whether a key press switches the tool. Precedence, highest first:
/// 1. text editing in progress: every key goes to the text editor;
/// 2. the Text tool is active (not editing): typing creates text, so letters are never shortcuts;
/// 3. any other tool: a plain letter bound to a tool (V A T M H R U O L S P C) switches to it.
/// Command, Control and Option chords are never tool shortcuts (they belong to menus and special characters).
public enum ToolShortcutRouter {
  public static func tool(
    for key: ToolKey, modifiers: ToolModifiers, currentTool: Tool, isEditingText: Bool
  ) -> Tool? {
    guard !isEditingText, currentTool != .text else { return nil }
    guard modifiers.isDisjoint(with: [.command, .control, .option]) else { return nil }
    guard case .character(let character) = key else { return nil }
    return Tool.tool(forShortcut: character)
  }
}
