import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Summon/dismiss the command palette. Default ⇧⌘V (user-rebindable in Settings).
    /// Option-only combos are avoided (macOS 15 FB15168205).
    static let togglePalette = Self("togglePalette", default: .init(.v, modifiers: [.command, .shift]))
}
