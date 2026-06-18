import SwiftUI

/// Command palette UI: search + result list over the live clipboard history.
struct PaletteView: View {
    let onPaste: (String) -> Void
    let onClose: () -> Void

    @ObservedObject private var monitor = ClipboardMonitor.shared
    @State private var query = ""
    @State private var selection = 0
    @FocusState private var searchFocused: Bool

    private var clips: [String] {
        let all = monitor.clips
        return query.isEmpty ? all : all.filter { $0.localizedCaseInsensitiveContains(query) }
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

            if clips.isEmpty {
                emptyState
            } else {
                resultList
            }

            footer
        }
        .frame(width: 640, height: 440)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .onAppear {
            selection = 0
            // Defer to the next runloop so the panel is key before grabbing focus.
            DispatchQueue.main.async { searchFocused = true }
        }
        .onChange(of: query) { selection = 0 }
        .onChange(of: clips.count) { if selection >= clips.count { selection = max(0, clips.count - 1) } }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.return) { pasteSelected(); return .handled }
        .onKeyPress(.escape) { onClose(); return .handled }
    }

    private var resultList: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(Array(clips.enumerated()), id: \.offset) { index, clip in
                    HStack {
                        Text(clip).lineLimit(1).truncationMode(.middle)
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

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "doc.on.clipboard")
                .font(.largeTitle).foregroundStyle(.secondary)
            Text("No clips yet").font(.headline)
            Text("Copy some text, then it appears here.")
                .font(.callout).foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        HStack {
            Text("↑↓ move · ⏎ paste · esc close")
            Spacer()
            Text("text only · more in Phase 1")
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
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
