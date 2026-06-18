import SwiftUI

/// Spike command palette: search field + result list + keyboard/mouse selection.
/// Uses placeholder clips for now; Phase 1 swaps in the real clipboard store.
struct PaletteView: View {
    let onPaste: (String) -> Void
    let onClose: () -> Void

    @State private var query = ""
    @State private var selection = 0
    @FocusState private var searchFocused: Bool

    private let allClips = [
        "Hello, world!",
        "https://github.com/sindresorhus/KeyboardShortcuts",
        "func paste() { /* … */ }",
        "#4F46E5",
        "The quick brown fox jumps over the lazy dog."
    ]

    private var clips: [String] {
        query.isEmpty ? allClips : allClips.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search your clipboard…", text: $query)
                .textFieldStyle(.plain)
                .font(.title2)
                .padding(16)
                .focused($searchFocused)
                .onSubmit(pasteSelected)

            Divider()

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Array(clips.enumerated()), id: \.offset) { index, clip in
                        HStack {
                            Text(clip).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(
                            index == selection ? Color.accentColor.opacity(0.25) : .clear,
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { selection = index; pasteSelected() }
                    }
                }
                .padding(8)
            }
        }
        .frame(width: 640, height: 420)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .onAppear { searchFocused = true; selection = 0 }
        .onChange(of: query) { selection = 0 }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.return) { pasteSelected(); return .handled }
        .onKeyPress(.escape) { onClose(); return .handled }
    }

    private func move(_ delta: Int) {
        guard !clips.isEmpty else { return }
        selection = (selection + delta + clips.count) % clips.count
    }

    private func pasteSelected() {
        guard clips.indices.contains(selection) else { return }
        onPaste(clips[selection])
    }
}
